# Centralized SES Identity Dashboard

Build organization-wide visibility into your Amazon SES email-sending posture across all AWS accounts in your Organization.

## Architecture

A centralized scanner in your management account discovers all member accounts, assumes a read-only role into each one, and collects SES identity information across all enabled AWS Regions. Results are stored in Amazon S3 (JSON Lines), queried with Amazon Athena, and visualized with Amazon QuickSight.

## Options

| Option | Best For | Scan Time |
|--------|----------|-----------|
| Option 1: Single Lambda | < 50 accounts | Sequential; must finish within the 15-minute Lambda timeout |
| Option 2: Step Functions | 50+ accounts | Parallel (up to 40 concurrent); ~3–5 minutes for 280 accounts |

## Repository Structure

```
ses-identity-dashboard/
├── README.md
├── LICENSE
├── option-1/
│   ├── ses-reader-role.yaml          # IAM role for member accounts (deploy via StackSets)
│   ├── ses-scanner-stack.yaml        # Scanner infrastructure (deploy to management account)
│   └── sample-athena-queries.sql     # Ready-to-use Athena queries
└── option-2/
    ├── ses-scanner-stepfunctions.yaml  # Step Functions version (deploy to management account)
    └── README.md                       # Option 2 specific instructions
```

## Quick Start (Option 1)

### Step 1: Deploy the IAM Role to Member Accounts

Deploy `option-1/ses-reader-role.yaml` via CloudFormation StackSets to all member accounts.

**Parameters:**
- `ManagementAccountId` — Your 12-digit management account ID
- `OrganizationId` — Your organization ID (`o-xxxxxxxxxx`); restricts assumption to principals in your org
- `ExternalId` — A unique secret you generate for this deployment (8–128 chars). Supply the **same** value to the scanner stack in Step 2. Do not reuse a sample value.
- `ScannerRoleName` — Leave the default (`SES-Identity-Scanner-Role`) unless you rename the scanner role

```bash
aws cloudformation create-stack-set \
  --stack-set-name ses-identity-reader-role \
  --template-body file://option-1/ses-reader-role.yaml \
  --parameters \
      ParameterKey=ManagementAccountId,ParameterValue=<YOUR_ACCOUNT_ID> \
      ParameterKey=OrganizationId,ParameterValue=o-xxxxxxxxxx \
      ParameterKey=ExternalId,ParameterValue=<YOUR_GENERATED_SECRET> \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false

aws cloudformation create-stack-instances \
  --stack-set-name ses-identity-reader-role \
  --deployment-targets OrganizationalUnitIds=<YOUR_ROOT_ID> \
  --regions us-east-1
```

### Step 2: Deploy the Scanner Stack

Deploy `option-1/ses-scanner-stack.yaml` to your management account.

**Parameters:**
- `OrganizationId` — Your organization ID (`o-xxxxxxxxxx`); scopes cross-account `sts:AssumeRole` via an `aws:ResourceOrgID` condition
- `ExternalId` — The same value you generated in Step 1
- `ScannerRoleName` — Must match Step 1 (default `SES-Identity-Scanner-Role`)
- `AlertEmail` — Email address that receives scan-error summaries and CloudWatch alarms
- `ScheduleExpression` — Scan frequency (default: `rate(1 day)`)

```bash
aws cloudformation deploy \
  --template-file option-1/ses-scanner-stack.yaml \
  --stack-name ses-identity-dashboard \
  --parameter-overrides \
      OrganizationId=o-xxxxxxxxxx \
      ExternalId=<YOUR_GENERATED_SECRET> \
      AlertEmail=you@example.com \
  --capabilities CAPABILITY_NAMED_IAM
```

After the stack is created, **confirm the SNS subscription** in the email sent to `AlertEmail`. Until you confirm, error notifications and alarms are not delivered.

### Step 3: Run the First Scan

```bash
aws lambda invoke \
  --function-name SES-Identity-Scanner-v2 \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/scan-output.json

cat /tmp/scan-output.json
```

### Step 4: Query with Athena

Open the Athena console, select the workgroup the stack creates (`<stack-name>-ses-identity`) — it enforces an encrypted results location inside the hardened scan-results bucket, so you do not set a query result location manually. Select the `ses_identity_dashboard` database and run:

```sql
SELECT account_id,
       COUNT(*) as total_identities,
       SUM(CASE WHEN verified THEN 1 ELSE 0 END) as verified_count,
       SUM(CASE WHEN dkim_status = 'SUCCESS' THEN 1 ELSE 0 END) as dkim_configured
FROM ses_identities
GROUP BY account_id
ORDER BY total_identities DESC;
```

## Data Schema

Each scan produces JSON Lines with the following fields:

| Field | Type | Description |
|-------|------|-------------|
| account_id | string | AWS account ID |
| region | string | AWS Region |
| identity_name | string | Domain name or email address |
| identity_type | string | DOMAIN or EMAIL_ADDRESS |
| verified | boolean | Verified for sending |
| dkim_status | string | SUCCESS, PENDING, FAILED, NOT_STARTED, TEMPORARY_FAILURE |
| dkim_signing_enabled | boolean | DKIM signing active |
| dkim_key_length | string | RSA key length (1024 or 2048) |
| mail_from_status | string | Custom MAIL FROM domain status |
| mail_from_domain | string | Custom MAIL FROM domain |
| sending_enabled | boolean | Sending enabled |
| scan_timestamp | string | ISO 8601 scan timestamp |

A run summary — accounts scanned, identities collected, and any per-account, per-region, or per-identity failures — is written to `scans/summary/latest.json` on every run so the dashboard can detect staleness and incompleteness. If accounts exist but zero identities are collected, the run fails without overwriting `scans/latest/` (the previous good scan is preserved) and the `SES-Scanner-Errors` alarm fires.

## Security

- **Cross-account trust is scoped to the scanner role only.** The reader role's trust policy requires all of: `aws:PrincipalArn` equal to the scanner role, `aws:PrincipalOrgID` equal to your organization, and a per-deployment `ExternalId`. It does not trust the management account's root broadly.
- **ExternalId is a per-deployment secret** passed as a `NoEcho` parameter — generate a unique value; do not hardcode or publish it.
- The reader role is strictly read-only, granting only `ses:ListEmailIdentities`, `ses:GetEmailIdentity`, and `ec2:DescribeRegions`.
- Cross-account `sts:AssumeRole` from the scanner is scoped with an `aws:ResourceOrgID` condition.
- Both S3 buckets enforce full public-access block, TLS-only access, SSE-S3 encryption, and lifecycle rules including noncurrent-version expiration.
- Athena queries run in an enforced, encrypted workgroup whose results land inside the hardened bucket.
- Scanner Lambda logs to an explicit CloudWatch log group with a finite retention period; SES identity names are not written to logs.
- StackSets auto-deployment covers new accounts automatically.

## Cost

| Component | Monthly Cost (280 accounts) |
|-----------|----------------------------|
| Lambda | ~$0.50 |
| S3 | ~$0.10 |
| Athena | ~$0.05 |
| Step Functions (Option 2) | ~$0.75 |
| **Total (without QuickSight)** | **~$1.40** |
| QuickSight (1 author) | $24.00 |

## Cleanup

```bash
# Delete scanner stack
aws cloudformation delete-stack --stack-name ses-identity-dashboard

# Delete StackSet instances then StackSet
aws cloudformation delete-stack-instances \
  --stack-set-name ses-identity-reader-role \
  --deployment-targets OrganizationalUnitIds=<YOUR_ROOT_ID> \
  --regions us-east-1 --no-retain-stacks

aws cloudformation delete-stack-set --stack-set-name ses-identity-reader-role
```

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

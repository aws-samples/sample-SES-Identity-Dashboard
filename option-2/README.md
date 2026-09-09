# Option 2: Step Functions with Parallel Map

For organizations with 50+ accounts where the single Lambda approach exceeds the 15-minute timeout.

## Prerequisites

- Complete Step 1 from Option 1 (deploy the IAM reader role via StackSets) — **only for `organization` scan mode**
- The SES-Identity-Reader role must exist in all member accounts (organization mode)
- Use the **same** `ExternalId` and `ScannerRoleName` you supplied to the reader-role StackSet

> **Standalone account?** Set `ScanMode` to `self` and skip the reader-role prerequisite entirely — the per-account scanner reads SES identities in its own account using its Lambda execution role.

## Deployment

```bash
aws cloudformation deploy \
  --template-file ses-scanner-stepfunctions.yaml \
  --stack-name ses-identity-dashboard-sfn \
  --parameter-overrides \
      ScanMode=organization \
      OrganizationId=o-xxxxxxxxxx \
      ExternalId=<YOUR_GENERATED_SECRET> \
      AlertEmail=you@example.com \
  --capabilities CAPABILITY_NAMED_IAM
```

After deployment, **confirm the SNS subscription** in the email sent to `AlertEmail`.

## Scan Modes

- **`organization`** (default) — discovers all active accounts via AWS Organizations and assumes the `SES-Identity-Reader` role in each. If AWS Organizations is not available, the scanner automatically falls back to a self-scan of the deploying account.
- **`self`** — scans only the account the stack is deployed into using the Lambda execution role. No `organizations:ListAccounts` call and no cross-account role assumption, so the reader-role StackSet (Step 1 of Option 1) is not needed.

## How It Works

1. EventBridge triggers the Step Functions state machine daily
2. **ListAccounts Lambda** — in `organization` mode, discovers all active accounts and returns a JSON array; in `self` mode (or when Organizations is unavailable), returns only the deploying account
3. **Map state** (inline, `MaxConcurrency: 40`) — processes accounts in parallel
4. **Per-Account Scanner Lambda** — scans one account across all enabled Regions; per-region and per-identity failures are reported in-band, not silently dropped. In `self` mode it reads its own account directly without assuming the reader role.
5. **Consolidate Lambda** — merges per-account results into `scans/latest/results.jsonl`, writes a run summary to `scans/summary/latest.json`, and **fails the execution** (preserving the previous `scans/latest/`) if accounts existed but zero identities were collected

## Concurrency and Scaling

The template uses an **inline** Map, which caps concurrency at **40** regardless of the `MaxConcurrency` value (bounded 1–40 by the parameter). To scale beyond 40 accounts in flight, switch the `ItemProcessor` `Mode` from `INLINE` to `DISTRIBUTED`. A Distributed Map additionally requires:

- `states:StartExecution`, `states:DescribeExecution`, `states:StopExecution` on the state machine (for the child executions), and
- S3 `ItemReader`/`ResultWriter` permissions.

At ~30 seconds per account and 40 in parallel, ~280 accounts complete in roughly 3–5 minutes.

## Retry Configuration

The Map state retries failed accounts automatically:
- ErrorEquals: States.ALL
- IntervalSeconds: 60
- MaxAttempts: 2
- BackoffRate: 2.0

## Monitoring

- Step Functions **execution logging (level ALL)** and **X-Ray tracing** are enabled for post-incident analysis.
- The Step Functions console shows per-account success/failure in the execution view.
- `SES-Scanner-SFN-Missed-Execution` fires if no successful execution occurs in 25 hours.
- `SES-Scanner-SFN-Execution-Failed` fires on a failed execution (including the fail-closed zero-identities path).
- SNS notifications are sent on partial failures and on the zero-identities failure.

## Athena & QuickSight

The data format is identical to Option 1. Option 2 creates its own Glue database `ses_identity_dashboard_sfn` (Option 1 uses `ses_identity_dashboard`) and its own enforced, encrypted Athena workgroup `<stack-name>-ses-identity-sfn` — select it in the Athena console. The distinct names let both options run in the same account. The same queries and QuickSight dashboards work by pointing at `ses_identity_dashboard_sfn`.

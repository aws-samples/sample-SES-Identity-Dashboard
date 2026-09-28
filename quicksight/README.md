# QuickSight dashboard definition (as code)

`ses-identity-analysis-definition.json` is an exported Amazon QuickSight
analysis/dashboard **definition** for the SES identity data. It reproduces the
"kitchen-sink" dashboard as code so you can recreate the same visuals in your
own account instead of building them by hand (see
[`../docs/quicksight-setup.md`](../docs/quicksight-setup.md) for the manual
walkthrough).

The definition contains only visual configuration — field references,
aggregations, calculated-field expressions, layout, and filter actions. It
holds **no row data, account IDs, ARNs, or other account-specific values**. The
one placeholder you must replace is the dataset ARN.

## What it builds

A single **Overview** sheet with 12 visuals:

| Visual | Type | Purpose |
|--------|------|---------|
| Total Identities | KPI | count of identities |
| Verified | KPI | sum of `verified` |
| DKIM OK | KPI | sum of `dkim_ok` (calculated) |
| Sending Enabled | KPI | sum of `sending_enabled` |
| Needs Attention | KPI | sum of `needs_attention` (calculated) |
| Identities by Account | Bar (horizontal) | drill hierarchy: account → region → identity type |
| Identities by Region | Bar (vertical) | count by region |
| DKIM Status by Account | Stacked bar | count by account, colored by `dkim_status` |
| MAIL FROM Status | Donut | count by `mail_from_status` |
| DKIM Key Length | Donut | count by `dkim_key_length` |
| Needs Attention | Table | rows where `needs_attention = 1` |
| Region x Account | Heat map | identity count, account (rows) x region (columns) |

All chart visuals have a click-to-filter action that filters every other visual
on the sheet (cross-visual filtering).

### Calculated fields

The definition declares two analysis-level calculated fields:

- `dkim_ok` = `ifelse({dkim_status}='SUCCESS',1,0)`
- `needs_attention` = `ifelse(verified=0 OR ({identity_type}='DOMAIN' AND {dkim_status}<>'SUCCESS'),1,0)`

## Prerequisites

Before importing this definition you need a QuickSight **dataset** built on the
Athena `ses_identities` table (see [`../docs/quicksight-setup.md`](../docs/quicksight-setup.md)).
The dataset must expose these columns (names must match exactly):

`account_id`, `region`, `identity_name`, `identity_type`, `verified`,
`dkim_signing_enabled`, `sending_enabled`, `dkim_status`, `dkim_key_length`,
`mail_from_status`, `mail_from_domain`, `scan_timestamp`.

`verified` and `sending_enabled` are numeric (0/1); the rest are strings.

## Applying the definition

1. Find your dataset ARN:

   ```bash
   aws quicksight list-data-sets --aws-account-id <YOUR_ACCOUNT_ID> \
     --region <YOUR_REGION> \
     --query "DataSetSummaries[?Name=='ses-identity-dataset'].Arn" --output text
   ```

2. Replace the placeholder ARN in `ses-identity-analysis-definition.json`:

   ```
   arn:aws:quicksight:us-east-1:111122223333:dataset/REPLACE_WITH_YOUR_DATASET_ID
   ```

   with your real dataset ARN. The `sesds` identifier (the
   `DataSetIdentifier` used throughout the file) can stay as-is.

3. Create an analysis from the definition:

   ```bash
   aws quicksight create-analysis \
     --aws-account-id <YOUR_ACCOUNT_ID> --region <YOUR_REGION> \
     --analysis-id ses-identity-analysis \
     --name "SES Identity Dashboard" \
     --definition file://ses-identity-analysis-definition.json
   ```

   Or publish it straight to a dashboard with `create-dashboard`
   (same `--definition` argument).

4. Check the result reached `CREATION_SUCCESSFUL` with no errors:

   ```bash
   aws quicksight describe-analysis \
     --aws-account-id <YOUR_ACCOUNT_ID> --region <YOUR_REGION> \
     --analysis-id ses-identity-analysis \
     --query "Analysis.{Status:Status,Errors:Errors}"
   ```

## Notes

- The example account ID `111122223333` in this file is a placeholder from the
  AWS documentation, not a real account.
- Schedule the dataset's SPICE refresh to run shortly after the daily scan so
  the dashboard reflects the latest data.

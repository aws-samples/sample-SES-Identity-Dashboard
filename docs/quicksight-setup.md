# QuickSight Dashboard Setup

This guide builds an Amazon QuickSight dashboard on top of the Athena table the
solution creates (`ses_identities`).

## Prerequisites

- The scanner stack is deployed and at least one scan has written data to
  `scans/latest/`.
- You can query the `ses_identities` table successfully in the Athena console.
- An Amazon QuickSight account (Standard or Enterprise) in the same Region.
- QuickSight has been granted access to Amazon Athena and to the scan-results
  S3 bucket (QuickSight console → Manage QuickSight → Security & permissions).

## 1. Create the dataset

1. Open the Amazon QuickSight console and choose **Datasets → New dataset**.
2. Choose **Athena** as the data source and give it a name (e.g.
   `ses-identity-dashboard`).
3. Select the database (`ses_identity_dashboard` for Option 1,
   `ses_identity_dashboard_sfn` for Option 2) and the `ses_identities` table.
4. Choose **Import to SPICE** for fast dashboard performance.

> **Prefer building it as code?** An exported dashboard definition that
> reproduces all of the visuals below (plus a drill-down account chart,
> a region heat map, and cross-visual filtering) is available at
> [`../quicksight/ses-identity-analysis-definition.json`](../quicksight/ses-identity-analysis-definition.json).
> See [`../quicksight/README.md`](../quicksight/README.md) for how to point it
> at your dataset and import it with `create-analysis` / `create-dashboard`.

## 2. Suggested visuals

| Visual | Type | Fields |
|--------|------|--------|
| Identities by account | Bar chart | `account_id` (X), count (Y) |
| Verified vs. unverified | Pie/donut | `verified` |
| DKIM status breakdown | Bar chart | `dkim_status` |
| Identities by Region and account | Heat map | `region` × `account_id` |
| Detail table | Table | all fields, with filters on `verified`, `dkim_status` |

## 3. Identities requiring attention

Add a filtered table or insight for rows where `verified = false` or
(`identity_type = 'DOMAIN'` and `dkim_status <> 'SUCCESS'`) to surface identities
that need remediation.

## 4. Schedule SPICE refresh

Schedule the SPICE refresh to run shortly after the daily scan completes so the
dashboard reflects the latest data. Set the refresh time after your
`ScheduleExpression` window.

## 5. Data freshness

The scanner writes `scans/summary/latest.json` with `accounts_scanned`,
`accounts_failed`, `total_identities`, and `scan_timestamp`. Consider surfacing
`scan_timestamp` in the dashboard so viewers can confirm the data is current,
and treat a run with `accounts_failed > 0` as incomplete rather than
authoritative.

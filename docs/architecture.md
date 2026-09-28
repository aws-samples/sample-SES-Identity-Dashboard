# Architecture

The Centralized SES Identity Dashboard runs entirely in your AWS Organization's
management account (or a delegated administrator). Member accounts contribute
only a read-only IAM role — no compute, no storage, no data-plane footprint.

## Workflow

```
                          Management account
  ┌───────────────────────────────────────────────────────────────┐
  │                                                                 │
  │  Amazon EventBridge (rate(1 day))                               │
  │        │ triggers                                               │
  │        ▼                                                        │
  │  Scanner  ──(1) organizations:ListAccounts──► AWS Organizations │
  │  (Lambda / Step Functions)                                      │
  │        │                                                        │
  │        │ (2) sts:AssumeRole (ExternalId + PrincipalOrgID)       │
  │        ▼                                                        │
  │  ┌──────────────┐   assume   ┌──────────────────────────────┐  │
  │  │ SES-Identity │◄───────────│ Member accounts              │  │
  │  │ -Reader role │            │ (SES-Identity-Reader role)   │  │
  │  └──────────────┘            └──────────────────────────────┘  │
  │        │ (3) ses:ListEmailIdentities / GetEmailIdentity         │
  │        │      across all enabled Regions                        │
  │        ▼                                                        │
  │  Amazon S3 (JSON Lines)                                         │
  │    scans/<date>/<time>/...jsonl   (history)                     │
  │    scans/latest/...jsonl          (current, queried by Athena)  │
  │    scans/summary/latest.json     (run summary: counts/failures)│
  │        │                                                        │
  │        ▼                                                        │
  │  Amazon Athena  ──►  Amazon QuickSight                          │
  │                                                                 │
  │  On any failure ► Amazon SNS ► email subscriber                 │
  │  CloudWatch alarms: missed run, Lambda Errors, DLQ depth        │
  └───────────────────────────────────────────────────────────────┘
```

## Steps

1. **Schedule.** Amazon EventBridge triggers the scanner on a daily schedule
   (`ScheduleExpression`, default `rate(1 day)`).
2. **Discover.** The scanner calls `organizations:ListAccounts` to enumerate all
   `ACTIVE` member accounts.
3. **Assume.** For each account it calls `sts:AssumeRole` on the
   `SES-Identity-Reader` role, supplying the per-deployment `ExternalId`. The
   role's trust policy additionally requires `aws:PrincipalOrgID` and the
   scanner role's `aws:PrincipalArn`.
4. **Scan.** Using the assumed credentials it calls `ec2:DescribeRegions` then
   `ses:ListEmailIdentities` and `ses:GetEmailIdentity` in each enabled Region.
5. **Store.** Results are written to Amazon S3 as JSON Lines — a timestamped
   historical object, a `scans/latest/` object for Athena, and a
   `scans/summary/latest.json` that records counts of scanned/failed accounts so
   the dashboard can distinguish "no identities" from "scan incomplete".
6. **Query and visualize.** Amazon Athena queries the `latest` prefix; Amazon
   QuickSight builds interactive dashboards on top.
7. **Alert.** Any per-account, per-region, or per-identity failure is published
   to Amazon SNS. CloudWatch alarms cover a missed run, Lambda `Errors` (which
   includes deliberate empty-result failures), and dead-letter-queue depth.

## Options

- **Option 1 — Single Lambda.** One function scans all accounts sequentially
  within the 15-minute Lambda timeout. Best for organizations with fewer than
  50 accounts.
- **Option 2 — Step Functions.** A state machine fans out across accounts with a
  Map state for parallel execution and per-account error isolation. Best for 50+
  accounts.

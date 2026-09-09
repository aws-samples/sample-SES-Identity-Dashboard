-- Centralized SES Identity Dashboard — Sample Athena Queries
-- Database: ses_identity_dashboard
-- Table: ses_identities

-- 1. Organization summary by account
SELECT account_id,
       COUNT(*) as total_identities,
       SUM(CASE WHEN verified THEN 1 ELSE 0 END) as verified_count,
       SUM(CASE WHEN dkim_status = 'SUCCESS' THEN 1 ELSE 0 END) as dkim_configured
FROM ses_identities
GROUP BY account_id
ORDER BY total_identities DESC;

-- 2. Identities requiring action (unverified or missing DKIM)
SELECT account_id, region, identity_name, identity_type, verified, dkim_status
FROM ses_identities
WHERE verified = false
   OR (identity_type = 'DOMAIN' AND dkim_status != 'SUCCESS')
ORDER BY account_id, region;

-- 3. Regional distribution
SELECT region,
       COUNT(*) as identity_count,
       SUM(CASE WHEN identity_type = 'DOMAIN' THEN 1 ELSE 0 END) as domains,
       SUM(CASE WHEN identity_type = 'EMAIL_ADDRESS' THEN 1 ELSE 0 END) as emails
FROM ses_identities
GROUP BY region
ORDER BY identity_count DESC;

-- 4. DKIM status breakdown
SELECT dkim_status, COUNT(*) as count
FROM ses_identities
WHERE identity_type = 'DOMAIN'
GROUP BY dkim_status
ORDER BY count DESC;

-- 5. Domains without DKIM signing enabled
SELECT account_id, region, identity_name, dkim_status, dkim_key_length
FROM ses_identities
WHERE identity_type = 'DOMAIN'
  AND dkim_signing_enabled = false;

-- 6. Identities with sending disabled
SELECT account_id, region, identity_name, identity_type
FROM ses_identities
WHERE sending_enabled = false;

-- 7. Custom MAIL FROM configuration status
SELECT account_id, identity_name, mail_from_domain, mail_from_status
FROM ses_identities
WHERE mail_from_domain != ''
ORDER BY mail_from_status;

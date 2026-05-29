-- v10: track single-domain and wildcard-subdomain MX capabilities separately.

ALTER TABLE domains ADD COLUMN IF NOT EXISTS supports_single BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE domains ADD COLUMN IF NOT EXISTS supports_wildcard BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE domains
SET supports_single = TRUE
WHERE domain_type IN ('exact', 'wildcard') AND supports_single = FALSE;

UPDATE domains
SET supports_wildcard = TRUE
WHERE domain_type = 'wildcard' AND supports_wildcard = FALSE;

UPDATE domains
SET is_active = (supports_single OR supports_wildcard),
    status = CASE
      WHEN supports_single OR supports_wildcard THEN 'active'
      WHEN status = 'active' THEN 'pending'
      ELSE status
    END;

CREATE INDEX IF NOT EXISTS idx_domains_active_single ON domains (supports_single) WHERE is_active = TRUE AND supports_single = TRUE;
CREATE INDEX IF NOT EXISTS idx_domains_active_wildcard ON domains (supports_wildcard) WHERE is_active = TRUE AND supports_wildcard = TRUE;

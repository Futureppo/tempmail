-- ============================================================
-- TempMail v8 迁移 — 多级/通配域名支持
-- ============================================================

ALTER TABLE domains ADD COLUMN IF NOT EXISTS domain_type VARCHAR(16) NOT NULL DEFAULT 'exact';
ALTER TABLE domains ADD COLUMN IF NOT EXISTS base_domain VARCHAR(255) NOT NULL DEFAULT '';

UPDATE domains
SET
  domain = LOWER(TRIM(TRAILING '.' FROM domain)),
  domain_type = CASE WHEN LOWER(TRIM(TRAILING '.' FROM domain)) LIKE '*.%' THEN 'wildcard' ELSE 'exact' END,
  base_domain = CASE
    WHEN LOWER(TRIM(TRAILING '.' FROM domain)) LIKE '*.%'
      THEN SUBSTRING(LOWER(TRIM(TRAILING '.' FROM domain)) FROM 3)
    ELSE LOWER(TRIM(TRAILING '.' FROM domain))
  END
WHERE base_domain = ''
   OR domain_type NOT IN ('exact', 'wildcard')
   OR domain <> LOWER(TRIM(TRAILING '.' FROM domain));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_domains_type'
  ) THEN
    ALTER TABLE domains
      ADD CONSTRAINT chk_domains_type CHECK (domain_type IN ('exact', 'wildcard'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_domains_base_domain_nonempty'
  ) THEN
    ALTER TABLE domains
      ADD CONSTRAINT chk_domains_base_domain_nonempty CHECK (base_domain <> '');
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_domains_active_type ON domains (domain_type) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_domains_base_domain ON domains (base_domain);

-- ============================================================
-- TempMail v4 迁移 — Linux DO Connect 登录与登录方式开关
-- ============================================================

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS linuxdo_id VARCHAR(128) UNIQUE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_linuxdo_id ON accounts (linuxdo_id) WHERE linuxdo_id IS NOT NULL;

INSERT INTO app_settings (key, value) VALUES ('key_login_enabled', 'true') ON CONFLICT DO NOTHING;
INSERT INTO app_settings (key, value) VALUES ('linuxdo_login_enabled', 'false') ON CONFLICT DO NOTHING;
INSERT INTO app_settings (key, value) VALUES ('linuxdo_client_id', '') ON CONFLICT DO NOTHING;
INSERT INTO app_settings (key, value) VALUES ('linuxdo_client_secret', '') ON CONFLICT DO NOTHING;
INSERT INTO app_settings (key, value) VALUES ('linuxdo_redirect_url', '') ON CONFLICT DO NOTHING;

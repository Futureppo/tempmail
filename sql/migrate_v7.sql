-- ============================================================
-- TempMail v7 迁移 — 自定义站点 Logo
-- ============================================================

INSERT INTO app_settings (key, value) VALUES ('site_logo_url', '') ON CONFLICT DO NOTHING;

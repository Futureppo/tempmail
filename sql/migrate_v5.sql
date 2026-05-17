-- ============================================================
-- TempMail v5 迁移 — 累计收件统计
-- ============================================================

INSERT INTO app_settings (key, value)
SELECT 'total_emails_received', COUNT(*)::TEXT FROM emails
ON CONFLICT DO NOTHING;

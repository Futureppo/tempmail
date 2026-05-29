#!/bin/bash
set -e

# ============================================================
# Postfix 容器入口脚本
# - 启动常驻 Go LMTP daemon (mail-receiver)
# - 动态从数据库加载域名到 virtual_domains regexp map
# - Postfix 通过内置 lmtp 客户端走 unix socket 投递
# ============================================================

echo "==> Starting Postfix mail receiver (LMTP daemon)..."

chmod +x /usr/local/bin/mail-receiver

# socket 必须放在 Postfix chroot 内的 private/ 目录
SOCK_DIR=/var/spool/postfix/private
mkdir -p "$SOCK_DIR"
SOCK_PATH="$SOCK_DIR/mail-receiver"
export LMTPD_SOCKET="$SOCK_PATH"
export API_URL="${API_URL:-http://api:8080}"
export LMTPD_HOSTNAME="${SMTP_HOSTNAME:-mail.example.com}"

# 启动 LMTP daemon（后台），异常退出会让容器整体重启
/usr/local/bin/mail-receiver &
RECEIVER_PID=$!

# 等待 socket 出现，最多 5 秒
for i in $(seq 1 50); do
    if [ -S "$SOCK_PATH" ]; then break; fi
    sleep 0.1
done
if [ ! -S "$SOCK_PATH" ]; then
    echo "mail-receiver socket not ready: $SOCK_PATH" >&2
    exit 1
fi
chown postfix:postfix "$SOCK_PATH" 2>/dev/null || true

# 生成初始虚拟域名列表（Postfix regexp map 格式）
DEFAULT_DOMAIN="${SMTP_HOSTNAME:-mail.example.com}"
python3 - "$DEFAULT_DOMAIN" > /etc/postfix/virtual_domains << 'PY'
import re
import sys

domain = sys.argv[1].strip().lower().rstrip(".")
print(f"/^{re.escape(domain)}$/     OK")
PY

cat > /usr/local/bin/sync-domains.sh << 'SCRIPT'
#!/bin/bash
set -e

API_URL="${API_URL:-http://api:8080}"
DOMAINS=$(curl -sf "$API_URL/internal/domains" 2>/dev/null || echo "")
if [ -n "$DOMAINS" ]; then
    echo "$DOMAINS" | python3 -c '
import json
import re
import sys

def normalize_domain(value):
    if not isinstance(value, str):
        return ""
    return value.strip().lower().rstrip(".")

def regexp_line(pattern):
    return f"/^{pattern}$/     OK"

def exact_pattern(domain):
    return re.escape(domain)

def wildcard_pattern(base_domain):
    labels = re.escape(base_domain)
    return rf"([^.]+(\.[^.]+)*\.)?{labels}"

def is_wildcard_record(record, domain):
    domain_type = str(record.get("domain_type", "")).strip().lower()
    return (
        domain.startswith("*.")
        or domain_type in {
            "wildcard",
            "wildcard_subdomain",
            "subdomain",
            "multi_level",
            "multi_level_subdomain",
        }
    )

def is_active_record(record):
    active = record.get("is_active", True)
    if isinstance(active, str):
        return active.strip().lower() not in {"", "0", "false", "no", "off"}
    return bool(active)

try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)

if isinstance(data, dict):
    records = data.get("domains", [])
elif isinstance(data, list):
    records = data
else:
    records = []

lines = []
seen = set()

for record in records:
    if not isinstance(record, dict):
        continue
    if not is_active_record(record):
        continue

    domain = normalize_domain(record.get("domain"))
    base_domain = normalize_domain(record.get("base_domain"))
    wildcard = is_wildcard_record(record, domain)

    if domain.startswith("*."):
        base_domain = normalize_domain(domain[2:])
    elif not base_domain:
        base_domain = domain

    if not base_domain:
        continue

    pattern = wildcard_pattern(base_domain) if wildcard else exact_pattern(base_domain)
    line = regexp_line(pattern)
    if line not in seen:
        seen.add(line)
        lines.append(line)

print("\n".join(lines))
' > /etc/postfix/virtual_domains.new
    if [ -s /etc/postfix/virtual_domains.new ]; then
        mv /etc/postfix/virtual_domains.new /etc/postfix/virtual_domains
        postfix reload 2>/dev/null || true
    fi
fi
SCRIPT
chmod +x /usr/local/bin/sync-domains.sh

/usr/local/bin/sync-domains.sh || true
(while true; do sleep 60; /usr/local/bin/sync-domains.sh; done) &

postconf -e "myhostname=${SMTP_HOSTNAME:-mail.example.com}"
postconf -e "virtual_mailbox_domains=regexp:/etc/postfix/virtual_domains"
postconf -e "virtual_transport=lmtp:unix:private/mail-receiver"

trap "kill $RECEIVER_PID 2>/dev/null; exit 0" TERM INT

postfix start

# 监控 receiver 进程：退出则停止 postfix，让容器重启
wait $RECEIVER_PID
echo "mail-receiver exited, stopping postfix" >&2
postfix stop
exit 1

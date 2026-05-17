#!/bin/bash
set -e

# ============================================================
# Postfix 容器入口脚本
# - 启动常驻 Go LMTP daemon (mail-receiver)
# - 动态从数据库加载域名到 virtual_domains
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

# 生成初始虚拟域名列表
echo "${SMTP_HOSTNAME:-mail.example.com}     OK" > /etc/postfix/virtual_domains

cat > /usr/local/bin/sync-domains.sh << 'SCRIPT'
#!/bin/bash
DOMAINS=$(curl -sf http://api:8080/internal/domains 2>/dev/null || echo "")
if [ -n "$DOMAINS" ]; then
    echo "$DOMAINS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for d in data.get('domains', []):
    if d.get('is_active', False):
        print(f\"{d['domain']}     OK\")
" > /etc/postfix/virtual_domains.new
    if [ -s /etc/postfix/virtual_domains.new ]; then
        mv /etc/postfix/virtual_domains.new /etc/postfix/virtual_domains
        postmap /etc/postfix/virtual_domains
        postfix reload 2>/dev/null || true
    fi
fi
SCRIPT
chmod +x /usr/local/bin/sync-domains.sh

postmap /etc/postfix/virtual_domains
(while true; do sleep 60; /usr/local/bin/sync-domains.sh; done) &

postconf -e "myhostname=${SMTP_HOSTNAME:-mail.example.com}"
postconf -e "virtual_mailbox_domains=hash:/etc/postfix/virtual_domains"
postconf -e "virtual_transport=lmtp:unix:private/mail-receiver"

trap "kill $RECEIVER_PID 2>/dev/null; exit 0" TERM INT

postfix start

# 监控 receiver 进程：退出则停止 postfix，让容器重启
wait $RECEIVER_PID
echo "mail-receiver exited, stopping postfix" >&2
postfix stop
exit 1

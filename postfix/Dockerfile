FROM golang:1.23-alpine AS receiver-builder

WORKDIR /build
COPY postfix/mail-receiver.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /build/mail-receiver mail-receiver.go

# ============================================================
# Postfix 收件容器
# ============================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
    postfix \
    python3 \
    curl \
    ca-certificates \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# 复制配置
COPY postfix/main.cf /etc/postfix/main.cf
COPY postfix/master.cf /etc/postfix/master.cf
COPY --from=receiver-builder /build/mail-receiver /usr/local/bin/mail-receiver
COPY postfix/entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/mail-receiver /entrypoint.sh

# 创建虚拟域名目录
RUN touch /etc/postfix/virtual_domains && postmap /etc/postfix/virtual_domains

EXPOSE 25

CMD ["/entrypoint.sh"]

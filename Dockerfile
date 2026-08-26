FROM alpine:3.20

LABEL maintainer="your-name"
LABEL description="Xray VMess WebSocket + Cloudflare Tunnel (Alpine)"

# 默认配置（可通过环境变量覆盖）
ENV XRAY_VERSION="v26.3.27" \
    VMESS_PORT="54321" \
    UUID="" \
    DOMAIN="novre.rahn.top" \
    ARGO_TOKEN="" \
    WS_PATH="/vmws"

# 安装依赖
RUN apk add --no-cache \
        curl \
        wget \
        unzip \
        ca-certificates \
        openssl \
        bash \
        tzdata \
    && update-ca-certificates

# 创建目录
RUN mkdir -p /etc/xray /var/log/xray /usr/local/bin

# 复制启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 下载 Xray + cloudflared（根据架构自动选择）
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
        x86_64|amd64)  XRAY_ARCH="64";        CF_ARCH="amd64" ;; \
        aarch64|arm64) XRAY_ARCH="arm64-v8a"; CF_ARCH="arm64" ;; \
        armv7l|armv7)  XRAY_ARCH="arm32-v7a"; CF_ARCH="arm" ;; \
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac; \
    \
    # 下载 Xray
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"; \
    wget -qO /tmp/xray.zip "$XRAY_URL"; \
    unzip -o /tmp/xray.zip -d /tmp/xray; \
    install -m 755 /tmp/xray/xray /usr/local/bin/xray; \
    rm -rf /tmp/xray /tmp/xray.zip; \
    \
    # 下载 cloudflared
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"; \
    wget -qO /usr/local/bin/cloudflared "$CF_URL"; \
    chmod +x /usr/local/bin/cloudflared; \
    \
    # 验证
    /usr/local/bin/xray version; \
    /usr/local/bin/cloudflared version

# 健康检查（可选）
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD pgrep -x xray >/dev/null && pgrep -x cloudflared >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]

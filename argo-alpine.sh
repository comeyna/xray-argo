#!/bin/sh

set -e

# =========================================================
# Xray + Cloudflare Tunnel
# Alpine Linux
# Xray: 26.3.27
# Protocol: VMess + WebSocket
# Init: OpenRC
# =========================================================

# =========================
# 用户配置
# =========================

XRAY_VERSION="v26.3.27"

VMESS_PORT=""

# 留空则自动生成 UUID
UUID=""

DOMAIN=""

# 请填写新的 Cloudflare Tunnel Token
ARGO_TOKEN=""

WS_PATH="/vmws"

# =========================
# 检查 root
# =========================

if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 运行此脚本"
    exit 1
fi

# =========================
# Alpine 检查
# =========================

if [ ! -f /etc/alpine-release ]; then
    echo "错误：当前系统不是 Alpine Linux"
    exit 1
fi

echo "======================================"
echo "Alpine Linux"
echo "======================================"

cat /etc/alpine-release

# =========================
# 安装依赖
# =========================

echo
echo "======================================"
echo "安装依赖"
echo "======================================"

apk update

apk add --no-cache \
    curl \
    wget \
    unzip \
    ca-certificates \
    openssl \
    bash

update-ca-certificates

# =========================
# CPU 架构
# =========================

ARCH="$(uname -m)"

case "$ARCH" in

    x86_64|amd64)
        XRAY_ARCH="64"
        CF_ARCH="amd64"
        ;;

    aarch64|arm64)
        XRAY_ARCH="arm64-v8a"
        CF_ARCH="arm64"
        ;;

    armv7l|armv7)
        XRAY_ARCH="arm32-v7a"
        CF_ARCH="arm"
        ;;

    *)
        echo "不支持的 CPU 架构：$ARCH"
        exit 1
        ;;

esac

echo
echo "CPU 架构：$ARCH"

# =========================
# UUID
# =========================

if [ -z "$UUID" ]; then
    UUID="$(cat /proc/sys/kernel/random/uuid)"
fi

echo
echo "UUID：$UUID"

# =========================
# 创建目录
# =========================

mkdir -p /etc/xray
mkdir -p /var/log/xray

# =========================
# 下载 Xray
# =========================

echo
echo "======================================"
echo "安装 Xray ${XRAY_VERSION}"
echo "======================================"

XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"

rm -f /tmp/xray.zip
rm -rf /tmp/xray

mkdir -p /tmp/xray

wget \
    --show-progress \
    "$XRAY_URL" \
    -O /tmp/xray.zip

unzip -o /tmp/xray.zip -d /tmp/xray

install -m 755 /tmp/xray/xray /usr/local/bin/xray

# =========================
# Xray 配置
# =========================

echo
echo "======================================"
echo "生成 Xray 配置"
echo "======================================"

cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },

  "inbounds": [
    {
      "tag": "vmess-ws",

      "listen": "127.0.0.1",
      "port": ${VMESS_PORT},

      "protocol": "vmess",

      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },

      "streamSettings": {
        "network": "ws",

        "security": "none",

        "wsSettings": {
          "path": "${WS_PATH}"
        }
      }
    }
  ],

  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
EOF

# =========================
# 检查 Xray
# =========================

echo
echo "======================================"
echo "检查 Xray 配置"
echo "======================================"

xray run -test -config /etc/xray/config.json

echo
echo "Xray 配置检查通过"

# =========================
# OpenRC Xray 服务
# =========================

echo
echo "======================================"
echo "创建 Xray OpenRC 服务"
echo "======================================"

cat > /etc/init.d/xray <<'EOF'
#!/sbin/openrc-run

name="xray"
description="Xray VMess WebSocket"

command="/usr/local/bin/xray"
command_args="run -config /etc/xray/config.json"

command_background="yes"

pidfile="/run/${RC_SVCNAME}.pid"

output_log="/var/log/xray/xray.log"
error_log="/var/log/xray/xray-error.log"

depend() {
    need net
    after firewall
}
EOF

chmod +x /etc/init.d/xray

# =========================
# 安装 Cloudflared
# =========================

echo
echo "======================================"
echo "安装 Cloudflared"
echo "======================================"

CLOUDFLARED="/usr/local/bin/cloudflared"

if [ "$CF_ARCH" = "amd64" ]; then

    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"

elif [ "$CF_ARCH" = "arm64" ]; then

    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"

elif [ "$CF_ARCH" = "arm" ]; then

    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"

fi

rm -f "$CLOUDFLARED"

wget \
    --show-progress \
    "$CF_URL" \
    -O "$CLOUDFLARED"

chmod +x "$CLOUDFLARED"

# =========================
# Cloudflared 检查
# =========================

echo
echo "======================================"
echo "Cloudflared 版本"
echo "======================================"

"$CLOUDFLARED" version

# =========================
# 检查 Token
# =========================

if [ -z "$ARGO_TOKEN" ] || [ "$ARGO_TOKEN" = "你的新Token" ]; then

    echo
    echo "错误：没有填写 Cloudflare Tunnel Token"
    echo
    echo '请修改：'
    echo
    echo 'ARGO_TOKEN="你的新Token"'
    echo

    exit 1

fi

# =========================
# OpenRC Argo 服务
# =========================

echo
echo "======================================"
echo "创建 Cloudflare Tunnel OpenRC 服务"
echo "======================================"

cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run

name="argo"
description="Cloudflare Tunnel"

command="/usr/local/bin/cloudflared"

command_args="tunnel --no-autoupdate run --token ${ARGO_TOKEN}"

command_background="yes"

pidfile="/run/\${RC_SVCNAME}.pid"

output_log="/var/log/argo.log"
error_log="/var/log/argo-error.log"

depend() {
    need net
    after xray
}
EOF

chmod +x /etc/init.d/argo

# =========================
# OpenRC 服务配置
# =========================

echo
echo "======================================"
echo "配置 OpenRC"
echo "======================================"

rc-update add xray default
rc-update add argo default

# =========================
# 启动 Xray
# =========================

echo
echo "======================================"
echo "启动 Xray"
echo "======================================"

rc-service xray restart

sleep 2

if rc-service xray status >/dev/null 2>&1; then

    echo "Xray 启动成功"

else

    echo "Xray 启动失败"
    echo
    tail -50 /var/log/xray/xray-error.log 2>/dev/null || true
    exit 1

fi

# =========================
# 启动 Cloudflare Tunnel
# =========================

echo
echo "======================================"
echo "启动 Cloudflare Tunnel"
echo "======================================"

rc-service argo restart

sleep 3

if rc-service argo status >/dev/null 2>&1; then

    echo "Cloudflare Tunnel 启动成功"

else

    echo "Cloudflare Tunnel 启动失败"
    echo
    tail -50 /var/log/argo-error.log 2>/dev/null || true
    exit 1

fi

# =========================
# 检查监听端口
# =========================

echo
echo "======================================"
echo "检查 Xray 监听"
echo "======================================"

if command -v ss >/dev/null 2>&1; then
    ss -lntp | grep ":${VMESS_PORT}" || true
else
    echo "系统没有 ss，跳过端口检查"
fi

# =========================
# 最终信息
# =========================

echo
echo
echo "======================================"
echo "       Xray + Cloudflare Tunnel"
echo "          安装完成"
echo "======================================"
echo
echo "系统：       Alpine Linux"
echo "Xray：       ${XRAY_VERSION}"
echo "协议：       VMess"
echo "传输：       WebSocket"
echo "本地端口：   ${VMESS_PORT}"
echo "UUID：       ${UUID}"
echo "WS Path：    ${WS_PATH}"
echo
echo "域名：       ${DOMAIN}"
echo "外部端口：   443"
echo "TLS：        Cloudflare"
echo
echo "======================================"
echo "客户端参数"
echo "======================================"
echo
echo "地址：       ${DOMAIN}"
echo "端口：       443"
echo "UUID：       ${UUID}"
echo "协议：       VMess"
echo "Network：    ws"
echo "Path：       ${WS_PATH}"
echo "TLS：        TLS"
echo "SNI：        ${DOMAIN}"
echo
echo "======================================"
echo "服务管理"
echo "======================================"
echo
echo "Xray 状态："
echo "rc-service xray status"
echo
echo "Argo 状态："
echo "rc-service argo status"
echo
echo "重启 Xray："
echo "rc-service xray restart"
echo
echo "重启 Argo："
echo "rc-service argo restart"
echo
echo "Xray 日志："
echo "tail -f /var/log/xray/xray.log"
echo
echo "Xray 错误日志："
echo "tail -f /var/log/xray/xray-error.log"
echo
echo "Argo 日志："
echo "tail -f /var/log/argo.log"
echo
echo "Argo 错误日志："
echo "tail -f /var/log/argo-error.log"
echo
echo "======================================"

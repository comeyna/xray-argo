#!/bin/sh

set -e

# =========================================================
# Xray + Cloudflare Tunnel 优化版
# Alpine Linux + OpenRC
# Protocol: VLESS + WebSocket
# Xray: 26.3.27
# =========================================================

# =========================
# 用户配置（请按需修改）
# =========================

XRAY_VERSION="v26.3.27"
VMESS_PORT="10086"                 # 本地监听端口（可改）
UUID="a80808ef-cbe5-4d5a-a623-89e2638455e5"   # 留空则自动生成
DOMAIN="rc.rahn.top"
WS_PATH="/rcrahn"

# 重要：请重新生成新的 Token 后再填写（旧 Token 已暴露）
ARGO_TOKEN="eyJhIjoiZTZiOGQwZmQ2ZGNiMGEyMGM0MjFkZmQzMDA1MTYwZWEiLCJ0IjoiYWE4MGJhZjgtZWE1Mi00NTdlLWFmMGMtM2MyZjJhYWNiYmZmIiwicyI6IlltRTRNMkZpWVRJdE1qQXhOUzAwTVRJM0xXRXlObU10TXpBMVl6UmpPREkxTUdObCJ9"

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
echo "系统信息"
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
apk add --no-cache curl wget unzip ca-certificates openssl bash
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

echo "CPU 架构：$ARCH"

# =========================
# UUID
# =========================
if [ -z "$UUID" ]; then
    UUID="$(cat /proc/sys/kernel/random/uuid)"
fi
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

wget --show-progress "$XRAY_URL" -O /tmp/xray.zip
unzip -o /tmp/xray.zip -d /tmp/xray
install -m 755 /tmp/xray/xray /usr/local/bin/xray

# =========================
# 生成优化后的 Xray 配置（已加入 DNS）
# =========================
echo
echo "======================================"
echo "生成优化 Xray 配置 (VLESS + WS + DNS)"
echo "======================================"

cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "https+local://8.8.8.8/dns-query",
      "localhost"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": ${VMESS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${WS_PATH}",
          "headers": {
            "Host": "${DOMAIN}"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": false
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# =========================
# 检查配置
# =========================
echo
echo "检查 Xray 配置..."
xray run -test -config /etc/xray/config.json
echo "Xray 配置检查通过"

# =========================
# OpenRC Xray 服务
# =========================
echo
echo "创建 Xray OpenRC 服务"
cat > /etc/init.d/xray <<'EOF'
#!/sbin/openrc-run

name="xray"
description="Xray VLESS WebSocket"

command="/usr/local/bin/xray"
command_args="run -config /etc/xray/config.json"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/xray/access.log"
error_log="/var/log/xray/error.log"

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

case "$CF_ARCH" in
    amd64)  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
    arm64)  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
    arm)    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
esac

rm -f "$CLOUDFLARED"
wget --show-progress "$CF_URL" -O "$CLOUDFLARED"
chmod +x "$CLOUDFLARED"
"$CLOUDFLARED" version

# =========================
# 检查 Token
# =========================
if [ -z "$ARGO_TOKEN" ] || [ "$ARGO_TOKEN" = "你的新Token" ]; then
    echo
    echo "错误：请填写有效的 Cloudflare Tunnel Token"
    exit 1
fi

# =========================
# OpenRC Argo 服务
# =========================
echo
echo "创建 Cloudflare Tunnel OpenRC 服务"

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
# 启用并启动服务
# =========================
echo
echo "配置 OpenRC 并启动服务"
rc-update add xray default
rc-update add argo default

rc-service xray restart
sleep 2

if ! rc-service xray status >/dev/null 2>&1; then
    echo "Xray 启动失败"
    tail -30 /var/log/xray/error.log 2>/dev/null || true
    exit 1
fi
echo "Xray 启动成功"

rc-service argo restart
sleep 3

if ! rc-service argo status >/dev/null 2>&1; then
    echo "Cloudflare Tunnel 启动失败"
    tail -30 /var/log/argo-error.log 2>/dev/null || true
    exit 1
fi
echo "Cloudflare Tunnel 启动成功"

# =========================
# 最终信息
# =========================
echo
echo "======================================"
echo "       安装完成（优化版）"
echo "======================================"
echo
echo "协议：       VLESS + WebSocket"
echo "本地端口：   ${VMESS_PORT}"
echo "UUID：       ${UUID}"
echo "WS Path：    ${WS_PATH}"
echo "域名：       ${DOMAIN}"
echo
echo "---------- 客户端参数 ----------"
echo "地址：       ${DOMAIN}  （推荐改用 Cloudflare 优选 IP）"
echo "端口：       443"
echo "UUID：       ${UUID}"
echo "协议：       VLESS"
echo "Network：    ws"
echo "Path：       ${WS_PATH}"
echo "TLS：        开启"
echo "SNI / Host： ${DOMAIN}"
echo "Fingerprint：chrome（推荐）"
echo "ALPN：       h2,http/1.1"
echo
echo "---------- 服务管理 ----------"
echo "rc-service xray status"
echo "rc-service argo status"
echo "rc-service xray restart"
echo "rc-service argo restart"
echo
echo "日志："
echo "tail -f /var/log/xray/error.log"
echo "tail -f /var/log/argo-error.log"
echo
echo "======================================"
echo "注意：请尽快在 Cloudflare 后台重新生成 Tunnel Token 并更新脚本！"
echo "======================================"

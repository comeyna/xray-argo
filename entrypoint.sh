#!/bin/bash
set -e

echo "======================================"
echo "Xray + Cloudflare Tunnel (Docker)"
echo "======================================"

# UUID 处理：未设置则自动生成
if [ -z "$UUID" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "自动生成 UUID: $UUID"
else
    echo "使用指定 UUID: $UUID"
fi

# 检查必要参数
if [ -z "$ARGO_TOKEN" ]; then
    echo "错误：必须设置环境变量 ARGO_TOKEN"
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "警告：DOMAIN 未设置，客户端连接时需要自己填写域名"
fi

# 生成 Xray 配置
cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
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

echo "Xray 配置已生成"

# 测试配置
/usr/local/bin/xray run -test -config /etc/xray/config.json

# 启动 Xray（后台）
echo "启动 Xray..."
/usr/local/bin/xray run -config /etc/xray/config.json &
XRAY_PID=$!

# 等待 Xray 启动
sleep 2
if ! kill -0 $XRAY_PID 2>/dev/null; then
    echo "Xray 启动失败"
    cat /var/log/xray/error.log 2>/dev/null || true
    exit 1
fi
echo "Xray 已启动 (PID: $XRAY_PID)"

# 启动 Cloudflare Tunnel（前台）
echo "启动 Cloudflare Tunnel..."
echo "域名: ${DOMAIN}"
echo "本地端口: ${VMESS_PORT}"
echo "WS Path: ${WS_PATH}"
echo "UUID: ${UUID}"
echo "======================================"

exec /usr/local/bin/cloudflared tunnel --no-autoupdate run --token "${ARGO_TOKEN}"

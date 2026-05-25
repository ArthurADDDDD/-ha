#!/data/data/com.termux/files/usr/bin/bash
# scripts/run-serveo.sh — 启动 Serveo SSH 隧道（后台 + 自动重连）
set -euo pipefail

DOMAIN="YOUR_SERVEO_SUBDOMAIN"
LOGFILE="${HOME}/HomeAssistant-Termux/serveo.log"
PIDFILE="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/serveo-ha.pid"

# 杀掉旧进程
if [ -f "$PIDFILE" ]; then
    OLDPID=$(cat "$PIDFILE")
    kill -9 "$OLDPID" 2>/dev/null || true
    rm -f "$PIDFILE"
fi
pkill -f "ssh.*serveo.*8123" 2>/dev/null || true
sleep 0.5

echo "[INFO] 启动 Serveo 隧道: https://${DOMAIN}.serveousercontent.com -> localhost:8123"

# 自动重连循环
(
  while true; do
    ssh -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -i ~/.ssh/id_ed25519 \
        -R "${DOMAIN}:80:localhost:8123" \
        serveo.net \
        >> "$LOGFILE" 2>&1
    echo "[WARN] Tunnel dropped, reconnecting in 5s..." >> "$LOGFILE"
    sleep 5
  done
) &
TUNNEL_PID=$!
echo $TUNNEL_PID > "$PIDFILE"

sleep 3
if kill -0 "$TUNNEL_PID" 2>/dev/null; then
    echo "[OK]   Serveo 隧道已启动 (PID: $TUNNEL_PID)"
    echo "      公网地址: https://${DOMAIN}.serveousercontent.com"
    echo "      日志文件: $LOGFILE"
else
    echo "[ERROR] Serveo 隧道启动失败"
    exit 1
fi

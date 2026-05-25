#!/data/data/com.termux/files/usr/bin/bash
# scripts/run-ngrok.sh — 启动 ngrok 隧道（后台运行 + 日志）
set -euo pipefail

DOMAIN="YOUR_NGROK_DOMAIN"
LOGFILE="/data/data/com.termux/files/home/HomeAssistant-Termux/ngrok.log"
PIDFILE="/data/data/com.termux/files/usr/tmp/ngrok-ha.pid"

# 杀掉旧进程
if [ -f "$PIDFILE" ]; then
    OLDPID=$(cat "$PIDFILE")
    if kill -0 "$OLDPID" 2>/dev/null; then
        echo "[INFO] 停止旧 ngrok 进程 (PID: $OLDPID)"
        kill "$OLDPID" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PIDFILE"
fi

# 清理残留的 ngrok 进程
pkill -f "ngrok http.*8123" 2>/dev/null || true
sleep 0.5

echo "[INFO] 启动 ngrok: https://${DOMAIN} -> http://localhost:8123"
nohup ngrok http --url="${DOMAIN}" 8123 > "$LOGFILE" 2>&1 &
NGROK_PID=$!
echo $NGROK_PID > "$PIDFILE"

sleep 2
if kill -0 "$NGROK_PID" 2>/dev/null; then
    echo "[OK]   ngrok 已启动 (PID: $NGROK_PID)"
    echo "      公网地址: https://${DOMAIN}"
    echo "      日志文件: ${LOGFILE}"
else
    echo "[ERROR] ngrok 启动失败，查看日志: ${LOGFILE}"
    tail -20 "${LOGFILE}"
    exit 1
fi

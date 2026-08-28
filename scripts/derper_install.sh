#!/usr/bin/env bash
set -e

# ==============================================================================
# Tailscale DERP 一键安装与 SysV Service 注册脚本 (完全可配置版)
# 支持通过环境变量或脚本参数自定义安装路径、日志路径、端口和域名
# ==============================================================================

# ----------------- 可配置参数区 -----------------
# 优先级: 环境变量 > 脚本参数 ($1, $2, $3, $4) > 默认值
DOMAIN="${DOMAIN:-${1:-rmlb1495562.bohrium.tech}}"           # DERP 域名
PORT="${PORT:-${2:-50003}}"                                  # DERP 监听端口
APP_DIR="${APP_DIR:-${3:-/root/derp}}"                       # DERP 安装与数据存储目录
LOG_FILE="${LOG_FILE:-${4:-${APP_DIR}/derper.log}}"          # DERP 运行日志路径

# 派生路径 (亦可通过环境变量直接指定)
CERTS_DIR="${CERTS_DIR:-${APP_DIR}/certs}"                  # SSL 证书目录
PID_FILE="${PID_FILE:-${APP_DIR}/derper.pid}"                # PID 文件路径
LOG_DIR="$(dirname "${LOG_FILE}")"
# -----------------------------------------------

# 卸载 DERP 服务
function do_uninstall {
    echo "=================================================="
    echo "🗑️  开始卸载 Tailscale DERP 服务..."
    echo "=================================================="

    if [ -f "/etc/init.d/derper" ]; then
        service derper stop 2>/dev/null || true
        rm -f /etc/init.d/derper
        echo "✅ 已注销并删除 /etc/init.d/derper"
    fi

    pkill -9 -f "derper -hostname" 2>/dev/null || true

    read -r -p "是否删除数据与证书目录 (${APP_DIR})? [y/N]: " clean_data
    if [[ "$clean_data" =~ ^[Yy]$ ]]; then
        rm -rf "${APP_DIR}"
        echo "✅ 已清理目录: ${APP_DIR}"
    else
        echo "ℹ️  已保留目录: ${APP_DIR}"
    fi

    echo "🎉 Tailscale DERP 卸载完成！"
    exit 0
}

# 命令分发
ACTION="${1:-}"
case "$ACTION" in
    uninstall|-u|--uninstall|remove)
        do_uninstall
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0 [域名] [端口] [安装目录] [日志路径] # 安装并启动 DERP 服务"
        echo "  sudo $0 uninstall                         # 停止并卸载 DERP 服务"
        exit 0
        ;;
esac

echo "=================================================="
echo "🚀 开始安装与配置 Tailscale DERP"
echo "📌 域名 (DOMAIN):      ${DOMAIN}"
echo "🔌 端口 (PORT):        ${PORT}"
echo "📂 安装目录 (APP_DIR): ${APP_DIR}"
echo "🔐 证书目录 (CERTS):   ${CERTS_DIR}"
echo "📄 日志文件 (LOG):     ${LOG_FILE}"
echo "🆔 PID 文件 (PID):     ${PID_FILE}"
echo "=================================================="

# 1. 目录准备与基础依赖检查
mkdir -p "${APP_DIR}" "${CERTS_DIR}" "${LOG_DIR}"

if ! command -v go &>/dev/null; then
    if [ -f "/root/go/go1.26.3/bin/go" ]; then
        export PATH="/root/go/go1.26.3/bin:$PATH"
    elif [ -f "/usr/local/go/bin/go" ]; then
        export PATH="/usr/local/go/bin:$PATH"
    elif [ -f "/root/go/bin/go" ]; then
        export PATH="/root/go/bin:$PATH"
    fi
fi

if ! command -v go &>/dev/null; then
    echo "❌ 未检测到 Go 环境，请先安装 Go 后重试！"
    exit 1
fi

if ! command -v openssl &>/dev/null; then
    echo "📦 正在安装 openssl..."
    apt-get update -y && apt-get install -y openssl || true
fi

# 2. 编译并安装 derper 二进制
echo "⚙️ 正在编译安装 derper..."
export GOPROXY="https://goproxy.cn,direct"
export GOSUMDB="sum.golang.google.cn"
export GOTOOLCHAIN="local"

go install tailscale.com/cmd/derper@v1.76.6

DERPER_BIN="$(go env GOPATH)/bin/derper"
if [ ! -f "${DERPER_BIN}" ]; then
    DERPER_BIN="$(which derper 2>/dev/null || true)"
fi

if [ ! -f "${DERPER_BIN}" ]; then
    echo "❌ 未找到编译好的 derper 二进制！"
    exit 1
fi
echo "✅ derper 安装成功: ${DERPER_BIN}"

# 3. 生成自签名 SSL 证书
echo "🔐 正在生成自签名 SSL 证书..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "${CERTS_DIR}/${DOMAIN}.key" \
  -out "${CERTS_DIR}/${DOMAIN}.crt" \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN}" 2>/dev/null
echo "✅ 证书生成完成: ${CERTS_DIR}/${DOMAIN}.crt"

# 4. 注册 /etc/init.d/derper 服务脚本 (完全参考 gold_monitor 结构)
echo "📝 正在生成并注册 /etc/init.d/derper 服务..."
cat << EOF > /etc/init.d/derper
#!/bin/sh
### BEGIN INIT INFO
# Provides:          derper
# Required-Start:    \$network \$local_fs \$remote_fs
# Required-Stop:     \$network \$local_fs \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Tailscale DERP Server
# Description:       Tailscale Custom DERP Relay Server
### END INIT INFO

APP_DIR="${APP_DIR}"
DERPER_BIN="${DERPER_BIN}"
DOMAIN="${DOMAIN}"
PORT="${PORT}"
CERTS_DIR="${CERTS_DIR}"
PID_FILE="${PID_FILE}"
LOG_FILE="${LOG_FILE}"
LOG_DIR="\$(dirname "\$LOG_FILE")"

START_CMD="\$DERPER_BIN -hostname \$DOMAIN -certmode manual -certdir \$CERTS_DIR -a :\$PORT -http-port -1 -stun=false -verify-clients=false"

mkdir -p "\$APP_DIR" "\$CERTS_DIR" "\$LOG_DIR"
cd "\$APP_DIR" || exit 1

case "\$1" in
    start)
        if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
            echo "derper 已经在运行中 (PID: \$(cat "\$PID_FILE"))"
        else
            echo "正在启动 derper 服务..."
            nohup \$START_CMD > "\$LOG_FILE" 2>&1 &
            echo \$! > "\$PID_FILE"
            sleep 1
            if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
                echo "✅ derper 已成功启动 (PID: \$(cat "\$PID_FILE"))"
            else
                echo "❌ 启动失败，请检查日志：\$LOG_FILE"
            fi
        fi
        ;;
    stop)
        if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
            PID=\$(cat "\$PID_FILE")
            echo "正在停止 derper (PID: \$PID)..."
            kill "\$PID" 2>/dev/null
            sleep 1
            if kill -0 "\$PID" 2>/dev/null; then
                kill -9 "\$PID" 2>/dev/null
            fi
            rm -f "\$PID_FILE"
            echo "✅ derper 已停止"
        else
            pkill -9 -f "derper -hostname" 2>/dev/null || true
            echo "derper 未运行"
            rm -f "\$PID_FILE"
        fi
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    status)
        if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
            echo "🟢 derper 正在运行 (PID: \$(cat "\$PID_FILE"))"
        else
            echo "🔴 derper 已停止"
        fi
        ;;
    logs)
        if [ -f "\$LOG_FILE" ]; then
            tail -n 50 -f "\$LOG_FILE"
        else
            echo "暂无日志文件: \$LOG_FILE"
        fi
        ;;
    *)
        echo "使用方法: service derper {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
exit 0
EOF

chmod +x /etc/init.d/derper

# 5. 启动服务并检查状态
service derper restart
service derper status

echo ""
echo "=================================================="
echo "🎉 derper 服务已注册完成并成功启动！"
echo "👉 管理命令: service derper {start|stop|restart|status|logs}"
echo "🌐 访问测试: https://${DOMAIN}:${PORT}"
echo "📄 实时日志: service derper logs (或 tail -f ${LOG_FILE})"
echo "=================================================="

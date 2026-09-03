#!/usr/bin/env bash
#
# 自动安装与卸载 Node.js LTS + npm + AI 开发者命令行工具 (@openai/codex, @google/gemini-cli)
# 用法:
#   sudo ./nodejs_install.sh [版本号]              # 安装指定版本或 LTS (例如: 20 / 22 / lts)
#   ./nodejs_install.sh list                     # 列出主流 Node.js LTS 与 Current 版本
#   sudo ./nodejs_install.sh uninstall           # 卸载 Node.js 及全局 npm 环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -d "$SCRIPT_DIR/../scripts" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
fi
LOG_DIR="$PROJECT_ROOT/logs"

if [ -d "$LOG_DIR" ]; then
    [ ! -w "$LOG_DIR" ] && { sudo chmod 777 "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"; }
else
    mkdir -p "$LOG_DIR" 2>/dev/null && chmod 777 "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
fi
logfile="${LOG_DIR}/$(basename "${BASH_SOURCE[0]}" .sh).log"

function log {
    local msg
    local logtype
    logtype=$1
    msg=$2
    datetime=$(date +'%F %H:%M:%S')
    logformat="${datetime} ${FUNCNAME[@]/log/} [line:${BASH_LINENO[0]}] ${logtype}:${msg}"
    {
        case $logtype in
            debug)
                echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true
                ;;
            info)
                echo -e "\033[32m $datetime [info] ${msg} \t \033[0m"
                echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true
                ;;
            warn)
                echo -e "\033[33m $datetime [WARN] ${msg} \t \033[0m"
                echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true
                ;;
            error)
                echo -e "\033[31m $datetime [ERROR] ${msg} \033[0m"
                echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true
                exit 1
                ;;
        esac
    }
}

# 列出官方可用版本
function list_versions {
    log info "正在查询 Node.js 官方发布版本列表..."
    local raw_json
    raw_json=$(curl -fsSL --connect-timeout 6 "https://nodejs.org/dist/index.json" 2>/dev/null || curl -fsSL --connect-timeout 6 "https://npmmirror.com/mirrors/node/index.json" 2>/dev/null || true)

    if [ -n "$raw_json" ] && command -v python3 >/dev/null 2>&1; then
        echo "$raw_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print("\033[0;34m========================================================\033[0m")
    print("\033[0;34m               Node.js 官方可用版本列表                 \033[0m")
    print("\033[0;34m========================================================\033[0m")
    lts_seen = set()
    print("  \033[1;36m[长期支持版 LTS Releases]\033[0m")
    for item in data:
        lts = item.get("lts")
        ver = item.get("version", "")
        if lts and lts not in lts_seen:
            lts_seen.add(lts)
            major = ver.split(".")[0].replace("v", "")
            print(f"    \033[1;32m* Node.js {major:<4}\033[0m (当前具体版本: {ver:<9} 代号: {lts})")
    print("\n  \033[1;36m[最新版本 Current Releases]\033[0m")
    for item in data[:3]:
        ver = item.get("version", "")
        print(f"    - {ver}")
    print("\033[0;34m========================================================\033[0m")
    print("提示: 执行安装: sudo ./scripts/nodejs_install.sh [20|22|lts]")
except Exception:
    sys.exit(1)
' && exit 0
    fi

    # 降级展示
    echo "========================================================"
    echo "               Node.js 推荐版本列表"
    echo "========================================================"
    echo "  * Node.js 22.x (Active LTS - Recommended)"
    echo "  * Node.js 20.x (Maintenance LTS)"
    echo "  * Node.js 18.x (Maintenance LTS)"
    echo "========================================================"
    echo "提示: 执行安装: sudo ./scripts/nodejs_install.sh 22"
    exit 0
}

function check_permission {
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            log error "当前用户没有 sudo 权限，请用 root 或 sudo 执行本脚本"
        else
            log info "检测到非 root 但具有 sudo 权限，继续执行..."
        fi
    else
        log info "检测到 root 用户执行"
    fi
}

function get_user_info {
    if [ -n "$SUDO_USER" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(eval echo "~$SUDO_USER")
    else
        ORIGINAL_USER="$USER"
        ORIGINAL_HOME="$HOME"
    fi
}

function detect_os {
    if [ "$(uname)" = "Darwin" ]; then
        OS_FAMILY="macos"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|linuxmint|pop)
                OS_FAMILY="debian"
                ;;
            centos|rhel|rocky|almalinux|fedora)
                OS_FAMILY="rhel"
                ;;
            *)
                OS_FAMILY="unknown"
                ;;
        esac
    else
        OS_FAMILY="unknown"
    fi
}

function uninstall_node {
    check_permission
    detect_os
    log info "开始卸载 Node.js 与 npm..."
    case "$OS_FAMILY" in
        debian)
            apt-get remove --purge -y nodejs npm 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            rm -f /etc/apt/sources.list.d/nodesource.list
            rm -f /etc/apt/keyrings/nodesource.gpg
            ;;
        rhel)
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y nodejs npm 2>/dev/null || true
            else
                yum remove -y nodejs npm 2>/dev/null || true
            fi
            rm -f /etc/yum.repos.d/nodesource*.repo
            ;;
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew uninstall node 2>/dev/null || true
            fi
            ;;
    esac
    # 清理全局 AI CLI 工具软链接与缓存
    rm -f /usr/local/bin/codex /usr/bin/codex /usr/local/bin/gemini /usr/bin/gemini 2>/dev/null || true
    rm -rf "$ORIGINAL_HOME/.npm" 2>/dev/null || true
    log info "Node.js 及相关 AI CLI 工具卸载完成！"
    exit 0
}

# 命令分发
ACTION="${1:-}"
case "$ACTION" in
    list|list-versions|-l|--list)
        list_versions
        ;;
    uninstall|-u|--uninstall|remove)
        uninstall_node
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0 [20|22|lts]           # 安装指定版本或最新 LTS Node.js"
        echo "  $0 list                       # 列出官方可用版本"
        echo "  sudo $0 uninstall             # 卸载 Node.js 及 npm"
        exit 0
        ;;
esac

check_permission
get_user_info
detect_os

NODE_VER_ARG="${1:-lts}"
case "$NODE_VER_ARG" in
    18|v18|18.x) SETUP_VER="18.x" ;;
    20|v20|20.x) SETUP_VER="20.x" ;;
    22|v22|22.x) SETUP_VER="22.x" ;;
    lts|current|*) SETUP_VER="lts.x" ;;
esac

log info "检测到操作系统类型: $OS_FAMILY"
log info "准备安装 Node.js 版本: $SETUP_VER"

install_debian() {
    log info "正在更新 apt 索引并安装基础依赖..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg

    log info "配置 NodeSource 官方仓库 ($SETUP_VER)..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$SETUP_VER nodistro main" > /etc/apt/sources.list.d/nodesource.list

    apt-get update -y
    apt-get install -y nodejs
}

install_rhel() {
    log info "正在为 RHEL/CentOS 配置 NodeSource 仓库 ($SETUP_VER)..."
    curl -fsSL "https://rpm.nodesource.com/setup_$SETUP_VER" | bash -
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y nodejs
    else
        yum install -y nodejs
    fi
}

install_macos() {
    log info "macOS 检测到，使用 Homebrew 安装 Node.js..."
    if ! command -v brew >/dev/null 2>&1; then
        log error "未检测到 Homebrew，请先安装 brew"
    fi
    brew install node
}

case "$OS_FAMILY" in
    debian)
        install_debian
        ;;
    rhel)
        install_rhel
        ;;
    macos)
        install_macos
        ;;
    *)
        log error "不支持的操作系统架构"
        ;;
esac

log info "验证 Node.js 与 npm 安装..."
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    log info "Node.js 安装成功: $(node -v)"
    log info "npm 安装成功: $(npm -v)"
else
    log error "Node.js 或 npm 未正常安装"
fi

# 安装常用 AI CLI 工具 (@openai/codex 与 @google/gemini-cli)
function install_ai_cli_tools {
    if ! command -v npm >/dev/null 2>&1; then
        log warn "未检测到 npm，跳过 AI CLI 工具安装。"
        return 0
    fi

    log info "开始安装 AI 开发者命令行工具 (@openai/codex, @google/gemini-cli)..."

    # 1. 安装 @openai/codex
    log info "正在安装 @openai/codex CLI..."
    if npm install -g @openai/codex@latest >> "$logfile" 2>&1 || npm install -g @openai/codex >> "$logfile" 2>&1; then
        log info "✅ @openai/codex CLI 安装完成"
    else
        log warn "⚠️ @openai/codex 安装失败 (可稍后手动重试: sudo npm install -g @openai/codex)"
    fi

    # 2. 安装 @google/gemini-cli
    log info "正在安装 @google/gemini-cli..."
    if npm install -g @google/gemini-cli@latest >> "$logfile" 2>&1 || npm install -g @google/gemini-cli >> "$logfile" 2>&1; then
        log info "✅ @google/gemini-cli 安装完成"
    else
        log warn "⚠️ @google/gemini-cli 安装失败 (可稍后手动重试: sudo npm install -g @google/gemini-cli)"
    fi
}

install_ai_cli_tools

log info "全部安装完成！ 🎉"


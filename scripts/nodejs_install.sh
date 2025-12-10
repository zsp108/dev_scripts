#!/bin/bash
#
# 自动安装 Node.js LTS + npm + @openai/codex
# Ubuntu/Debian 使用 setup_lts.x
# macOS 使用 brew install node
# RHEL/CentOS 使用 setup_lts.x RPM 版
#

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile="$SCRIPT_ROOT/init.log"

# -----------------------------
# 日志函数（与 go_install.sh 保持一致）
# -----------------------------
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
                echo "${logformat}" &>> "$logfile"
                ;;
            info)
                echo -e "\033[32m $datetime [info] ${msg} \t \033[0m"
                echo "${logformat}" &>> "$logfile"
                ;;
            warn)
                echo -e "\033[33m $datetime [WARN] ${msg} \t \033[0m"
                echo "${logformat}" &>> "$logfile"
                ;;
            error)
                echo -e "\033[31m $datetime [ERROR] ${msg} \033[0m"
                echo "${logformat}" &>> "$logfile"
                exit 1
                ;;
        esac
    }
}

# -----------------------------
# 权限检查（与 go_install.sh 同逻辑）
# -----------------------------
if [ "$EUID" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
        log error "当前用户没有sudo权限，请用 root 或 sudo 执行本脚本"
    else
        log info "检测到非 root 但具有 sudo 权限，继续执行..."
    fi
else
    log info "检测到 root 用户执行"
fi

if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo "~$SUDO_USER")
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
fi

log info "原始用户: $ORIGINAL_USER, HOME: $ORIGINAL_HOME"

# -----------------------------
# 检测系统
# -----------------------------
OS="unknown"
if [ "$(uname)" = "Darwin" ]; then
    OS="macos"
elif [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS=$ID
fi

log info "检测到系统: $OS"

# -----------------------------
# 工具函数
# -----------------------------
ensure_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        log warn "curl 未安装，正在安装..."

        case "$OS" in
            ubuntu|debian)
                sudo apt-get update
                sudo apt-get install -y curl
                ;;
            centos|rhel|rocky|almalinux)
                sudo yum install -y curl || sudo dnf install -y curl
                ;;
            *)
                log error "未知系统，无法自动安装 curl"
                ;;
        esac
    fi
}

# -----------------------------
# macOS 安装 node
# -----------------------------
install_node_macos() {
    log info "macOS 检测，使用 Homebrew 安装 node"

    sudo xcode-select --install || true

    if ! command -v brew >/dev/null 2>&1; then
        log info "brew 未安装，开始安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        log info "brew 已安装"
    fi

    brew install node || log error "brew install node 失败"

    log info "macOS Node.js 安装完成: $(node -v)"
}

# -----------------------------
# Ubuntu / Debian 安装 node
# -----------------------------
install_node_debian() {
    ensure_curl

    log info "使用 NodeSource LTS 安装 Node.js"

    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash - \
        || log error "运行 NodeSource 脚本失败"

    sudo apt-get install -y nodejs || log error "apt-get install nodejs 失败"

    log info "Node.js 安装完成: $(node -v)"
}

# -----------------------------
# RHEL / CentOS / Rocky / Alma
# -----------------------------
install_node_rhel() {
    ensure_curl

    log info "使用 NodeSource LTS 安装 Node.js (RPM 系)"

    curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - \
        || log error "运行 NodeSource RPM 脚本失败"

    if command -v yum >/dev/null 2>&1; then
        sudo yum install -y nodejs
    else
        sudo dnf install -y nodejs
    fi

    log info "Node.js 安装完成: $(node -v)"
}

# -----------------------------
# 安装 codex CLI
# -----------------------------
install_codex_cli() {
    if ! command -v npm >/dev/null 2>&1; then
        log error "npm 未找到，无法安装 @openai/codex"
    fi

    log info "开始安装 @openai/codex@latest"

    sudo npm install -g @openai/codex@latest || log error "安装 codex 失败"

    log info "codex CLI 安装完成"
}

# -----------------------------
# 主流程
# -----------------------------
log info "开始安装 Node.js LTS + @openai/codex"

case "$OS" in
    macos)
        install_node_macos
        ;;
    ubuntu|debian)
        install_node_debian
        ;;
    centos|rhel|rocky|almalinux|ol)
        install_node_rhel
        ;;
    *)
        log error "不支持的系统：$OS"
        ;;
esac

#install_codex_cli

log info "全部安装完成！ 🎉"


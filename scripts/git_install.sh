#!/usr/bin/env bash
#
# 自动下载并编译安装 Git
# 用法:
#   sudo ./git_install.sh [版本号]              # 安装指定版本 Git (默认: 2.42.0)
#   ./git_install.sh list                     # 列出官方可用版本
#   sudo ./git_install.sh uninstall           # 卸载编译安装的 Git

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
if [ -d "$SCRIPT_DIR/../scripts" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
fi
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
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
            echo "${logformat}" >> "$logfile" 2>&1;;
        info)
            echo -e "\033[32m $datetime [info] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1;;
        warn)
            echo -e "\033[33m $datetime [WARN] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1;;
        error)
            echo -e "\033[31m $datetime [ERROR] ${msg} \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1
            exit 1;;
    esac
    }
}

function list_versions {
    echo -e "\033[0;34m========================================================\033[0m"
    echo -e "\033[0;34m               Git 官方稳定发布版本列表                 \033[0m"
    echo -e "\033[0;34m========================================================\033[0m"
    echo -e "    \033[1;32m* 2.42.0\033[0m (默认稳定推荐版)"
    echo -e "    * 2.45.2"
    echo -e "    * 2.48.1"
    echo -e "    * 2.51.0"
    echo -e "\033[0;34m========================================================\033[0m"
    echo "提示: 执行安装: sudo ./scripts/git_install.sh <版本号>"
    exit 0
}

function check_permission {
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            log error "当前用户没有 sudo 权限，请以 root 用户或使用 sudo 执行此脚本"
        else
            log info "检测到非 root 用户但有 sudo 权限，继续执行..."
        fi
    else
        log info "检测到 root 用户执行，继续执行..."
    fi
}

function get_user_info {
    if [ -n "$SUDO_USER" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(eval echo ~"$SUDO_USER")
    else
        ORIGINAL_USER="$USER"
        ORIGINAL_HOME="$HOME"
    fi
}

function do_uninstall {
    check_permission
    get_user_info
    log info "开始卸载编译安装的 Git..."

    if [ -d "/usr/local/git" ]; then
        rm -rf /usr/local/git
        log info "已删除 /usr/local/git"
    fi

    if [ -L "/usr/bin/git" ] && [ "$(readlink /usr/bin/git)" = "/usr/local/git/bin/git" ]; then
        rm -f /usr/bin/git
    fi

    cleanup_bashrc() {
        local user_home="$1"
        local user_bashrc="$user_home/.bashrc"
        if [ -f "$user_bashrc" ] && grep -q "/usr/local/git/bin" "$user_bashrc"; then
            sed -i.bak '/# Git envs/,/export PATH=\/usr\/local\/git/d' "$user_bashrc" 2>/dev/null || true
            sed -i.bak '/\/usr\/local\/git\/bin/d' "$user_bashrc" 2>/dev/null || true
            rm -f "$user_bashrc.bak"
            log info "已清理 $user_bashrc 中的 Git 环境变量"
        fi
    }

    cleanup_bashrc "$HOME"
    [ "$ORIGINAL_HOME" != "$HOME" ] && cleanup_bashrc "$ORIGINAL_HOME"
    log info "Git 卸载完成！"
    exit 0
}

ACTION="${1:-}"
case "$ACTION" in
    list|list-versions|-l|--list)
        list_versions
        ;;
    uninstall|-u|--uninstall|remove)
        do_uninstall
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0 [版本号]              # 编译安装指定版本 Git (默认: 2.42.0)"
        echo "  $0 list                       # 列出官方可用版本"
        echo "  sudo $0 uninstall             # 卸载编译安装的 Git"
        exit 0
        ;;
esac

check_permission
get_user_info

GIT_VERSION="${1:-2.42.0}"
log info "准备编译安装 Git 版本: $GIT_VERSION"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log error "无法确定操作系统类型。"
fi

install_dependencies() {
    log info "安装 Git 编译依赖..."
    case "$OS" in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y build-essential libssl-dev libcurl4-gnutls-dev libexpat1-dev gettext unzip wget
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y gcc make openssl-devel libcurl-devel expat-devel gettext-devel unzip wget
            else
                yum install -y gcc make openssl-devel libcurl-devel expat-devel gettext-devel unzip wget
            fi
            ;;
        *)
            log warn "未知操作系统，尝试继续编译"
            ;;
    esac
}

install_dependencies

cd /tmp
tar_file="v${GIT_VERSION}.tar.gz"
download_url="https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz"

log info "下载 Git 源码: $download_url"
wget --timeout=30 --tries=3 "$download_url" -O "/tmp/$tar_file" || wget --timeout=30 --tries=3 "https://github.com/git/git/archive/refs/tags/v${GIT_VERSION}.tar.gz" -O "/tmp/$tar_file"

rm -rf "/tmp/git-${GIT_VERSION}"
tar -xzf "/tmp/$tar_file" -C /tmp
cd "/tmp/git-${GIT_VERSION}" || cd "/tmp/git-v${GIT_VERSION}"

make prefix=/usr/local/git all -j$(nproc 2>/dev/null || echo 2)
make prefix=/usr/local/git install

if [ -f "/usr/local/git/bin/git" ]; then
    ln -sf /usr/local/git/bin/git /usr/bin/git || true
    log info "Git 编译安装成功: $(/usr/local/git/bin/git --version)"
else
    log error "Git 安装失败"
fi

#!/bin/bash
#
# 卸载 Docker 及相关组件
# 用法：sudo ./docker_uninstall.sh [--purge-data] [--yes]

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile=$SCRIPT_ROOT/init.log

show_help() {
    cat <<'EOT'
用法:
  sudo ./docker_uninstall.sh [--purge-data] [--yes]

参数:
  --purge-data   清理 Docker 数据目录（危险操作）
  --yes, -y      跳过确认，直接执行（建议仅在自动化场景使用）
  -h, --help     显示帮助

说明:
  默认仅卸载 Docker 软件包并停止/禁用服务，不删除数据目录。
EOT
}

PURGE_DATA="false"
ASSUME_YES="false"

for arg in "$@"; do
    case "$arg" in
        --purge-data)
            PURGE_DATA="true"
            ;;
        --yes|-y)
            ASSUME_YES="true"
            ;;
        -h|--help|help)
            show_help
            exit 0
            ;;
        *)
            echo "未知参数: $arg"
            show_help
            exit 1
            ;;
    esac
done

# 日志函数
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
            echo "${logformat}" >> "$logfile" 2>&1 ;;
        info)
            echo -e "\033[32m ${datetime} [info] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1 ;;
        warn)
            echo -e "\033[33m ${datetime} [WARN] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1 ;;
        error)
            echo -e "\033[31m ${datetime} [ERROR] ${msg} \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1
            exit 1 ;;
    esac
    }
}

# 检查用户权限
if [ "$EUID" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
        log error "当前用户没有sudo权限，请以root用户或使用sudo命令执行此脚本"
    else
        log info "检测到非root用户但有sudo权限，继续执行..."
    fi
else
    log info "检测到root用户执行，继续执行..."
fi

log info "清理数据目录: $PURGE_DATA"
log info "跳过确认: $ASSUME_YES"

# 获取系统信息
UNAME_S=$(uname -s)
if [ "$UNAME_S" = "Darwin" ]; then
    OS="darwin"
    VERSION=$(sw_vers -productVersion 2>/dev/null || uname -r)
    OS_NAME="macOS $VERSION"
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_NAME=$PRETTY_NAME
else
    OS="unknown"
    OS_NAME="unknown"
fi

log info "检测到操作系统: $OS_NAME ($OS)"

# 停止并禁用服务
if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | grep -q '^docker.service'; then
        log info "停止 Docker 服务"
        systemctl stop docker || log warn "停止 Docker 服务失败，继续执行"
        systemctl disable docker || log warn "禁用 Docker 服务失败，继续执行"
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^containerd.service'; then
        log info "停止 containerd 服务"
        systemctl stop containerd || log warn "停止 containerd 服务失败，继续执行"
        systemctl disable containerd || log warn "禁用 containerd 服务失败，继续执行"
    fi
fi

uninstall_darwin() {
    log info "开始卸载 macOS 上的 Docker..."
    if command -v brew >/dev/null 2>&1; then
        brew uninstall --cask docker || true
    fi
    rm -rf "/Applications/Docker.app" 2>/dev/null || true
    rm -rf "$HOME/Library/Containers/com.docker.docker" 2>/dev/null || true
    rm -rf "$HOME/Library/Application Support/Docker Desktop" 2>/dev/null || true
    rm -rf "$HOME/.docker" 2>/dev/null || true
    log info "macOS Docker 卸载完成"
}

uninstall_debian() {
    log info "开始卸载 Docker (Debian/Ubuntu系列)"
    apt-get remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker.io docker docker-engine runc || true
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker.io docker docker-engine runc || true
    apt-get autoremove -y || true
    rm -f /etc/apt/sources.list.d/docker.list || true
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg || true
}

uninstall_rhel() {
    log info "开始卸载 Docker (RHEL/CentOS/Fedora系列)"
    if command -v dnf >/dev/null 2>&1; then
        dnf remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker docker-client docker-common docker-engine || true
    else
        yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker docker-client docker-common docker-engine || true
    fi
    rm -f /etc/yum.repos.d/docker-ce.repo || true
}

case "$OS" in
    darwin)
        uninstall_darwin
        exit 0
        ;;
    ubuntu|debian|linuxmint|pop)
        uninstall_debian
        ;;
    centos|rhel|rocky|almalinux|fedora)
        uninstall_rhel
        ;;
    *)
        log warn "未适配的系统: $OS，尝试通用卸载命令"
        if command -v apt-get >/dev/null 2>&1; then
            uninstall_debian
        elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
            uninstall_rhel
        else
            log warn "无法识别包管理器，请手动卸载 Docker"
        fi
        ;;
esac

# 读取 daemon.json 中的 data-root
DOCKER_DATA_ROOT=""
if [ -f /etc/docker/daemon.json ]; then
    DOCKER_DATA_ROOT=$(sed -n 's/.*"data-root"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /etc/docker/daemon.json | head -n1)
fi

if [ "$PURGE_DATA" = "true" ]; then
    if [ "$ASSUME_YES" != "true" ]; then
        echo "即将永久删除 Docker 数据目录，包含镜像、容器、卷、构建缓存。"
        read -p "确认继续吗？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log info "用户取消数据清理"
            log info "Docker 卸载完成（保留数据目录）"
            exit 0
        fi
    fi

    log warn "将清理 Docker 数据目录"

    if [ -n "$DOCKER_DATA_ROOT" ] && [ -d "$DOCKER_DATA_ROOT" ]; then
        log info "清理 data-root: $DOCKER_DATA_ROOT"
        rm -rf "$DOCKER_DATA_ROOT"
    fi

    for p in /var/lib/docker /var/lib/containerd /docker; do
        if [ -d "$p" ]; then
            log info "清理目录: $p"
            rm -rf "$p"
        fi
    done

    rm -rf /etc/docker || true
else
    log info "未启用数据清理，保留数据目录与 /etc/docker 配置"
fi

# 清理可执行文件（可能由手工安装留下）
rm -f /usr/local/bin/docker-compose || true

log info "Docker 卸载完成"
if [ "$PURGE_DATA" = "true" ]; then
    log warn "Docker 数据已清理，无法恢复"
fi

#!/usr/bin/env bash
#
# 自动安装与卸载 Docker 及相关组件
# 安装用法：sudo ./docker_install.sh [version] [channel] [data-root]
# 卸载用法：sudo ./docker_install.sh uninstall [--purge-data] [--yes]
# 示例：
#   sudo ./docker_install.sh
#   sudo ./docker_install.sh 24.0.5 stable /var/lib/docker
#   sudo ./docker_install.sh uninstall
#   sudo ./docker_install.sh uninstall --purge-data

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

# 默认配置
DOCKER_VERSION=""
DOCKER_CHANNEL="stable"
DOCKER_INSTALL_PATH="/var/lib/docker"

# 日志函数，记录操作系统，并且将输出打印到屏幕
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

# 获取原始用户信息
function get_original_user {
    if [ -n "$SUDO_USER" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(eval echo ~"$SUDO_USER")
        log info "检测到 sudo 执行，原始用户: $ORIGINAL_USER, 原始家目录: $ORIGINAL_HOME"
    else
        ORIGINAL_USER="$USER"
        ORIGINAL_HOME="$HOME"
        log info "直接执行，当前用户: $ORIGINAL_USER, 当前家目录: $ORIGINAL_HOME"
    fi
}

# 获取操作系统信息
function detect_os {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        OS_NAME=$PRETTY_NAME
    else
        log error "无法确定操作系统类型。"
    fi
}

# ------------------------------------------------------------------------------
# 卸载模块
# ------------------------------------------------------------------------------
function do_uninstall {
    check_permission
    detect_os
    log info "开始执行 Docker 卸载流程..."

    local purge_data="false"
    local assume_yes="false"

    for arg in "$@"; do
        case "$arg" in
            --purge-data)
                purge_data="true"
                ;;
            --yes|-y)
                assume_yes="true"
                ;;
        esac
    done

    log info "清理数据目录: $purge_data"

    # 停止并禁用服务
    if systemctl list-unit-files 2>/dev/null | grep -q "^docker.service"; then
        log info "正在停止 Docker 服务..."
        systemctl stop docker 2>/dev/null || true
        systemctl disable docker 2>/dev/null || true
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q "^containerd.service"; then
        log info "正在停止 containerd 服务..."
        systemctl stop containerd 2>/dev/null || true
        systemctl disable containerd 2>/dev/null || true
    fi

    # 卸载软件包
    case "$OS" in
        ubuntu|debian|linuxmint|pop)
            log info "正在卸载 Docker 软件包 (Debian/Ubuntu 系列)..."
            apt-get remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker.io docker docker-engine runc 2>/dev/null || true
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker.io docker docker-engine runc 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
            rm -f /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true
            ;;
        centos|rhel|rocky|almalinux|fedora)
            log info "正在卸载 Docker 软件包 (RHEL/CentOS 系列)..."
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker docker-client docker-common docker-engine 2>/dev/null || true
            else
                yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker docker-client docker-common docker-engine 2>/dev/null || true
            fi
            rm -f /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
            ;;
        *)
            log warn "尝试通用包管理器卸载 Docker..."
            if command -v apt-get >/dev/null 2>&1; then
                apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker.io docker 2>/dev/null || true
            elif command -v yum >/dev/null 2>&1; then
                yum remove -y docker-ce docker-ce-cli containerd.io docker 2>/dev/null || true
            fi
            ;;
    esac

    # 读取并清理数据目录
    local docker_data_root=""
    if [ -f /etc/docker/daemon.json ]; then
        docker_data_root=$(sed -n "s/.*\"data-root\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" /etc/docker/daemon.json | head -n1)
    fi

    if [ "$purge_data" = "true" ]; then
        if [ "$assume_yes" != "true" ] && [ -t 0 ]; then
            echo "即将永久删除 Docker 数据目录（包含所有镜像、容器、存储卷与构建缓存）。"
            read -r -p "确认继续吗？(y/N): " confirm_purge
            if [[ ! "$confirm_purge" =~ ^[Yy]$ ]]; then
                log info "用户取消数据清理，已保留数据目录。"
                log info "Docker 软件卸载完成！"
                exit 0
            fi
        fi

        log warn "正在清理 Docker 数据目录..."
        if [ -n "$docker_data_root" ] && [ -d "$docker_data_root" ]; then
            rm -rf "$docker_data_root"
            log info "已删除: $docker_data_root"
        fi

        for p in /var/lib/docker /var/lib/containerd /docker; do
            if [ -d "$p" ]; then
                rm -rf "$p"
                log info "已删除: $p"
            fi
        done
        rm -rf /etc/docker
    else
        log info "未启用数据清理，保留数据目录及 /etc/docker 配置文件。"
    fi

    rm -f /usr/local/bin/docker-compose 2>/dev/null || true
    log info "Docker 卸载完成！"
    exit 0
}

# ------------------------------------------------------------------------------
# 命令分发与参数解析
# ------------------------------------------------------------------------------
ACTION="${1:-}"
case "$ACTION" in
    uninstall|-u|--uninstall|remove)
        shift || true
        do_uninstall "$@"
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0 [版本] [通道] [数据目录]              # 安装 Docker (默认: latest stable /var/lib/docker)"
        echo "  sudo $0 uninstall [--purge-data] [--yes]     # 卸载 Docker (--purge-data 清理所有容器与镜像数据)"
        exit 0
        ;;
esac

# ------------------------------------------------------------------------------
# 安装流程
# ------------------------------------------------------------------------------
check_permission

# 参数处理
if [ -n "$1" ]; then
    DOCKER_VERSION="$1"
fi

if [ -n "$2" ]; then
    DOCKER_CHANNEL="$2"
fi

if [ -n "$3" ]; then
    DOCKER_INSTALL_PATH="$3"
fi

if [ -z "$DOCKER_VERSION" ]; then
    DOCKER_VERSION="latest"
fi

log info "Docker版本: $DOCKER_VERSION"
log info "Docker通道: $DOCKER_CHANNEL"
log info "Docker安装路径(data-root): $DOCKER_INSTALL_PATH"

get_original_user

# 系统架构检测和标准化
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) DOCKER_ARCH="amd64" ;;
    aarch64|arm64) DOCKER_ARCH="arm64" ;;
    i386|i686) DOCKER_ARCH="i386" ;;
    armv7l) DOCKER_ARCH="armhf" ;;
    *) log error "不支持的架构: $ARCH" ;;
esac

detect_os

# 打印系统信息
log info "检测到系统架构: $ARCH (Docker架构: $DOCKER_ARCH)"
log info "检测到操作系统: $OS_NAME ($OS $VERSION)"

# 检查 Docker 是否已安装
if command -v docker &> /dev/null; then
    DOCKER_CURRENT_VERSION=$(docker --version | cut -d' ' -f3 | sed 's/,//')
    log warn "Docker已安装，当前版本: $DOCKER_CURRENT_VERSION"

    if [ "$DOCKER_VERSION" != "latest" ] && [ "$DOCKER_CURRENT_VERSION" = "$DOCKER_VERSION" ]; then
        log info "指定版本已安装，无需重新安装"
        exit 0
    fi

    if [ -t 0 ]; then
        read -p "是否要卸载当前版本并重新安装？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log info "用户取消安装"
            exit 0
        fi
    fi
fi

# Docker 安装函数
install_docker_debian() {
    log info "开始安装 Docker (Debian/Ubuntu 系列)"

    apt-get update || log error "无法更新包索引"
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release || log error "无法安装依赖包"

    local docker_gpg_tmp="/tmp/docker.gpg"
    rm -f "$docker_gpg_tmp"
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 10 https://download.docker.com/linux/$OS/gpg -o "$docker_gpg_tmp" || log error "无法下载 Docker GPG 密钥"
    gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg "$docker_gpg_tmp" || log error "无法添加 Docker GPG 密钥"
    rm -f "$docker_gpg_tmp"

    echo "deb [arch=$DOCKER_ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $VERSION_CODENAME $DOCKER_CHANNEL" > /etc/apt/sources.list.d/docker.list || log error "无法添加 Docker 仓库"
    apt-get update || log error "无法更新包索引（添加仓库后）"

    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    if [ "$DOCKER_VERSION" = "latest" ]; then
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || log error "无法安装 Docker"
    else
        apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-compose-plugin || log error "无法安装指定版本的Docker"
    fi
}

install_docker_rhel() {
    log info "开始安装 Docker (RHEL/CentOS 系列)"

    yum install -y yum-utils || log error "无法安装 yum-utils"
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || log error "无法添加 Docker 仓库"
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    if [ "$DOCKER_VERSION" = "latest" ]; then
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || log error "无法安装 Docker"
    else
        yum install -y docker-ce-$DOCKER_VERSION docker-ce-cli-$DOCKER_VERSION containerd.io docker-compose-plugin || log error "无法安装指定版本的 Docker"
    fi
}

install_docker_fedora() {
    log info "开始安装 Docker (Fedora 系列)"

    dnf install -y dnf-plugins-core || log error "无法安装 dnf-plugins-core"
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || log error "无法添加 Docker 仓库"
    dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    if [ "$DOCKER_VERSION" = "latest" ]; then
        dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || log error "无法安装 Docker"
    else
        dnf install -y docker-ce-$DOCKER_VERSION docker-ce-cli-$DOCKER_VERSION containerd.io docker-compose-plugin || log error "无法安装指定版本的 Docker"
    fi
}

# 配置 Docker 数据目录
configure_docker_path() {
    log info "配置 Docker 安装路径(data-root): $DOCKER_INSTALL_PATH"

    mkdir -p /etc/docker || log error "无法创建 /etc/docker 目录"
    mkdir -p "$DOCKER_INSTALL_PATH" || log error "无法创建 Docker 安装路径: $DOCKER_INSTALL_PATH"

    cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "$DOCKER_INSTALL_PATH"
}
EOF
}

# 根据操作系统选择安装方法
case "$OS" in
    ubuntu|debian|linuxmint|pop)
        install_docker_debian
        ;;
    centos|rhel|rocky|almalinux)
        install_docker_rhel
        ;;
    fedora)
        install_docker_fedora
        ;;
    *)
        log error "不支持的操作系统: $OS"
        ;;
esac

configure_docker_path

# 启动并启用 Docker 服务
log info "启动 Docker 服务..."
systemctl enable docker || log warn "无法启用 Docker 服务"
systemctl start docker || log error "无法启动 Docker 服务"

# 将当前用户添加到 docker 组
if [ "$ORIGINAL_USER" != "root" ]; then
    log info "将用户 $ORIGINAL_USER 添加到 docker 组"
    usermod -aG docker "$ORIGINAL_USER" || log warn "无法将用户添加到 docker 组"
    log warn "请重新登录或执行 'newgrp docker' 以使组权限生效"
fi

# 验证安装
log info "验证 Docker 安装..."
systemctl is-active --quiet docker && log info "Docker 服务正在运行" || log error "Docker 服务未运行"
docker --version && log info "Docker 命令行工具可用" || log error "Docker 命令行工具不可用"

log info "Docker 安装完成！"
log info "使用 'docker --version' 查看版本"
log info "使用 'docker run hello-world' 测试安装"

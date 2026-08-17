#!/bin/bash
#
# 自动下载并安装 Docker
# 用法：sudo ./docker_install.sh [docker-version] [channel] [docker-install-path]
# 示例：
#   sudo ./docker_install.sh 24.0.6 stable /data/docker
#   sudo ./docker_install.sh latest stable /var/lib/docker

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"

logfile=$SCRIPT_ROOT/init.log

show_help() {
    cat <<'EOF'
用法:
  sudo ./docker_install.sh [docker-version] [channel] [docker-install-path]

参数:
  docker-version       Docker 版本，默认 latest
  channel              Docker 通道，默认 stable（如 stable/test/nightly）
  docker-install-path  Docker 数据目录(data-root)，默认 /var/lib/docker

示例:
  sudo ./docker_install.sh
  sudo ./docker_install.sh latest
  sudo ./docker_install.sh 24.0.6 stable
  sudo ./docker_install.sh 24.0.6 stable /data/docker

帮助:
  sudo ./docker_install.sh -h
  sudo ./docker_install.sh --help
EOF
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
    show_help
    exit 0
fi

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

# 检查用户权限
if [ "$EUID" -ne 0 ]; then
    # 非root用户，检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        log error "当前用户没有sudo权限，请以root用户或使用sudo命令执行此脚本"
    else
        log info "检测到非root用户但有sudo权限，继续执行..."
    fi
else
    log info "检测到root用户执行，继续执行..."
fi

# 解析命令行参数
DOCKER_VERSION=""
DOCKER_CHANNEL="stable"
DOCKER_INSTALL_PATH="/var/lib/docker"

if [ -n "$1" ]; then
    if [ "$1" = "latest" ]; then
        DOCKER_VERSION="latest"
        DOCKER_CHANNEL="stable"
    else
        DOCKER_VERSION="$1"
    fi
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

# 获取原始用户信息（当使用sudo执行时）
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo "~$SUDO_USER")
    ORIGINAL_GROUP=$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")
    log info "检测到sudo执行，原始用户: $ORIGINAL_USER, 原始家目录: $ORIGINAL_HOME, 用户组: $ORIGINAL_GROUP"
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
    ORIGINAL_GROUP=$(id -gn "$USER" 2>/dev/null || echo "$USER")
    log info "直接执行，当前用户: $ORIGINAL_USER, 当前家目录: $ORIGINAL_HOME, 用户组: $ORIGINAL_GROUP"
fi

# 系统架构检测和标准化
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) DOCKER_ARCH="amd64" ;;
    aarch64|arm64) DOCKER_ARCH="arm64" ;;
    i386|i686) DOCKER_ARCH="i386" ;;
    armv7l) DOCKER_ARCH="armhf" ;;
    *) log error "不支持的架构: $ARCH" ;;
esac

# 获取系统版本信息
UNAME_S=$(uname -s)
if [ "$UNAME_S" = "Darwin" ]; then
    OS="darwin"
    VERSION=$(sw_vers -productVersion 2>/dev/null || uname -r)
    OS_NAME="macOS $VERSION"
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    OS_NAME=$PRETTY_NAME
else
    OS="unknown"
    VERSION=$(uname -r)
    OS_NAME="$OS $VERSION"
fi

# 打印系统信息
log info "检测到系统架构: $ARCH (Docker架构: $DOCKER_ARCH)"
log info "检测到操作系统: $OS_NAME ($OS $VERSION)"

# 检查Docker是否已安装
if command -v docker >/dev/null 2>&1; then
    DOCKER_CURRENT_VERSION=$(docker --version 2>&1 | cut -d' ' -f3 | sed 's/,//')
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

# Docker安装函数
install_docker_darwin() {
    log info "开始安装Docker (macOS)"
    if command -v brew >/dev/null 2>&1; then
        log info "使用 Homebrew 安装 Docker Desktop..."
        sudo -u "$ORIGINAL_USER" brew install --cask docker || log error "brew install --cask docker 失败"
        log info "Docker Desktop 安装成功，请在“应用程序”中启动 Docker"
    else
        log warn "未检测到 Homebrew，请手动下载 Docker Desktop DMG 安装: https://www.docker.com/products/docker-desktop/"
    fi
}

install_docker_debian() {
    log info "开始安装Docker (Debian/Ubuntu系列)"

    # 更新包索引
    apt-get update || log error "无法更新包索引"

    # 安装必要的依赖
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release || log error "无法安装依赖包"

    # 添加Docker官方GPG密钥（带重试，避免网络抖动导致失败）
    local docker_gpg_tmp="/tmp/docker.gpg"
    rm -f "$docker_gpg_tmp"
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 10 https://download.docker.com/linux/$OS/gpg -o "$docker_gpg_tmp" || log error "无法下载Docker GPG密钥"
    gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg "$docker_gpg_tmp" || log error "无法添加Docker GPG密钥"
    rm -f "$docker_gpg_tmp"

    # 设置Docker仓库
    echo "deb [arch=$DOCKER_ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $VERSION_CODENAME $DOCKER_CHANNEL" > /etc/apt/sources.list.d/docker.list || log error "无法添加Docker仓库"

    # 更新包索引
    apt-get update || log error "无法更新包索引（添加仓库后）"

    # 卸载旧版本
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # 安装Docker
    if [ "$DOCKER_VERSION" = "latest" ]; then
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || log error "无法安装Docker"
    else
        apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-compose-plugin || log error "无法安装指定版本的Docker"
    fi
}

install_docker_rhel() {
    log info "开始安装Docker (RHEL/CentOS系列)"

    # 安装必要的依赖
    yum install -y yum-utils || log error "无法安装yum-utils"

    # 添加Docker仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || log error "无法添加Docker仓库"

    # 卸载旧版本
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    # 安装Docker
    if [ "$DOCKER_VERSION" = "latest" ]; then
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || log error "无法安装Docker"
    else
        yum install -y docker-ce-$DOCKER_VERSION docker-ce-cli-$DOCKER_VERSION containerd.io docker-compose-plugin || log error "无法安装指定版本的Docker"
    fi
}

install_docker_fedora() {
    log info "开始安装Docker (Fedora系列)"

    # 安装必要的依赖
    dnf install -y dnf-plugins-core || log error "无法安装dnf-plugins-core"

    # 添加Docker仓库
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || log error "无法添加Docker仓库"

    # 卸载旧版本
    dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    # 安装Docker
    if [ "$DOCKER_VERSION" = "latest" ]; then
        dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || log error "无法安装Docker"
    else
        dnf install -y docker-ce-$DOCKER_VERSION docker-ce-cli-$DOCKER_VERSION containerd.io docker-compose-plugin || log error "无法安装指定版本的Docker"
    fi
}

# 配置Docker数据目录
configure_docker_path() {
    if [ "$OS" = "darwin" ]; then
        return 0
    fi
    log info "配置Docker安装路径(data-root): $DOCKER_INSTALL_PATH"

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
    darwin)
        install_docker_darwin
        exit 0
        ;;
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

# 写入Docker data-root配置
configure_docker_path

# 启动并启用Docker服务
log info "启动Docker服务"
systemctl enable docker || log warn "无法启用Docker服务"
systemctl start docker || log error "无法启动Docker服务"

# 将当前用户添加到docker组（如果不是root）
if [ "$ORIGINAL_USER" != "root" ]; then
    log info "将用户 $ORIGINAL_USER 添加到docker组"
    usermod -aG docker "$ORIGINAL_USER" || log warn "无法将用户添加到docker组"
    log warn "请重新登录或执行 'newgrp docker' 以使组权限生效"
fi

# 验证安装
log info "验证Docker安装"
systemctl is-active --quiet docker && log info "Docker服务正在运行" || log error "Docker服务未运行"
docker --version && log info "Docker命令行工具可用" || log error "Docker命令行工具不可用"

# 运行测试容器
log info "运行Hello World测试容器"
docker run --rm hello-world || log warn "Docker测试容器运行失败，可能需要重启后才能正常使用"

log info "Docker安装完成！"
log info "使用 'docker --version' 查看版本"
log info "使用 'docker run hello-world' 测试安装"

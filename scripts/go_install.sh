#!/bin/bash
#
# 自动下载并安装 Golang
# 用法：sudo ./go_install.sh 1.25.3

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"

logfile=$SCRIPT_ROOT/init.log
# 日志函数，记录操作系统，并且将输出打印到屏幕
function log {
    local msg
    local logtype
    logtype=$1
    msg=$2
    datetime=`date +'%F %H:%M:%S'`
    logformat="${datetime} ${FUNCNAME[@]/log/} [line:${BASH_LINENO[0]}] ${logtype}:${msg}"
    {
    case $logtype in
        debug)
            echo "${logformat}" &>> $logfile;;
        info)
            echo -e "\033[32m $datetime [info] ${msg} \t \033[0m"
            echo "${logformat}" &>> $logfile;;
        warn)
            echo -e "\033[33m $datetime [WARN] ${msg} \t \033[0m"
            echo "${logformat}" &>> $logfile;;
        error)
            echo -e "\033[31m $datetime [ERROR] ${msg} \033[0m"
            echo "${logformat}" &>> $logfile
            exit 1;;
    esac
    }
}

if [ "$EUID" -ne 0 ]; then
  log error "请以 root 或者sudo 命令执行此脚本"
fi

if [ -z "$1" ]; then
  echo "Usage: $0 <go-version>  e.g.: $0 1.25.3"
fi

GO_VERSION="$1"

# 获取原始用户信息（当使用sudo执行时）
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo ~$SUDO_USER)
    log info "检测到sudo执行，原始用户: $ORIGINAL_USER, 原始家目录: $ORIGINAL_HOME"
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
    log info "直接执行，当前用户: $ORIGINAL_USER, 当前家目录: $ORIGINAL_HOME"
fi

# 系统架构
ARCH=$(uname -m)


# 获取系统版本信息（支持 CentOS/RedHat 或 Ubuntu/Debian）
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log error "无法确定操作系统类型。"
fi

# 打印系统信息
log info "检测到系统架构: $ARCH"
log info "检测到操作系统: $OS $VERSION"

# 判断下载链接
case "$ARCH" in
  x86_64) download_tarfile="go$GO_VERSION.linux-amd64.tar.gz" ;;
  i386|i686) download_tarfile="go$GO_VERSION.linux-386.tar.gz" ;;
  aarch64) download_tarfile="go$GO_VERSION.linux-arm64.tar.gz" ;;
  *) log error "不支持的架构: $ARCH";;
esac

download_url="https://golang.google.cn/dl/$download_tarfile"
log info "安装包下载报名：$download_tarfile"
log info "安装包下载链接：$download_url"


if [ -f "/tmp/$download_tarfile" ]; then
    log info "已存在golang 安装包，跳过下载"
else
    log info "准备下载 $ARCH 版... $download_url"
    cd /tmp || log error "无法切换到 /tmp 目录"
    wget --timeout=30 --tries=3 "$download_url" || log error "下载失败，请手动下载后重试脚本，下载地址：$download_url"
fi

# Golang 安装目录创建（使用原始用户的家目录）
if [ -d "$ORIGINAL_HOME/go" ]; then
    log warn "检测到 $ORIGINAL_HOME/go 目录存在，请确认是否需要清理"
else
    mkdir -p "$ORIGINAL_HOME/go" || log error "无法创建 Go 安装目录"
fi
tar -xvzf "/tmp/$download_tarfile" -C "$ORIGINAL_HOME/go" || log error "解压 Go 安装包失败"
mv "$ORIGINAL_HOME/go/go" "$ORIGINAL_HOME/go/go$GO_VERSION" || log error "重命名 Go 目录失败"

# 生成 Go 环境变量配置
generate_go_env_config() {
    cat << EOF
# Go envs
export GOVERSION=go$GO_VERSION # Go 版本设置
export GO_INSTALL_DIR=$ORIGINAL_HOME/go # Go 安装目录
export GOROOT=\$GO_INSTALL_DIR/\$GOVERSION # GOROOT 设置
export GOPATH=\$WORKSPACE/golang # GOPATH 设置
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH # 将 Go 语言自带的和通过 go install 安装的二进制文件加入到 PATH 路径中
export GO111MODULE="on" # 开启 Go moudles 特性
#export GOPROXY=https://goproxy.cn,direct # 安装 Go 模块时，代理服务器设置
export GOPRIVATE=
export GOSUMDB=off # 关闭校验 Go 依赖包的哈希值
EOF
}

# 配置环境变量函数
configure_bashrc() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "# Go envs" "$user_bashrc"; then
        log warn "$user_bashrc 已包含 Go 环境变量配置，请检查配置是否正确"
        return 0
    else
        # 添加工作目录配置
        cat << EOF >> "$user_bashrc"
export WORKSPACE="$user_home/workspace" # 设置工作目录

#创建工作路径
if [ ! -d "$user_home/workspace" ]; then
    mkdir -p "$user_home/workspace"
fi

# Default entry folder
cd \$WORKSPACE # 登录系统，默认进入 workspace 目录

alias ws="cd \$WORKSPACE"

$(generate_go_env_config)
EOF
        log info "已添加 Go 环境变量配置到 $user_bashrc"
        return 0
    fi
}

# 为当前用户（root）配置环境变量
configure_bashrc "$HOME"

# 如果使用sudo执行，也为原始用户配置环境变量
if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
    log info "为原始用户 $ORIGINAL_USER 配置环境变量..."
    configure_bashrc "$ORIGINAL_HOME"

    # 更改Go安装目录的所有权
    if [ -d "$ORIGINAL_HOME/go" ]; then
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/go"
        log info "已将 $ORIGINAL_HOME/go 目录所有权赋予 $ORIGINAL_USER"
    fi

    # 更改workspace目录的所有权（如果已存在）
    if [ -d "$ORIGINAL_HOME/workspace" ]; then
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/workspace"
        log info "已将 $ORIGINAL_HOME/workspace 目录所有权赋予 $ORIGINAL_USER"
    fi

    # 确保Go安装权限正确
    log info "确保Go安装目录权限正确..."
    if [ -d "$ORIGINAL_HOME/go/go$GO_VERSION" ]; then
        chmod -R 755 "$ORIGINAL_HOME/go/go$GO_VERSION"
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/go/go$GO_VERSION"
    fi
else
    # 直接执行时，也需要确保当前用户对Go目录有权限
    log info "确保Go安装目录权限正确..."
    if [ -d "$ORIGINAL_HOME/go/go$GO_VERSION" ]; then
        chmod -R 755 "$ORIGINAL_HOME/go/go$GO_VERSION"
    fi
fi

# 验证安装并初始化 Go 工作区
log info "验证 Go 安装..."

# 设置原始用户的环境变量用于验证
export GOVERSION=go$GO_VERSION
export GO_INSTALL_DIR="$ORIGINAL_HOME/go"
export GOROOT="$GO_INSTALL_DIR/$GOVERSION"
export GOPATH="$ORIGINAL_HOME/workspace/golang"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"

if [ -f "$GOROOT/bin/go" ]; then
    installed_version=$("$GOROOT/bin/go" version | grep -oE 'go[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$installed_version" = "go$GO_VERSION" ]; then
        log info "Go 版本验证成功: $installed_version"

        # 初始化 GOPATH 和工作区
        mkdir -p "$GOPATH" || log error "创建 GOPATH 目录失败"

        # 为原始用户设置GOPATH目录权限
        if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
            chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$GOPATH"
        fi

        cd "$GOPATH" || log error "切换到 GOPATH 目录失败"
        "$GOROOT/bin/go" work init || log warn "Go 工作区初始化失败，可手动执行 'go work init'"

        log info "Golang 安装成功！"
        log info "请执行 'source ~/.bashrc' 或重新登录以加载环境变量"
        if [ "$ORIGINAL_USER" != "$USER" ]; then
            log info "原始用户 $ORIGINAL_USER 的环境变量已配置，请重新登录以生效"
        fi
    else
        log error "Go 版本不匹配，期望: go$GO_VERSION，实际: $installed_version"
    fi
else
    log error "Go 二进制文件未找到: $GOROOT/bin/go，安装可能失败"
fi

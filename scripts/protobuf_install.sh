#!/bin/bash
#
# 自动下载并编译安装 Protobuf 及 protoc-gen-go 插件
# 用法：./protobuf_install.sh [protobuf_version] [protoc_gen_go_version]
# 示例：./protobuf_install.sh v3.21.1 v1.5.2

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

# 检查用户权限并设置 SUDO 前缀命令
if [ "$EUID" -ne 0 ]; then
    # 非root用户，检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        log error "当前用户没有sudo权限，请以root用户或使用sudo命令执行此脚本"
    else
        log info "检测到非root用户但有sudo权限，后续系统级命令将使用 sudo 执行..."
        SUDO="sudo"
    fi
else
    log info "检测到root用户执行，继续执行..."
    SUDO=""
fi

# 获取原始用户信息（当使用sudo执行或无sudo执行时）
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo ~$SUDO_USER)
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
fi

# 卸载 Protobuf 及插件
function do_uninstall {
    log info "开始卸载 Protobuf 及 protoc-gen-go..."

    $SUDO rm -f /usr/local/bin/protoc /usr/local/bin/protoc-gen-go
    $SUDO rm -rf /usr/local/include/google/protobuf
    $SUDO rm -f /usr/local/lib/libproto* /usr/local/lib/libprotoc* 2>/dev/null || true
    if command -v ldconfig >/dev/null 2>&1; then
        $SUDO ldconfig 2>/dev/null || true
    fi

    # 清理 .bashrc 中的环境变量
    cleanup_pb_bashrc() {
        local user_home="$1"
        local user_bashrc="$user_home/.bashrc"
        if [ -f "$user_bashrc" ] && grep -q "# Set PATH to include Protobuf" "$user_bashrc"; then
            sed -i.bak '/# Set PATH to include Protobuf/,+1d' "$user_bashrc" 2>/dev/null || true
            rm -f "$user_bashrc.bak"
            log info "已清理 $user_bashrc 中的 Protobuf 环境变量"
        fi
    }

    cleanup_pb_bashrc "$HOME"
    if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
        cleanup_pb_bashrc "$ORIGINAL_HOME"
    fi

    log info "Protobuf 及插件卸载完成！请执行 'source ~/.bashrc'。"
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
        echo "  ./$0 [pb_version] [gen_go_ver] # 编译安装 Protobuf 及插件"
        echo "  ./$0 uninstall                 # 卸载 Protobuf 及插件并清理环境变量"
        exit 0
        ;;
esac

# 处理 Protobuf 版本参数
if [ -z "$1" ]; then
  protobuf_version="v3.21.1"
  log info "未指定 Protobuf 版本，使用默认版本: $protobuf_version"
else
  protobuf_version="$1"
  [[ "$protobuf_version" != v* ]] && protobuf_version="v$protobuf_version"
  log info "使用指定 Protobuf 版本: $protobuf_version"
fi

# 处理 protoc-gen-go 版本参数
if [ -z "$2" ]; then
  protoc_gen_go_version="v1.5.2"
  log info "未指定 protoc-gen-go 版本，使用默认版本: $protoc_gen_go_version"
else
  protoc_gen_go_version="$2"
  [[ "$protoc_gen_go_version" != v* ]] && protoc_gen_go_version="v$protoc_gen_go_version"
  log info "使用指定 protoc-gen-go 版本: $protoc_gen_go_version"
fi

# 获取原始用户信息（当使用sudo执行或无sudo执行时）
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo ~$SUDO_USER)
    log info "检测到sudo执行，原始用户: $ORIGINAL_USER, 原始家目录: $ORIGINAL_HOME"
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
    log info "直接执行，当前用户: $ORIGINAL_USER, 当前家目录: $ORIGINAL_HOME"
fi

# 判断是否已安装 protoc，若已安装则确认是否重新安装
skip_protobuf_build=false
if command -v protoc >/dev/null 2>&1; then
    cur_pb_raw=$(protoc --version 2>&1 | awk '{print $2}')
    cur_pb_version="v$cur_pb_raw"
    log info "当前 protoc 版本为: $cur_pb_raw ($cur_pb_version)"
    
    if [[ "$cur_pb_version" == "$protobuf_version" ]]; then
        log info "已安装的版本与将要安装的版本相同 ($protobuf_version)，跳过 Protobuf 源码编译安装"
        skip_protobuf_build=true
    else
        log info "已安装的版本 ($cur_pb_version) 与指定版本 ($protobuf_version) 不同"
        # CI 非交互模式自动跳过提示或选择更新
        if [ -t 0 ]; then
            read -p "是否覆盖并重新编译安装 Protobuf $protobuf_version？(y/n): " is_reinstall_pb
            if [[ "$is_reinstall_pb" != "y" ]]; then
                log info "用户选择跳过编译安装 Protobuf"
                skip_protobuf_build=true
            fi
        else
            log info "非交互终端环境，继续自动进行 Protobuf 重新编译安装"
        fi
    fi
fi

# 系统架构与操作系统信息获取
ARCH=$(uname -m)

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log error "无法确定操作系统类型。"
    exit 1
fi

log info "检测到系统架构: $ARCH"
log info "检测到操作系统: $OS $VERSION"

# 安装编译依赖与 Golang 环境
install_dependencies() {
    log info "正在安装 Protobuf 编译依赖及 Go 环境..."

    case $OS in
        'rhel'|'centos'|'fedora'|'rocky'|'almalinux')
            if command -v dnf >/dev/null 2>&1; then
                $SUDO dnf update -y
                $SUDO dnf groupinstall -y "Development Tools"
                $SUDO dnf install -y autoconf automake libtool curl make gcc-c++ unzip git golang
            else
                $SUDO yum update -y
                $SUDO yum groupinstall -y "Development Tools"
                $SUDO yum install -y epel-release.noarch && $SUDO yum update -y
                $SUDO yum install -y autoconf automake libtool curl make gcc-c++ unzip git golang
            fi
            ;;
        'ubuntu'|'debian')
            $SUDO apt update -y
            $SUDO apt install -y build-essential autoconf automake libtool curl make g++ unzip git golang-go
            ;;
        *)
            log error "不支持的操作系统: $OS，请手动安装依赖包"
            exit 1
            ;;
    esac

    log info "依赖包安装完成"
}

# 执行依赖安装
install_dependencies

# 第一步：编译安装 Protobuf
if [ "$skip_protobuf_build" != "true" ]; then
    log info "开始获取 Protobuf $protobuf_version 源码..."
    
    cd /tmp || log error "无法切换到 /tmp 目录"
    rm -rf /tmp/protobuf

    GITHUB_REPO="https://github.com/protocolbuffers/protobuf"
    MIRROR_REPO="https://ghproxy.net/https://github.com/protocolbuffers/protobuf"

    log info "正在克隆 Protobuf 源码 (Tag: $protobuf_version)..."
    git clone -b "$protobuf_version" --depth=1 "$GITHUB_REPO" /tmp/protobuf || {
        log warn "从 GitHub 主源克隆失败，尝试备用镜像源..."
        git clone -b "$protobuf_version" --depth=1 "$MIRROR_REPO" /tmp/protobuf || log error "克隆 Protobuf 源码失败，请检查网络"
    }

    cd /tmp/protobuf || log error "无法进入源码目录"

    log info "更新 Git 子模块..."
    git submodule update --init --recursive || log warn "子模块更新存在警告，尝试继续..."

    log info "生成 configure 脚本 (autogen.sh)..."
    ./autogen.sh || log error "autogen.sh 执行失败"

    log info "配置编译选项 (configure)..."
    ./configure --prefix=/usr/local CFLAGS="-O2" CXXFLAGS="-O2" || log error "configure 配置失败"

    log info "正在编译 Protobuf (使用 $(nproc) 个 CPU 核心)..."
    make -j$(nproc) || log error "编译失败"

    log info "正在安装 Protobuf..."
    $SUDO make install -j$(nproc) || log error "安装失败"

    # 刷新动态链接库缓存（防止 libprotobuf.so 找不到报错）
    if command -v ldconfig >/dev/null 2>&1; then
        $SUDO ldconfig || log warn "ldconfig 刷新失败，如遇到库引用报错请手动运行 sudo ldconfig"
    fi

    log info "Protobuf 源码编译安装完成"
fi

# 验证 protoc 安装
log info "正在验证 protoc 安装..."
if command -v protoc >/dev/null 2>&1; then
    installed_pb_ver=$(protoc --version 2>&1)
    log info "protoc 验证成功: $installed_pb_ver"
else
    log error "protoc 安装失败或未在 PATH 中"
fi

# 第二步：安装 protoc-gen-go
install_protoc_gen_go() {
    log info "正在安装 protoc-gen-go ($protoc_gen_go_version)..."

    if ! command -v go >/dev/null 2>&1; then
        log error "未检测到 Go 环境，无法安装 protoc-gen-go！"
        return 1
    fi

    export GOPROXY="https://goproxy.cn,direct"

    log info "执行 go install github.com/golang/protobuf/protoc-gen-go@$protoc_gen_go_version ..."

    go install "github.com/golang/protobuf/protoc-gen-go@$protoc_gen_go_version"

    local user_gopath
    user_gopath=$(go env GOPATH 2>/dev/null || echo "$HOME/go")
    local gen_go_bin="$user_gopath/bin/protoc-gen-go"

    # 将 protoc-gen-go 复制到系统标准目录 /usr/local/bin
    if [ -f "$gen_go_bin" ]; then
        $SUDO cp -f "$gen_go_bin" /usr/local/bin/protoc-gen-go
        $SUDO chmod +x /usr/local/bin/protoc-gen-go
        log info "已成功安装 protoc-gen-go 并发布至 /usr/local/bin/protoc-gen-go"
    else
        log warn "未在预期路径找到 protoc-gen-go，请检查 GOPATH/GOBIN 设置"
    fi
}

install_protoc_gen_go

# 配置环境变量函数
configure_env() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "# Set PATH to include Protobuf and Go bin" "$user_bashrc" 2>/dev/null; then
        log warn "$user_bashrc 已包含 Protobuf 环境变量配置"
        return 0
    else
        cat << 'EOF' >> "$user_bashrc"

# Set PATH to include Protobuf and Go bin
export PATH=$PATH:/usr/local/bin:$(go env GOPATH 2>/dev/null || echo $HOME/go)/bin
EOF
        log info "已添加 Protobuf/Go 环境变量配置到 $user_bashrc"
        return 0
    fi
}

# 配置环境变量
configure_env "$HOME"
if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
    log info "为原始用户 $ORIGINAL_USER 配置环境变量..."
    configure_env "$ORIGINAL_HOME"
fi

# 验证 protoc-gen-go
log info "正在验证 protoc-gen-go..."
if command -v protoc-gen-go >/dev/null 2>&1; then
    log info "protoc-gen-go 验证成功: $(which protoc-gen-go)"
else
    log warn "未直接识别到 protoc-gen-go 命令，请检查 PATH 是否包含 /usr/local/bin 或 \$GOPATH/bin"
fi

# 清理临时文件
log info "正在清理临时文件..."
rm -rf /tmp/protobuf
log info "临时文件清理完成"

log info "Protobuf 及 protoc-gen-go 自动化安装完成！"
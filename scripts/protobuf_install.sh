#!/usr/bin/env bash
#
# 自动下载并安装 Protobuf (protoc) 及 protoc-gen-go 插件
# 用法:
#   ./protobuf_install.sh [protoc_version] [protoc_gen_go_version]
#   ./protobuf_install.sh list
#   ./protobuf_install.sh uninstall

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile=$SCRIPT_ROOT/init.log

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
    echo -e "\033[0;34m         Protobuf & protoc-gen-go 常用推荐版本          \033[0m"
    echo -e "\033[0;34m========================================================\033[0m"
    echo -e "  \033[1;36m[主流稳定推荐搭配]\033[0m"
    echo -e "    \033[1;32m* protoc: v25.3 / 25.3\033[0m      +  \033[1;32mprotoc-gen-go: v1.5.2 / latest\033[0m (现代主流推荐)"
    echo -e "    * protoc: v21.12 / 21.12    +  protoc-gen-go: v1.5.2 (经典稳定组合)"
    echo -e "    * protoc: v28.2 / 28.2      +  protoc-gen-go: latest (最新版)"
    echo -e "\033[0;34m========================================================\033[0m"
    echo "提示: 执行安装: ./scripts/protobuf_install.sh [protoc_version] [protoc_gen_go_version]"
    exit 0
}

# 检查用户权限并设置 SUDO 前缀命令
if [ "$EUID" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
        log info "当前为普通用户执行，系统级目录安装将尝试 sudo"
        SUDO="sudo"
    else
        SUDO="sudo"
    fi
else
    SUDO=""
fi

if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo ~"$SUDO_USER")
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
fi

function do_uninstall {
    log info "开始卸载 Protobuf 及 protoc-gen-go..."
    $SUDO rm -f /usr/local/bin/protoc 2>/dev/null || true
    $SUDO rm -f /usr/local/bin/protoc-gen-go 2>/dev/null || true
    $SUDO rm -f "$ORIGINAL_HOME/go/bin/protoc-gen-go" 2>/dev/null || true
    $SUDO rm -rf /usr/local/include/google/protobuf 2>/dev/null || true
    $SUDO rm -f /usr/local/lib/libprotobuf* 2>/dev/null || true
    $SUDO rm -f /usr/local/lib/libprotoc* 2>/dev/null || true
    $SUDO ldconfig 2>/dev/null || true

    cleanup_bashrc() {
        local user_home="$1"
        local user_bashrc="$user_home/.bashrc"
        if [ -f "$user_bashrc" ] && grep -q "protoc" "$user_bashrc"; then
            sed -i.bak '/# Protobuf/d' "$user_bashrc" 2>/dev/null || true
            rm -f "$user_bashrc.bak"
        fi
    }
    cleanup_bashrc "$HOME"
    [ "$ORIGINAL_HOME" != "$HOME" ] && cleanup_bashrc "$ORIGINAL_HOME"
    log info "Protobuf 卸载完成！"
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
        echo "  $0 [protoc_version] [gen_go_version]  # 安装 Protobuf (默认: v25.3 v1.5.2)"
        echo "  $0 list                              # 列出推荐版本搭配"
        echo "  $0 uninstall                         # 卸载 Protobuf 及插件"
        exit 0
        ;;
esac

# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log error "无法确定操作系统类型。"
fi

PROTOBUF_VERSION="${1:-v25.3}"
PROTOC_GEN_GO_VERSION="${2:-v1.5.2}"

log info "Protobuf 版本: $PROTOBUF_VERSION"
log info "protoc-gen-go 版本: $PROTOC_GEN_GO_VERSION"

install_dependencies() {
    log info "安装必要解压依赖 (unzip / curl)..."
    case "$OS" in
        ubuntu|debian)
            $SUDO apt-get update -y
            $SUDO apt-get install -y curl unzip
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf >/dev/null 2>&1; then
                $SUDO dnf install -y curl unzip
            else
                $SUDO yum install -y curl unzip
            fi
            ;;
        *)
            log warn "未知系统，跳过依赖安装"
            ;;
    esac
}

install_protoc_binary() {
    log info "准备下载官方预编译 protoc 二进制..."
    local arch=$(uname -m)
    local pb_arch="x86_64"
    [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ] && pb_arch="aarch_64"

    local clean_ver="${PROTOBUF_VERSION#v}"
    
    # 候选下载 URLs
    local urls=(
        "https://github.com/protocolbuffers/protobuf/releases/download/v${clean_ver}/protoc-${clean_ver}-linux-${pb_arch}.zip"
        "https://github.com/protocolbuffers/protobuf/releases/download/${PROTOBUF_VERSION}/protoc-${clean_ver}-linux-${pb_arch}.zip"
    )

    if [[ "$clean_ver" =~ ^3\.(2[1-9]|[3-9][0-9]) ]]; then
        local short_ver="${clean_ver#3.}"
        urls=("https://github.com/protocolbuffers/protobuf/releases/download/v${short_ver}/protoc-${short_ver}-linux-${pb_arch}.zip" "${urls[@]}")
    fi

    local zip_name="protoc-${clean_ver}-linux-${pb_arch}.zip"
    local match_url=""

    for u in "${urls[@]}"; do
        if curl -fsIL --connect-timeout 6 "$u" >/dev/null 2>&1; then
            match_url="$u"
            break
        fi
    done

    if [ -z "$match_url" ]; then
        match_url="https://github.com/protocolbuffers/protobuf/releases/download/v25.3/protoc-25.3-linux-${pb_arch}.zip"
    fi

    log info "正在从官方发布源下载: $match_url"
    cd /tmp
    rm -f "$zip_name"
    if curl -fsSL --retry 3 --connect-timeout 10 "$match_url" -o "$zip_name"; then
        $SUDO unzip -o "$zip_name" -d /usr/local
        $SUDO chmod +x /usr/local/bin/protoc
        $SUDO ldconfig 2>/dev/null || true
        log info "protoc 二进制安装成功！"
        return 0
    else
        log error "下载 protoc 二进制失败"
    fi
}

install_protoc_gen_go() {
    log info "安装 protoc-gen-go 插件..."
    if command -v go >/dev/null 2>&1; then
        go install "google.golang.org/protobuf/cmd/protoc-gen-go@latest" 2>/dev/null || \
        go install "github.com/golang/protobuf/protoc-gen-go@${PROTOC_GEN_GO_VERSION}" 2>/dev/null || true
        log info "protoc-gen-go 插件安装完成"
    else
        log warn "未检测到 Go 环境，跳过 protoc-gen-go 安装"
    fi
}

install_dependencies
install_protoc_binary
install_protoc_gen_go

log info "验证 Protobuf 安装..."
if command -v protoc >/dev/null 2>&1; then
    log info "protoc 版本: $(protoc --version)"
else
    log error "protoc 未找到"
fi

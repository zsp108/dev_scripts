#!/usr/bin/env bash
#
# 自动下载并安装 Golang
# 用法：
#   sudo ./go_install.sh [版本号]              # 安装指定版本 (默认: 1.25.3)
#   ./go_install.sh list                     # 列出官方可用版本
#   sudo ./go_install.sh uninstall [版本|all] # 卸载 Go 环境

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
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true;;
        info)
            echo -e "\033[32m $datetime [info] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true;;
        warn)
            echo -e "\033[33m $datetime [WARN] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true;;
        error)
            echo -e "\033[31m $datetime [ERROR] ${msg} \033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true
            exit 1;;
    esac
    }
}

# 列出官方可用版本 (无需 sudo)
function list_versions {
    log info "正在查询 Go 官方发布版本列表..."
    local raw_json
    raw_json=$(curl -fsSL --connect-timeout 6 "https://golang.google.cn/dl/?mode=json" 2>/dev/null || curl -fsSL --connect-timeout 6 "https://go.dev/dl/?mode=json" 2>/dev/null || true)

    if [ -n "$raw_json" ] && command -v python3 >/dev/null 2>&1; then
        echo "$raw_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print("\033[0;34m========================================================\033[0m")
    print("\033[0;34m               Go (Golang) 官方可安装版本列表           \033[0m")
    print("\033[0;34m========================================================\033[0m")
    for i, item in enumerate(data):
        ver = item.get("version", "").replace("go", "")
        stable = item.get("stable", False)
        if not ver:
            continue
        if stable:
            if i == 0:
                print(f"  \033[1;32m* {ver:<12}\033[0m (最新稳定版 - Latest Stable)")
            else:
                print(f"    {ver:<12} (稳定版)")
        else:
            print(f"    {ver:<12}")
    print("\033[0;34m========================================================\033[0m")
    print("提示: 复制版本号执行安装: sudo ./scripts/go_install.sh <版本号>")
except Exception:
    sys.exit(1)
' && exit 0
    fi

    # 降级方案
    echo "========================================================"
    echo "               Go (Golang) 可用版本列表"
    echo "========================================================"
    echo "$raw_json" | grep -oE '"version": "go[0-9.]+"' | cut -d'"' -f4 | sed 's/go//' | head -n 10 | while read -r v; do
        echo "  $v"
    done
    echo "========================================================"
    echo "提示: 复制版本号执行安装: sudo ./scripts/go_install.sh <版本号>"
    exit 0
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
function get_user_info {
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

# 卸载 Go 及清理环境变量
function do_uninstall {
    check_permission
    get_user_info
    local target_ver="${1:-}"
    log info "开始卸载 Go 环境..."

    if [ -n "$target_ver" ] && [ "$target_ver" != "all" ]; then
        local ver_dir="$ORIGINAL_HOME/go/go$target_ver"
        if [ -d "$ver_dir" ]; then
            rm -rf "$ver_dir"
            log info "已删除 Go 版本目录: $ver_dir"
        else
            log warn "未找到指定 Go 版本目录: $ver_dir"
        fi
    else
        if [ -d "$ORIGINAL_HOME/go" ]; then
            rm -rf "$ORIGINAL_HOME/go"
            log info "已删除 Go 安装目录: $ORIGINAL_HOME/go"
        fi
    fi

    # 清理 .bashrc 中的 Go 环境变量配置
    cleanup_bashrc() {
        local user_home="$1"
        local user_bashrc="$user_home/.bashrc"
        if [ -f "$user_bashrc" ] && grep -q "# Go envs" "$user_bashrc"; then
            sed -i.bak '/# Go envs/,/export GOSUMDB=/d' "$user_bashrc" 2>/dev/null || true
            rm -f "$user_bashrc.bak"
            log info "已清理 $user_bashrc 中的 Go 环境变量配置"
        fi
    }

    cleanup_bashrc "$HOME"
    if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
        cleanup_bashrc "$ORIGINAL_HOME"
    fi

    log info "Go 卸载完成！请执行 'source ~/.bashrc' 使环境变量生效。"
    exit 0
}

# 命令分发
ACTION="${1:-}"
case "$ACTION" in
    list|list-versions|-l|--list)
        list_versions
        ;;
    uninstall|-u|--uninstall|remove)
        shift || true
        do_uninstall "$@"
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0 [版本号]              # 安装指定版本 Go (默认: 1.25.3)"
        echo "  $0 list                       # 列出官方可用版本"
        echo "  sudo $0 uninstall [版本号|all] # 卸载指定版本或全部 Go 环境"
        exit 0
        ;;
esac

check_permission
get_user_info

if [ -z "$1" ]; then
  log warn "未指定版本，使用默认版本: 1.25.3"
  GO_VERSION="1.25.3"
else
  GO_VERSION="$1"
fi

log info "准备安装 Go 版本: $GO_VERSION"

# 系统架构
ARCH=$(uname -m)

# 获取系统版本信息
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log error "无法确定操作系统类型。"
fi

log info "检测到系统架构: $ARCH"
log info "检测到操作系统: $OS $VERSION"

case "$ARCH" in
  x86_64) download_tarfile="go$GO_VERSION.linux-amd64.tar.gz" ;;
  i386|i686) download_tarfile="go$GO_VERSION.linux-386.tar.gz" ;;
  aarch64|arm64) download_tarfile="go$GO_VERSION.linux-arm64.tar.gz" ;;
  *) log error "不支持的架构: $ARCH";;
esac

download_url="https://golang.google.cn/dl/$download_tarfile"
log info "安装包名称：$download_tarfile"
log info "下载链接：$download_url"

if [ -f "/tmp/$download_tarfile" ]; then
    log info "已存在 Go 安装包，跳过下载"
else
    log info "准备下载 $ARCH 版... $download_url"
    cd /tmp || log error "无法切换到 /tmp 目录"
    wget --timeout=30 --tries=3 "$download_url" || log error "下载失败，请手动下载后重试，地址：$download_url"
fi

# 创建安装目录
if [ -d "$ORIGINAL_HOME/go" ]; then
    log warn "检测到 $ORIGINAL_HOME/go 目录存在"
else
    mkdir -p "$ORIGINAL_HOME/go" || log error "无法创建 Go 安装目录"
fi

tar -xzf "/tmp/$download_tarfile" -C "$ORIGINAL_HOME/go" || log error "解压 Go 安装包失败"
rm -rf "$ORIGINAL_HOME/go/go$GO_VERSION"
mv "$ORIGINAL_HOME/go/go" "$ORIGINAL_HOME/go/go$GO_VERSION" || log error "重命名 Go 目录失败"

# 生成 Go 环境变量配置
generate_go_env_config() {
    cat << EOF
# Go envs
export GOVERSION=go$GO_VERSION # Go 版本设置
export GO_INSTALL_DIR=$ORIGINAL_HOME/go # Go 安装目录
export GOROOT=\$GO_INSTALL_DIR/\$GOVERSION # GOROOT 设置
export GOPATH=\${WORKSPACE:-$user_home/workspace}/golang # GOPATH 设置
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH # PATH 路径
export GO111MODULE="on" # 开启 Go modules
#export GOPROXY=https://goproxy.cn,direct # GOPROXY 代理
export GOPRIVATE=
export GOSUMDB=off # 关闭校验
EOF
}

configure_bashrc() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "# Go envs" "$user_bashrc"; then
        log warn "$user_bashrc 已包含 Go 环境变量配置"
        return 0
    else
        cat << EOF >> "$user_bashrc"

$(generate_go_env_config)
EOF
        log info "已添加 Go 环境变量配置到 $user_bashrc"
        return 0
    fi
}

configure_bashrc "$HOME"

if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
    log info "为原始用户 $ORIGINAL_USER 配置环境变量..."
    configure_bashrc "$ORIGINAL_HOME"

    if [ -d "$ORIGINAL_HOME/go" ]; then
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/go"
        chmod -R 755 "$ORIGINAL_HOME/go/go$GO_VERSION"
        log info "已设置 $ORIGINAL_HOME/go 权限与归属为 $ORIGINAL_USER"
    fi
fi

# 验证安装
export GOVERSION=go$GO_VERSION
export GO_INSTALL_DIR="$ORIGINAL_HOME/go"
export GOROOT="$GO_INSTALL_DIR/$GOVERSION"
export GOPATH="$ORIGINAL_HOME/workspace/golang"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"

if [ -f "$GOROOT/bin/go" ]; then
    installed_version=$("$GOROOT/bin/go" version | grep -oE 'go[0-9]+\.[0-9]+(\.[0-9]+)?')
    log info "Go 版本验证成功: $installed_version"

    mkdir -p "$GOPATH" || true
    if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$GOPATH" || true
    fi

    log info "Golang 安装成功！"
    log info "请执行 'source ~/.bashrc' 或重新打开终端加载环境变量"
else
    log error "Go 二进制文件未找到: $GOROOT/bin/go，安装可能失败"
fi

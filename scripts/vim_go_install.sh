#!/usr/bin/env bash
#
# 自动安装 vim-go 插件及配套 Go 工具集
# 用法：./vim_go_install.sh [vim_go_branch_or_tag]
# 示例：sudo ./vim_go_install.sh master

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

# 检查用户权限
if [ "$EUID" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
        log warn "当前非 root 用户且无免密 sudo 权限，部分系统依赖安装可能受限"
    else
        log info "检测到非 root 用户但有 sudo 权限，继续执行..."
    fi
else
    log info "检测到 root 用户执行，继续执行..."
fi

# 获取原始用户信息（当使用 sudo 执行时）
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo ~$SUDO_USER)
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
fi

# 卸载 vim-go 及清理 .vimrc
function do_uninstall {
    log info "开始卸载 vim-go 插件及配置..."

    # 删除插件目录
    rm -rf "$ORIGINAL_HOME/.vim/pack/plugins/start/vim-go"
    rm -rf "$HOME/.vim/pack/plugins/start/vim-go"
    log info "已删除 vim-go 插件目录"

    # 清理 .vimrc
    cleanup_vimrc() {
        local user_vimrc="$1/.vimrc"
        if [ -f "$user_vimrc" ] && grep -q "Vim-Go 推荐基础配置" "$user_vimrc"; then
            sed -i.bak '/" --- Vim-Go 推荐基础配置 ---/,+5d' "$user_vimrc" 2>/dev/null || true
            rm -f "$user_vimrc.bak"
            log info "已清理 $user_vimrc 中的 vim-go 配置"
        fi
    }

    cleanup_vimrc "$ORIGINAL_HOME"
    [ "$ORIGINAL_HOME" != "$HOME" ] && cleanup_vimrc "$HOME"

    log info "vim-go 插件卸载完成！"
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
        echo "  ./$0 [分支名]         # 安装 vim-go 插件 (默认: master)"
        echo "  ./$0 uninstall       # 卸载 vim-go 插件并清理 .vimrc"
        exit 0
        ;;
esac

# 处理 vim-go 版本/分支参数
if [ -z "$1" ]; then
  vim_go_branch="master"
  log info "未指定 vim-go 分支/Tag，使用默认: $vim_go_branch"
else
  vim_go_branch="$1"
  log info "使用指定 vim-go 分支/Tag: $vim_go_branch"
fi

# 获取系统版本信息
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    OS="unknown"
fi

log info "检测到操作系统: $OS"

# 检查并安装基本依赖项 (Vim, Git, Go)
install_dependencies() {
    log info "正在检查基础软件依赖 (Vim, Git, Go)..."

    local need_install=""
    command -v vim >/dev/null 2>&1 || need_install="$need_install vim"
    command -v git >/dev/null 2>&1 || need_install="$need_install git"

    if [ -n "$need_install" ]; then
        log info "正在安装缺失的系统软件包:$need_install ..."
        case $OS in
            'rhel'|'centos'|'fedora'|'rocky'|'almalinux')
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y $need_install
                else
                    yum install -y $need_install
                fi
                ;;
            'ubuntu'|'debian')
                apt update -y
                apt install -y $need_install
                ;;
            *)
                log warn "无法自动安装软件包:$need_install，请确保已手动安装"
                ;;
        esac
    fi

    # 专门检查 Go 环境并自动探测可能路径
    if ! command -v go >/dev/null 2>&1; then
        for p in /usr/local/go/bin "$HOME"/go/go*/bin "$ORIGINAL_HOME"/go/go*/bin; do
            if [ -x "$p/go" ]; then
                export PATH="$p:$PATH"
                break
            fi
        done
    fi

    if ! command -v go >/dev/null 2>&1; then
        log error "未检测到 Go 环境！vim-go 依赖 Go 环境，请先安装 Go 后重试"
    else
        log info "Go 环境已就绪: $(go version)"
    fi
}

install_dependencies

# 第一步：安装 vim-go 插件
install_vim_go_plugin() {
    local plugin_start_dir="$ORIGINAL_HOME/.vim/pack/plugins/start"
    local vim_go_target_dir="$plugin_start_dir/vim-go"

    log info "准备安装 vim-go 到目录: $vim_go_target_dir"

    # 创建 Vim 8+ 原生插件目录
    if [ "$ORIGINAL_USER" != "$USER" ]; then
        sudo -u "$ORIGINAL_USER" mkdir -p "$plugin_start_dir"
    else
        mkdir -p "$plugin_start_dir"
    fi

    # 判断目录是否已存在
    if [ -d "$vim_go_target_dir" ]; then
        log info "检测到已存在 vim-go 插件目录"
        read -p "是否删除并重新克隆安装 vim-go？(y/n): " is_reclone
        if [[ "$is_reclone" == "y" ]]; then
            rm -rf "$vim_go_target_dir"
            log info "已删除旧版 vim-go"
        else
            log info "跳过 vim-go 插件克隆，保持现有目录"
            return 0
        fi
    fi

    # 准备 GitHub 仓库地址与备用镜像
    GITHUB_REPO="https://github.com/fatih/vim-go.git"
    MIRROR_REPO="https://ghproxy.net/https://github.com/fatih/vim-go.git"

    log info "正在克隆 vim-go 仓库 (分支/Tag: $vim_go_branch)..."

    if [ "$ORIGINAL_USER" != "$USER" ]; then
        sudo -u "$ORIGINAL_USER" git clone -b "$vim_go_branch" --depth=1 "$GITHUB_REPO" "$vim_go_target_dir" || {
            log warn "从 GitHub 克隆失败，尝试备用镜像源..."
            sudo -u "$ORIGINAL_USER" git clone -b "$vim_go_branch" --depth=1 "$MIRROR_REPO" "$vim_go_target_dir" || log error "克隆 vim-go 仓库失败，请检查网络"
        }
    else
        git clone -b "$vim_go_branch" --depth=1 "$GITHUB_REPO" "$vim_go_target_dir" || {
            log warn "从 GitHub 克隆失败，尝试备用镜像源..."
            git clone -b "$vim_go_branch" --depth=1 "$MIRROR_REPO" "$vim_go_target_dir" || log error "克隆 vim-go 仓库失败，请检查网络"
        }
    fi

    log info "vim-go 插件代码下载完成"
}

install_vim_go_plugin

# 第二步：安装 vim-go 所需的 Go 工具集 (:GoInstallBinaries)
install_go_binaries() {
    log info "准备安装 vim-go 所需的 Go 依赖工具 (guru, godef, goimports, gopls 等)..."

    export GOPROXY="https://goproxy.cn,direct"

    local test_file="/tmp/test_vim_go_init.go"
    echo 'package main' > "$test_file"
    [ "$ORIGINAL_USER" != "$USER" ] && chown "$ORIGINAL_USER:$ORIGINAL_USER" "$test_file" 2>/dev/null || true

    log info "通过 Vim 静默模式自动执行 :GoInstallBinaries ..."

    # 适配无 TTY / CI Headless 环境
    if [ "$ORIGINAL_USER" != "$USER" ]; then
        sudo -u "$ORIGINAL_USER" GOPROXY="${GOPROXY}" vim -es -u NONE \
            -c "set runtimepath+=$ORIGINAL_HOME/.vim/pack/plugins/start/vim-go" \
            -c "runtime ftplugin/go.vim" \
            -c "GoInstallBinaries" \
            -c "qa!" "$test_file" 2>/dev/null || true
    else
        GOPROXY="${GOPROXY}" vim -es -u NONE \
            -c "set runtimepath+=$ORIGINAL_HOME/.vim/pack/plugins/start/vim-go" \
            -c "runtime ftplugin/go.vim" \
            -c "GoInstallBinaries" \
            -c "qa!" "$test_file" 2>/dev/null || true
    fi

    rm -f "$test_file"
    log info "Go 工具集安装指令执行完成"
}

install_go_binaries

# 自动配置 .vimrc
configure_vimrc() {
    local user_vimrc="$ORIGINAL_HOME/.vimrc"
    log info "检查 $user_vimrc 配置..."

    if [ -f "$user_vimrc" ] && grep -q "filetype plugin indent on" "$user_vimrc" 2>/dev/null; then
        log info "$user_vimrc 已包含插件基础配置"
    else
        log info "添加 vim-go 推荐基础配置到 $user_vimrc ..."
        cat << 'EOF' >> "$user_vimrc"

" --- Vim-Go 推荐基础配置 ---
syntax on
filetype plugin indent on
let g:go_fmt_command = "goimports"
let g:go_autodetect_gopath = 1
let g:go_list_type = "quickfix"
EOF
        [ "$ORIGINAL_USER" != "$USER" ] && chown "$ORIGINAL_USER:$ORIGINAL_USER" "$user_vimrc" 2>/dev/null || true
        log info "已成功更新 $user_vimrc"
    fi
}

configure_vimrc

# 验证二进制工具
log info "正在验证已安装的 Go 工具..."
gopath_bin=$(sudo -u "$ORIGINAL_USER" go env GOPATH 2>/dev/null || go env GOPATH 2>/dev/null || echo "$ORIGINAL_HOME/go")/bin

if [ -d "$gopath_bin" ]; then
    installed_tools=$(ls "$gopath_bin" 2>/dev/null | tr '\n' ' ')
    log info "已在 $gopath_bin 中检测到以下 Go 工具:"
    log info "$installed_tools"
else
    log warn "未找到 $gopath_bin 目录，请确保 GOPATH/bin 已加入系统 PATH 环境变量"
fi

log info "vim-go 插件及依赖工具安装完成！"
log info "提示：如需重新更新或补全 Go 工具，可在任意 .go 文件中打开 Vim 并输入命令： :GoInstallBinaries"
#!/usr/bin/env bash
#
# 自动下载并安装 gitlint commit message 校验工具
# 用法：./go_install.sh 

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

# 卸载 gitlint
function do_uninstall {
    log "info" "开始卸载 gitlint..."
    if [ -f "/usr/local/bin/gitlint" ]; then
        if [ -w "/usr/local/bin" ] || [ "$EUID" -eq 0 ]; then
            rm -f "/usr/local/bin/gitlint"
        else
            sudo rm -f "/usr/local/bin/gitlint"
        fi
        log "info" "已删除 /usr/local/bin/gitlint"
    fi
    rm -f "$HOME/.local/bin/gitlint"
    log "info" "gitlint 卸载完成！"
    exit 0
}

# 检查参数
ACTION="${1:-}"
case "$ACTION" in
    uninstall|-u|--uninstall|remove)
        do_uninstall
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  $0            # 编译并安装 gitlint"
        echo "  $0 uninstall  # 卸载 gitlint"
        exit 0
        ;;
esac

# 检查Go环境是否安装
function check_go_environment {
    log "info" "检查Go环境..."

    if ! command -v go &> /dev/null; then
        log "error" "Go未安装，请先安装Go语言环境"
    fi

    local go_version=$(go version 2>&1)
    if [[ $? -eq 0 ]]; then
        log "info" "检测到Go环境: $go_version"
    else
        log "error" "Go版本检查失败，请确保Go正确安装"
    fi
}

# Install Go-gitlint
function install_go_gitlint() {
    log "info" "开始安装go-gitlint..."

    # 检查go-gitlint目录是否已存在
    if [[ -d /tmp/go-gitlint ]]; then
        log "info" "go-gitlint目录已��在，跳过git clone步骤"
        cd /tmp/go-gitlint
    else
        log "info" "克隆go-gitlint仓库..."
        cd /tmp && git clone https://github.com/llorllale/go-gitlint.git
        cd go-gitlint
    fi

    # 首先尝试直接构建
    log "info" "尝试直接构建go-gitlint..."
    if make build; then
        log "info" "直接构建成功"
    else
        log "warn" "直接构建失败，设置Go代理后重试..."

        # 设置Go代理以解决模块下载问题
        export GOPROXY=https://goproxy.cn,direct
        export GOSUMDB=sum.golang.google.cn
        log "info" "已设置GOPROXY: $GOPROXY"

        # 清理模块缓存后重新构建
        log "info" "清理模块缓存并重新构建..."
        go clean -modcache

        if ! make build; then
            log "error" "使用代理构建仍然失败"
            # cd .. && rm -rf go-gitlint
            return 1
        fi

        log "info" "使用代理构建成功"
    fi

    # 检查构建结果
    if [[ -f gitlint ]]; then
        # 检查是否有权限写入/usr/local/bin
        if [[ -w /usr/local/bin ]] || command -v sudo &> /dev/null; then
            if command -v sudo &> /dev/null; then
                sudo mv gitlint /usr/local/bin/gitlint
                log "info" "gitlint二进制文件已通过sudo移动到/usr/local/bin/"
            else
                mv gitlint /usr/local/bin/gitlint
                log "info" "gitlint二进制文件已移动到/usr/local/bin/"
            fi
        else
            # 如果没有sudo权限，安装到用户本地目录
            local install_dir="$HOME/.local/bin"
            mkdir -p "$install_dir"
            mv gitlint "$install_dir/gitlint"
            log "info" "gitlint二进制文件已移动到$install_dir/"

            # 检查是否需要添加到PATH
            if [[ ":$PATH:" != *":$install_dir:"* ]]; then
                log "warn" "请将 $install_dir 添加到您的PATH环境变量中"
                log "info" "可以在 ~/.bashrc 或 ~/.zshrc 中添加: export PATH=\"\$PATH:$install_dir\""
                log "info" "然后运行: source ~/.bashrc (或 source ~/.zshrc)"
            fi
        fi
    else
        log "error" "构建失败，未找到gitlint二进制文件"
        # cd .. && rm -rf go-gitlint
        return 1
    fi

    cd .. && rm -rf go-gitlint

    # 验证安装
    if command -v gitlint &> /dev/null; then
        log "info" "go-gitlint安装成功"
        gitlint --help
    else
        log "error" "go-gitlint安装失败"
        return 1
    fi
}

# 主函数
function main {
    log "info" "开始执行gitlint安装脚本"

    # 检查Go环境
    check_go_environment

    # 安装gitlint
    install_go_gitlint

    log "info" "gitlint安装完成"
}

# 执行主函数
main "$@"
#!/bin/bash
#
# 环境初始化脚本
# 设置工作目录和代理
# 用法：./env_init.sh [proxy_ip:port]
# 示例：./env_init.sh                    # 仅设置工作目录
#       ./env_init.sh 10.10.30.174:10808 # 设置工作目录并配置代理

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"

logfile=$SCRIPT_ROOT/env_init.log
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

# 显示帮助信息
show_help() {
    cat << EOF
环境初始化脚本

用法: $0 [proxy_ip:port]

参数:
  proxy_ip:port    代理服务器地址和端口 (可选)

示例:
  $0                           # 设置工作目录
  $0 10.10.30.174:10808        # 设置工作目录和代理

功能:
  ✓ 配置中文支持 (UTF-8 编码)
  ✓ 创建并配置工作目录 (~/workspace)
  ✓ 添加 ws 别名快速切换到工作目录
  ✓ 可选配置代理开关函数 (setproxy/unssetproxy/proxy_status)

EOF
}

# 解析命令行参数
PROXY_IP_PORT=""
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        # 无参数，仅配置工作目录
        log info "未提供代理参数，仅配置工作目录"
        ;;
    *)
        PROXY_IP_PORT="$1"
        log info "检测到代理参数: $PROXY_IP_PORT"

        # 验证代理参数格式 (IP:PORT)
        if ! echo "$PROXY_IP_PORT" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$'; then
            log error "代理参数格式错误，请使用 IP:PORT 格式，例如: 10.10.30.174:10808"
        fi
        ;;
esac

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

# 代理配置函数
configure_proxy() {
    local user_home="$1"
    local proxy_ip="$2"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "=== V2Ray 本地代理开关 ===" "$user_bashrc"; then
        log warn "$user_bashrc 已包含代理配置，请检查配置是否正确"
        return 0
    else
        # 添加代理配置
        cat << EOF >> "$user_bashrc"

# === V2Ray 本地代理开关 ===
function setproxy() {
    export http_proxy="socks5://$proxy_ip"
    export https_proxy="socks5://$proxy_ip"
    export ftp_proxy="socks5://$proxy_ip"
    export no_proxy="172.16.x.x"
    echo "✅ 已开启终端代理"
}

function unsetproxy() {
    unset http_proxy https_proxy ftp_proxy no_proxy
    echo "✅ 已关闭终端代理"
}

# 代理状态检查函数
function proxy_status() {
    if [ -n "\$http_proxy" ]; then
        echo "🔄 代理已开启: \$http_proxy"
    else
        echo "⚡ 代理已关闭"
    fi
}
EOF
        log info "已添加代理配置到 $user_bashrc"
        return 0
    fi
}

# 中文支持配置函数
configure_locale() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "export LANG=en_US.UTF-8" "$user_bashrc"; then
        log warn "$user_bashrc 已包含中文支持配置，请检查配置是否正确"
        return 0
    else
        # 添加中文支持配置
        cat << EOF >> "$user_bashrc"

# 中文支持配置
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF
        log info "已添加中文支持配置到 $user_bashrc"
        return 0
    fi
}

# 工作目录配置函数
configure_workspace() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"


    if grep -q "export WORKSPACE=" "$user_bashrc"; then
        log warn "$user_bashrc 已包含工作目录配置，请检查配置是否正确"
        return 0
    else
        # 添加工作目录配置
        cat << EOF >> "$user_bashrc"

# 工作目录配置
export WORKSPACE="$user_home/workspace" # 设置工作目录

#创建工作路径
if [ ! -d "$user_home/workspace" ]; then
    mkdir -p "$user_home/workspace"
fi

# Default entry folder
cd \$WORKSPACE # 登录系统，默认进入 workspace 目录

alias ws="cd \$WORKSPACE"
EOF
        log info "已添加工作目录配置到 $user_bashrc"
        return 0
    fi
}

# 为当前用户（root）配置中文支持和工作目录
configure_locale "$HOME"
configure_workspace "$HOME"

# 如果提供了代理参数，配置代理
if [ -n "$PROXY_IP_PORT" ]; then
    log info "为当前用户配置代理..."
    configure_proxy "$HOME" "$PROXY_IP_PORT"
fi

# 如果使用sudo执行，也为原始用户配置工作目录和代理
if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
    log info "为原始用户 $ORIGINAL_USER 配���中文支持..."
    configure_locale "$ORIGINAL_HOME"

    log info "为原始用户 $ORIGINAL_USER 配置工作目录..."
    configure_workspace "$ORIGINAL_HOME"

    # 如果提供了代理参数，为原始用户配置代理
    if [ -n "$PROXY_IP_PORT" ]; then
        log info "为原始用户 $ORIGINAL_USER 配置代理..."
        configure_proxy "$ORIGINAL_HOME" "$PROXY_IP_PORT"
    fi

    # 更改workspace目录的所有权（如果已存在）
    if [ -d "$ORIGINAL_HOME/workspace" ]; then
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/workspace"
        log info "已将 $ORIGINAL_HOME/workspace 目录所有权赋予 $ORIGINAL_USER"
    fi
fi

# 立即创建工作目录
if [ ! -d "$ORIGINAL_HOME/workspace" ]; then
    mkdir -p "$ORIGINAL_HOME/workspace"
    log info "已创建工作目录: $ORIGINAL_HOME/workspace"
else
    log info "工作目录已存在: $ORIGINAL_HOME/workspace"
fi

# 设置工作目录权限
if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
    chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/workspace"
    log info "已设置工作目录权限"
fi

# 显示配置总结
log info "环境初始化完成！"
log info "✓ 中文支持已配置: UTF-8 编码"
log info "✓ 工作目录已配置: $ORIGINAL_HOME/workspace"


if [ -n "$PROXY_IP_PORT" ]; then
    log info "✓ 代理已配置: $PROXY_IP_PORT"
    log info "  使用方法:"
    log info "    setproxy      - 开启代理"
    log info "    unsetproxy    - 关闭代理"
    log info "    proxy_status  - 检查代理状态"
else
    log info "ℹ  未配置代理 (如需配置，请使用: ./env_init.sh IP:PORT)"
fi

log info ""
log info "请执行 'source ~/.bashrc' 或重新登录以加载环境变量"
if [ "$ORIGINAL_USER" != "$USER" ]; then
    log info "原始用户 $ORIGINAL_USER 的环境变量已配置，请重新登录以生效"
fi
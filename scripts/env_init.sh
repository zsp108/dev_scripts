#!/bin/bash
#
# 环境初始化脚本
# - 配置工作目录 & 字符集
# - 配置代理
#
# 模式:
#   env   : 仅环境（字符集 + WORKSPACE）
#   proxy : 仅代理
#   all   : 环境 + 代理（默认）
#
# 兼容旧用法:
#   ./env_init.sh 127.0.0.1:10808
#
# 新用法:
#   ./env_init.sh all   127.0.0.1 socket 10808
#   ./env_init.sh all   127.0.0.1 http   10809
#   ./env_init.sh proxy 127.0.0.1 socket 10808
#   ./env_init.sh proxy 127.0.0.1 http   10809
#   ./env_init.sh env   # 只配环境

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile="$SCRIPT_ROOT/env_init.log"

### 日志函数 ##########################################################
function log {
    local msg="$2"
    local logtype="$1"
    local datetime
    datetime=$(date +'%F %H:%M:%S')
    local logformat="${datetime} ${FUNCNAME[@]/log/} [line:${BASH_LINENO[0]}] ${logtype}:${msg}"

    {
    case "$logtype" in
        debug)
            echo "${logformat}" >> "$logfile" 2>&1
            ;;
        info)
            echo -e "\033[32m $datetime [info] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1
            ;;
        warn)
            echo -e "\033[33m $datetime [WARN] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1
            ;;
        error)
            echo -e "\033[31m $datetime [ERROR] ${msg} \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1
            exit 1
            ;;
    esac
    }
}

### 帮助 ###############################################################
show_help() {
    local prog
    prog=$(basename "$0")

    cat << EOF
环境初始化脚本

用法:
  $prog [MODE] [代理参数]

MODE:
  env           仅配置环境（字符集 + WORKSPACE）
  proxy         仅配置代理
  all           环境 + 代理（默认）

代理参数:
  旧格式（默认使用 socks5）:
    IP:PORT
      例: 127.0.0.1:10808

  新格式:
    IP TYPE PORT
      TYPE 支持: socket / socks5 / http / https
      例:
        127.0.0.1 socket 10808   # socks5 代理
        127.0.0.1 http   10809   # http  代理

示例:
  # 只配置环境（字符集 + 工作目录），不配置代理
  $prog
  $prog env

  # 环境 + 代理（all 模式，默认）
  $prog 127.0.0.1:10808
  $prog all 127.0.0.1 socket 10808
  $prog all 127.0.0.1 http   10809

  # 只配置 / 更新代理，不动环境
  $prog proxy 127.0.0.1:10808
  $prog proxy 127.0.0.1 socket 10808
  $prog proxy 127.0.0.1 http   10809

说明:
  - 环境配置包括:
      * 设置 LANG / LC_ALL 为 en_US.UTF-8
      * 创建 ~/workspace 目录
      * 在 ~/.bashrc 中添加 WORKSPACE 环境变量与 ws 别名
  - 代理配置会在 ~/.bashrc 中添加:
      * setproxy      开启代理
      * unsetproxy    关闭代理
      * showproxy     展示当前代理配置
      * proxy_status  查看代理状态（同 showproxy）
    多次执行 $prog proxy ... 会更新同一段 setproxy 配置，而不会重复追加。

EOF
}


### 卸载/清理环境配置 ##############################################
do_clean_env() {
    log info "开始清理环境配置与代理设置..."

    clean_user_bashrc() {
        local user_home="$1"
        local user_bashrc="$user_home/.bashrc"

        if [ -f "$user_bashrc" ]; then
            # 清理代理函数段
            sed -i.bak '/# Proxy config/,/showproxy$/d' "$user_bashrc" 2>/dev/null || true
            sed -i.bak '/function setproxy()/,/showproxy$/d' "$user_bashrc" 2>/dev/null || true
            # 清理 WORKSPACE 与别名
            sed -i.bak '/export WORKSPACE=/d' "$user_bashrc" 2>/dev/null || true
            sed -i.bak '/alias ws=/d' "$user_bashrc" 2>/dev/null || true
            sed -i.bak '/export LANG=en_US.UTF-8/d' "$user_bashrc" 2>/dev/null || true
            sed -i.bak '/export LC_ALL=en_US.UTF-8/d' "$user_bashrc" 2>/dev/null || true
            rm -f "$user_bashrc.bak"
            log info "已清理 $user_bashrc 中的环境变量与代理设置"
        fi
    }

    clean_user_bashrc "$HOME"
    if [ -n "$SUDO_USER" ]; then
        local orig_home
        orig_home=$(eval echo ~"$SUDO_USER")
        [ "$orig_home" != "$HOME" ] && clean_user_bashrc "$orig_home"
    fi

    log info "环境与代理配置清理完成！请执行 'source ~/.bashrc'。"
    exit 0
}

### 解析模式 ###########################################################
MODE="all"

case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    clean|uninstall|-u|--uninstall)
        do_clean_env
        ;;
    env|proxy|all)
        MODE="$1"
        shift
        ;;
esac

### 解析代理参数（只在非 env 模式下解析） ############################
PROXY_IP_PORT=""   # 形如 127.0.0.1:10808
PROXY_SCHEME=""    # socks5/http/https
PROXY_DESC=""

if [ "$MODE" != "env" ]; then
    if [ "$#" -eq 0 ]; then
        # 不配代理也可以
        :
    elif [ "$#" -eq 1 ]; then
        # 旧格式：IP:PORT，默认 socks5
        PROXY_IP_PORT="$1"
        log info "检测到旧格式代理参数: $PROXY_IP_PORT (默认 socks5)"
        if ! echo "$PROXY_IP_PORT" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+$'; then
            log error "代理参数格式错误，请使用 IP:PORT 格式，例如: 127.0.0.1:10808"
        fi
        PROXY_SCHEME="socks5"
        PROXY_DESC="${PROXY_SCHEME}://${PROXY_IP_PORT}"
    elif [ "$#" -eq 3 ]; then
        # 新格式: IP TYPE PORT
        PROXY_IP="$1"
        PROXY_TYPE="$2"
        PROXY_PORT="$3"

        log info "检测到新格式代理参数: IP=$PROXY_IP TYPE=$PROXY_TYPE PORT=$PROXY_PORT"

        if ! echo "$PROXY_IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
            log error "IP 格式错误，请使用类似 127.0.0.1 的 IPv4 地址"
        fi

        if ! echo "$PROXY_PORT" | grep -qE '^[0-9]+$'; then
            log error "端口格式错误，请使用数字，例如: 10808"
        fi

        case "$PROXY_TYPE" in
            socket|socks5|SOCKS5|SOCKET)
                PROXY_SCHEME="socks5"
                ;;
            http|HTTP)
                PROXY_SCHEME="http"
                ;;
            https|HTTPS)
                PROXY_SCHEME="https"
                ;;
            *)
                log error "不支持的代理类型: $PROXY_TYPE，仅支持 socket/socks5/http/https"
                ;;
        esac

        PROXY_IP_PORT="${PROXY_IP}:${PROXY_PORT}"
        PROXY_DESC="${PROXY_SCHEME}://${PROXY_IP_PORT}"
    else
        log error "参数错误。使用 -h 或 --help 查看用法说明。"
    fi
fi

### 当前用户 / 原始用户 #################################################
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(eval echo "~$SUDO_USER")
    log info "检测到 sudo 执行，原始用户: $ORIGINAL_USER, 原始家目录: $ORIGINAL_HOME"
else
    ORIGINAL_USER="$USER"
    ORIGINAL_HOME="$HOME"
    log info "直接执行，当前用户: $ORIGINAL_USER, 当前家目录: $ORIGINAL_HOME"
fi

### 函数：代理配置（独立模块） #######################################
configure_proxy() {
    local user_home="$1"
    local proxy_scheme="$2"   # socks5/http/https
    local proxy_ip_port="$3"  # IP:PORT
    local user_bashrc="$user_home/.bashrc"

    # 如果已有 "=== 通用代理开关 ===" 标记，则只更新其中的地址
    if grep -q "=== 通用代理开关 ===" "$user_bashrc" 2>/dev/null; then
        log info "$user_bashrc 已存在代理配置，执行更新..."

        # 用统一模板重写代理配置块，确保 showproxy/proxy_status 都存在
        local proxy_block
        proxy_block=$(cat <<EOF
# === 通用代理开关 ===
function setproxy() {
    export http_proxy="${proxy_scheme}://${proxy_ip_port}"
    export https_proxy="${proxy_scheme}://${proxy_ip_port}"
    export ftp_proxy="${proxy_scheme}://${proxy_ip_port}"
    export all_proxy="${proxy_scheme}://${proxy_ip_port}"
    export no_proxy="172.16.x.x"
    echo "✅ 已开启终端代理: ${proxy_scheme}://${proxy_ip_port}"
}

function unsetproxy() {
    unset http_proxy https_proxy ftp_proxy all_proxy no_proxy
    echo "✅ 已关闭终端代理"
}

function showproxy() {
    if [ -n "\$http_proxy" ]; then
        echo "🔄 当前代理配置:"
        echo "  http_proxy=\$http_proxy"
        echo "  https_proxy=\$https_proxy"
        echo "  ftp_proxy=\$ftp_proxy"
        echo "  all_proxy=\$all_proxy"
        echo "  no_proxy=\$no_proxy"
    else
        echo "⚡ 代理已关闭"
    fi
}

function proxy_status() {
    showproxy
}
EOF
)

        python3 - "$user_bashrc" <<PY
import sys
from pathlib import Path

path = Path(sys.argv[1])
block = """${proxy_block}
"""
text = path.read_text()
marker = "# === 通用代理开关 ==="
if marker not in text:
    sys.exit(0)

start = text.find(marker)
proxy_status_idx = text.find("function proxy_status()", start)
if proxy_status_idx == -1:
    sys.exit(0)

end = text.find("\n}\n", proxy_status_idx)
if end == -1:
    sys.exit(0)
end += 3  # include trailing newline after closing brace

path.write_text(text[:start] + block + text[end:])
PY

        log info "已更新代理配置为: ${proxy_scheme}://${proxy_ip_port}"
        return 0
    fi

    # 否则为第一次配置，追加一整段
    cat << EOF >> "$user_bashrc"

# === 通用代理开关 ===
function setproxy() {
    export http_proxy="${proxy_scheme}://${proxy_ip_port}"
    export https_proxy="${proxy_scheme}://${proxy_ip_port}"
    export ftp_proxy="${proxy_scheme}://${proxy_ip_port}"
    export all_proxy="${proxy_scheme}://${proxy_ip_port}"
    export no_proxy="172.16.x.x"
    echo "✅ 已开启终端代理: ${proxy_scheme}://${proxy_ip_port}"
}

function unsetproxy() {
    unset http_proxy https_proxy ftp_proxy all_proxy no_proxy
    echo "✅ 已关闭终端代理"
}

function showproxy() {
    if [ -n "\$http_proxy" ]; then
        echo "🔄 当前代理配置:"
        echo "  http_proxy=\$http_proxy"
        echo "  https_proxy=\$https_proxy"
        echo "  ftp_proxy=\$ftp_proxy"
        echo "  all_proxy=\$all_proxy"
        echo "  no_proxy=\$no_proxy"
    else
        echo "⚡ 代理已关闭"
    fi
}

function proxy_status() {
    showproxy
}
EOF

    log info "已添加代理配置到 $user_bashrc (${proxy_scheme}://${proxy_ip_port})"
    return 0
}

### 函数：字符集配置（独立模块） ######################################
configure_locale() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "# 中文支持配置" "$user_bashrc" 2>/dev/null; then
        log info "$user_bashrc 已包含中文支持配置，跳过..."
        return 0
    fi

    cat << 'EOF' >> "$user_bashrc"

# 中文支持配置
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF

    log info "已添加中文支持配置到 $user_bashrc"
    return 0
}

### 函数：工作目录配置（独立模块） ####################################
configure_workspace() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "# 工作目录配置" "$user_bashrc" 2>/dev/null; then
        log info "$user_bashrc 已包含工作目录配置，跳过..."
        return 0
    fi

    cat << EOF >> "$user_bashrc"

# 工作目录配置
export WORKSPACE="$user_home/workspace" # 设置工作目录

# 默认进入工作目录（仅当目录存在）
if [ -d "\$WORKSPACE" ]; then
    cd "\$WORKSPACE"
fi

alias ws="cd \$WORKSPACE"
EOF

    log info "已添加工作目录配置到 $user_bashrc"
    return 0
}

### 模块 1：环境（字符集 + WORKSPACE） #################################
if [ "$MODE" = "all" ] || [ "$MODE" = "env" ]; then
    # 当前用户
    configure_locale "$HOME"
    configure_workspace "$HOME"

    # 原始用户 workspace 目录
    if [ ! -d "$ORIGINAL_HOME/workspace" ]; then
        mkdir -p "$ORIGINAL_HOME/workspace"
        log info "已创建工作目录: $ORIGINAL_HOME/workspace"
    else
        log info "工作目录已存在: $ORIGINAL_HOME/workspace"
    fi

    # sudo 场景下给原始用户 ownership
    if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
        chown -R "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/workspace"
        log info "已设置工作目录权限给 $ORIGINAL_USER"

        log info "为原始用户 $ORIGINAL_USER 配置字符集..."
        configure_locale "$ORIGINAL_HOME"

        log info "为原始用户 $ORIGINAL_USER 配置工作目录..."
        configure_workspace "$ORIGINAL_HOME"
    fi
fi

### 模块 2：代理 #######################################################
if [ "$MODE" = "all" ] || [ "$MODE" = "proxy" ]; then
    if [ -n "$PROXY_IP_PORT" ]; then
        log info "为当前用户配置代理..."
        configure_proxy "$HOME" "$PROXY_SCHEME" "$PROXY_IP_PORT"

        if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
            log info "为原始用户 $ORIGINAL_USER 配置代理..."
            configure_proxy "$ORIGINAL_HOME" "$PROXY_SCHEME" "$PROXY_IP_PORT"
        fi
    else
        log info "MODE=$MODE 但未提供代理参数，跳过代理配置"
    fi
fi

### 总结输出 ###########################################################
log info "环境初始化完成！"

if [ "$MODE" = "all" ] || [ "$MODE" = "env" ]; then
    log info "✓ 环境已配置: 字符集 + 工作目录 ($ORIGINAL_HOME/workspace)"
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "proxy" ]; then
    if [ -n "$PROXY_IP_PORT" ]; then
        log info "✓ 代理已配置: $PROXY_DESC"
        log info "  使用方法:"
        log info "    setproxy      - 开启代理"
        log info "    unsetproxy    - 关闭代理"
        log info "    showproxy     - 展示当前代理设置"
        log info "    proxy_status  - 检查代理状态（同 showproxy）"
    else
        log info "ℹ 未配置代理 (如需配置，请在 all/proxy 模式下提供 IP 信息)"
    fi
fi

log info ""
log info "请执行 'source ~/.bashrc' 或重新登录以加载环境变量"
if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
    log info "原始用户 $ORIGINAL_USER 的环境变量已配置，请重新登录以生效"
fi

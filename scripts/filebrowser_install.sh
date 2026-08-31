#!/usr/bin/env bash
# ==============================================================================
# 脚本名称: filebrowser_install.sh
# 描述:     FileBrowser 轻量级 Web 文件管理器自动化安装、多用户存储隔离与运维管理脚本
# 适用系统: Debian 系列 (Ubuntu, Debian, Deepin, Mint, Kali 等)
#           RedHat 系列 (RHEL, CentOS, Rocky Linux, AlmaLinux, Fedora, openEuler 等)
# 适用架构: x86_64 (amd64), aarch64 (arm64), armv7l, armv6l, i386 (386)
# 用户隔离: 支持多用户空间隔离 (每个用户绑定独立的 Scope 存储目录，完美协同 Samba)
# 服务托管: 智能三级自适应探测 (systemctl ➔ service ➔ direct)
#
# 用法:
#   1. 交互式运行 (自动提权):
#      ./filebrowser_install.sh
#   2. 快速安装 (自动注册服务并启动):
#      sudo ./filebrowser_install.sh install [管理目录路径] [监听端口] [管理员密码]
#      例如: sudo ./filebrowser_install.sh install /data 8080 admin123
#   3. 用户管理 (支持独立目录 Scope 隔离):
#      sudo ./filebrowser_install.sh adduser [用户名] [密码] [专属目录路径]
#      例如: sudo ./filebrowser_install.sh adduser alice 123456 /data/users/alice
#      sudo ./filebrowser_install.sh deluser [用户名]
#      sudo ./filebrowser_install.sh lsusers
#   4. 服务独立注册与管理:
#      sudo ./filebrowser_install.sh service register    # 注册系统服务并开启自启
#      sudo ./filebrowser_install.sh service unregister  # 注销系统服务
#      sudo ./filebrowser_install.sh start|stop|restart|status # 服务启停状态
#   5. 完全卸载:
#      sudo ./filebrowser_install.sh uninstall
# ==============================================================================

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

INSTALL_BIN="/usr/local/bin/filebrowser"
CONFIG_DIR="/etc/filebrowser"
DEFAULT_DB_FILE="${CONFIG_DIR}/filebrowser.db"
ENV_FILE="${CONFIG_DIR}/filebrowser.env"
COMMON_HOST_FILE="/etc/dev_scripts/.server_host"
SAMBA_HOST_FILE="/etc/samba/.server_host"
HOST_RECORD_FILE="${CONFIG_DIR}/.server_host"
CUSTOM_HOST=""
DB_FILE="${FILEBROWSER_DB:-$DEFAULT_DB_FILE}"
LOG_PATH="/var/log/filebrowser.log"
PID_FILE="/var/run/filebrowser.pid"

UNIFIED_SERVICE_NAME="filebrowser"
SYSTEMD_FILE="/etc/systemd/system/${UNIFIED_SERVICE_NAME}.service"
SYSVINIT_FILE="/etc/init.d/${UNIFIED_SERVICE_NAME}"

# 默认版本
DEFAULT_VERSION="v2.63.23"

# 加载已持久化的运行时环境配置
function load_runtime_config {
    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        . "$ENV_FILE" 2>/dev/null || true
    fi
    DB_FILE="${FILEBROWSER_DB:-${DB_FILE:-$DEFAULT_DB_FILE}}"
    ROOT_DIR="${FILEBROWSER_ROOT:-${ROOT_DIR:-/data}}"
    PORT="${FILEBROWSER_PORT:-${PORT:-8080}}"
}

# 保存持久化运行时环境配置
function save_runtime_config {
    local root_dir="$1"
    local port="$2"
    local db_path="$3"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$(dirname "$db_path")"
    cat << EOF > "$ENV_FILE"
# FileBrowser 运行时环境配置 (自动生成与维护)
FILEBROWSER_ROOT="${root_dir}"
FILEBROWSER_PORT="${port}"
FILEBROWSER_DB="${db_path}"
FILEBROWSER_LOG="${LOG_PATH}"
EOF
    chmod 600 "$ENV_FILE" 2>/dev/null || true
}

# 日志函数，记录操作并格式化输出
function log {
    local logtype="$1"
    local msg="$2"
    local datetime
    datetime=$(date +'%F %H:%M:%S')
    local logformat="${datetime} ${FUNCNAME[*]/log/} [line:${BASH_LINENO[0]}] ${logtype}:${msg}"
    
    case "$logtype" in
        debug)
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            ;;
        info)
            echo -e "\033[32m${datetime} [INFO]  ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            ;;
        warn)
            echo -e "\033[33m${datetime} [WARN]  ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            ;;
        error)
            echo -e "\033[31m${datetime} [ERROR] ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            exit 1
            ;;
    esac
}

# 检查用户权限并自动提权 (Self-Elevation)
function check_permission {
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            log info "检测到非 root 用户执行，正在自动切换为 sudo 权限执行..."
            exec sudo bash "$0" "$@"
        else
            log error "当前不是 root 用户且系统中未找到 sudo 命令，请使用 root 用户执行此脚本。"
        fi
    fi
}

# 获取原始用户信息（当使用 sudo 执行时）
function get_original_user {
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(eval echo "~$SUDO_USER")
    else
        ORIGINAL_USER="$USER"
        ORIGINAL_HOME="$HOME"
    fi
}

# 检测系统与架构
function detect_system {
    RAW_ARCH=$(uname -m)
    case "$RAW_ARCH" in
        x86_64|amd64)
            TARGET_ARCH="amd64"
            ;;
        aarch64|arm64)
            TARGET_ARCH="arm64"
            ;;
        armv7l|armhf)
            TARGET_ARCH="armv7"
            ;;
        armv6l)
            TARGET_ARCH="armv6"
            ;;
        i386|i686)
            TARGET_ARCH="386"
            ;;
        *)
            log error "不支持的 CPU 架构: $RAW_ARCH"
            ;;
    esac
    log info "检测到系统 CPU 架构: $RAW_ARCH (适配下载包: $TARGET_ARCH)"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_LIKE="${ID_LIKE,,}"
        VERSION_ID="${VERSION_ID}"
    else
        log error "无法读取 /etc/os-release，不支持此操作系统。"
    fi

    if [[ "$OS_ID" =~ ^(ubuntu|debian|deepin|uos|linuxmint|kali|raspbian)$ ]] || [[ "$OS_LIKE" =~ (debian|ubuntu) ]]; then
        OS_FAMILY="debian"
    elif [[ "$OS_ID" =~ ^(rhel|centos|fedora|rocky|almalinux|ol|anolis|openeuler|kylin)$ ]] || [[ "$OS_LIKE" =~ (rhel|fedora|centos) ]]; then
        OS_FAMILY="redhat"
    else
        OS_FAMILY="linux-generic"
    fi

    log info "检测到操作系统: $OS_ID $VERSION_ID (归类为 $OS_FAMILY 系列)"
}

# 智能探测当前环境服务管理器
function detect_service_manager {
    if [ "$EUID" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
        local systemctl_test
        systemctl_test="$(systemctl is-system-running 2>&1 || true)"
        if [ -d "/run/systemd/system" ] && [[ "$systemctl_test" != *"Failed to connect to bus"* && "$systemctl_test" != *"not been booted with systemd"* && "$systemctl_test" != *"offline"* && "$systemctl_test" != *"Host is down"* ]]; then
            echo "systemd"
            return 0
        fi
    fi

    if [ -d "/etc/init.d" ] || command -v service >/dev/null 2>&1 || command -v update-rc.d >/dev/null 2>&1 || command -v chkconfig >/dev/null 2>&1; then
        echo "sysvinit"
        return 0
    fi

    echo "direct"
}

# 多源智能探测服务器 IP / 域名 (内网 IP + 公网 IP + Samba 已有配置自动复用)
function detect_server_hosts {
    # 1. 探测内网 IP
    PRIVATE_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}')

    # 2. 探测公网 IP (针对阿里云/腾讯云 ECS 等云主机，设置 2 秒超时防卡顿)
    PUBLIC_IP=""
    if command -v curl >/dev/null 2>&1; then
        PUBLIC_IP=$(curl -fsSL --connect-timeout 2 "https://api.ipify.org" 2>/dev/null ||                     curl -fsSL --connect-timeout 2 "http://ip.sb" 2>/dev/null ||                     curl -fsSL --connect-timeout 2 "http://ifconfig.me" 2>/dev/null || true)
    fi

    # 3. 决定默认推荐候选 (优先复用 FileBrowser 自身记录 / Samba 已配置域名 / 公共记录)
    if [ -n "$CUSTOM_HOST" ]; then
        RECOMMENDED_HOST="$CUSTOM_HOST"
    elif [ -f "$HOST_RECORD_FILE" ] && [ -s "$HOST_RECORD_FILE" ]; then
        RECOMMENDED_HOST=$(cat "$HOST_RECORD_FILE" | tr -d ' \n\r')
    elif [ -f "$SAMBA_HOST_FILE" ] && [ -s "$SAMBA_HOST_FILE" ]; then
        RECOMMENDED_HOST=$(cat "$SAMBA_HOST_FILE" | tr -d ' \n\r')
    elif [ -f "$COMMON_HOST_FILE" ] && [ -s "$COMMON_HOST_FILE" ]; then
        RECOMMENDED_HOST=$(cat "$COMMON_HOST_FILE" | tr -d ' \n\r')
    elif [ -n "$PUBLIC_IP" ] && [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        RECOMMENDED_HOST="$PUBLIC_IP"
    elif [ -n "$PRIVATE_IP" ]; then
        RECOMMENDED_HOST="$PRIVATE_IP"
    else
        RECOMMENDED_HOST="<服务器IP/域名>"
    fi

    SERVER_HOST="$RECOMMENDED_HOST"
}

# 获取当前配置的 Web 访问地址
function get_server_host {
    if [ -n "$CUSTOM_HOST" ]; then
        SERVER_HOST="$CUSTOM_HOST"
        return 0
    fi
    if [ -f "$HOST_RECORD_FILE" ] && [ -s "$HOST_RECORD_FILE" ]; then
        SERVER_HOST=$(cat "$HOST_RECORD_FILE" | tr -d ' \n\r')
        return 0
    fi
    if [ -f "$SAMBA_HOST_FILE" ] && [ -s "$SAMBA_HOST_FILE" ]; then
        SERVER_HOST=$(cat "$SAMBA_HOST_FILE" | tr -d ' \n\r')
        return 0
    fi
    if [ -f "$COMMON_HOST_FILE" ] && [ -s "$COMMON_HOST_FILE" ]; then
        SERVER_HOST=$(cat "$COMMON_HOST_FILE" | tr -d ' \n\r')
        return 0
    fi
    detect_server_hosts
}

# 保存持久化地址 (同时同步到全局公共共享文件，供 Samba 等其他服务自动复用)
function save_server_host {
    local h="$1"
    [ -z "$h" ] && return 0
    [ -z "$CONFIG_DIR" ] && CONFIG_DIR="/etc/filebrowser"
    mkdir -p "$CONFIG_DIR" /etc/dev_scripts 2>/dev/null || true
    echo "$h" > "${CONFIG_DIR}/.server_host" 2>/dev/null || true
    echo "$h" > "/etc/dev_scripts/.server_host" 2>/dev/null || true
}

# 交互式确认或手动输入 Web 访问 IP / 域名 (支持一键复用 Samba 配置)
function prompt_server_host {
    if [ -n "$CUSTOM_HOST" ]; then
        SERVER_HOST="$CUSTOM_HOST"
        save_server_host "$SERVER_HOST"
        return 0
    fi

    detect_server_hosts

    echo ""
    echo -e "\033[36m------------------------------------------------------------------------------\033[0m"
    echo -e "\033[33m🌐 Web 访问地址 (IP / 域名) 探测与确认:\033[0m"
    [ -n "$PRIVATE_IP" ] && echo -e "   • 检测到内网局域网 IP: \033[36m${PRIVATE_IP}\033[0m"
    [ -n "$PUBLIC_IP" ]  && echo -e "   • 检测到公网外网 IP:   \033[32m${PUBLIC_IP}\033[0m (推荐用于云服务器 ECS / 外网访问)"
    if [ -f "$SAMBA_HOST_FILE" ] && [ -s "$SAMBA_HOST_FILE" ]; then
        local s_host
        s_host=$(cat "$SAMBA_HOST_FILE" | tr -d ' \n\r')
        echo -e "   • 发现 Samba 已配置的域名/IP: \033[35m${s_host}\033[0m (已自动设为默认推荐)"
    fi

    local default_prompt="${RECOMMENDED_HOST}"
    echo -n "请输入 Web 客户端访问使用的 服务器IP 或 解析域名 [回车默认使用: ${default_prompt}]: "
    read -r user_input_host

    if [ -n "$user_input_host" ]; then
        SERVER_HOST="$user_input_host"
    else
        SERVER_HOST="$RECOMMENDED_HOST"
    fi

    save_server_host "$SERVER_HOST"
    echo -e "\033[36m------------------------------------------------------------------------------\033[0m"
    log info "已设置 Web 访问连接目标地址为: $SERVER_HOST"
}

# 安装基础解压与下载依赖
function install_dependencies {
    log info "检查并安装基础依赖包 (curl, wget, tar, procps)..."
    case "$OS_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y curl wget tar procps
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y curl wget tar procps-ng
            else
                yum install -y curl wget tar procps-ng
            fi
            ;;
        *)
            if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
                log error "系统中缺少 curl 或 wget，请手动安装后重试。"
            fi
            if ! command -v tar >/dev/null 2>&1; then
                log error "系统中缺少 tar 解压工具，请手动安装后重试。"
            fi
            ;;
    esac
    log info "基础依赖检查完成。"
}

# 下载并安装 FileBrowser 二进制文件
function download_filebrowser {
    log info "正在获取 FileBrowser 安装包..."

    local pkg_name="linux-${TARGET_ARCH}-filebrowser.tar.gz"
    local tmp_dir="/tmp/filebrowser_install_$$"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    # 1. 检查本地是否存在离线安装包或二进制 (多路径智能探测)
    local local_search_paths=(
        "${SCRIPT_DIR}/${pkg_name}"
        "$(pwd)/${pkg_name}"
        "/tmp/${pkg_name}"
        "/personal/${pkg_name}"
        "/root/${pkg_name}"
        "${SCRIPT_DIR}/filebrowser"
        "$(pwd)/filebrowser"
        "/tmp/filebrowser"
        "/personal/filebrowser_bin"
    )
    for p in "${local_search_paths[@]}"; do
        if [ -f "$p" ]; then
            if [[ "$p" == *.tar.gz ]] && tar -tzf "$p" >/dev/null 2>&1; then
                log info "检测到本地有效离线安装包: $p，直接使用本地文件..."
                cp -f "$p" "${tmp_dir}/${pkg_name}"
                tar -xzf "${tmp_dir}/${pkg_name}" -C "$tmp_dir" || true
                if [ -f "${tmp_dir}/filebrowser" ]; then
                    cp -f "${tmp_dir}/filebrowser" "$INSTALL_BIN"
                    chmod +x "$INSTALL_BIN"
                    rm -rf "$tmp_dir"
                    log info "FileBrowser 二进制安装成功 (离线包): $("$INSTALL_BIN" version 2>/dev/null || echo "$p")"
                    return 0
                fi
            elif [[ "$p" == *filebrowser ]] && [ -x "$p" ]; then
                log info "检测到本地有效可执行文件: $p，直接复制使用..."
                cp -f "$p" "$INSTALL_BIN"
                chmod +x "$INSTALL_BIN"
                rm -rf "$tmp_dir"
                log info "FileBrowser 二进制安装成功 (本地文件): $("$INSTALL_BIN" version 2>/dev/null || echo "$p")"
                return 0
            fi
        fi
    done

    # 2. 版本探测 (支持 API 直连与加速镜像探测，超时快速 Fallback)
    local version="$DEFAULT_VERSION"
    local latest_ver=""
    local api_urls=(
        "https://api.github.com/repos/filebrowser/filebrowser/releases/latest"
        "https://gh-proxy.com/https://api.github.com/repos/filebrowser/filebrowser/releases/latest"
    )
    for ver_url in "${api_urls[@]}"; do
        latest_ver=$(curl -s --connect-timeout 3 -m 5 "$ver_url" 2>/dev/null | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]' || true)
        if [ -n "$latest_ver" ] && [[ "$latest_ver" =~ ^v?[0-9] ]]; then
            version="$latest_ver"
            log info "检测到 FileBrowser 最新版本: $version"
            break
        fi
    done

    if [ -z "$latest_ver" ] || [[ ! "$latest_ver" =~ ^v?[0-9] ]]; then
        version="$DEFAULT_VERSION"
        log info "使用预设稳定版本: $version"
    fi

    # 3. 构造加速下载源列表 (涵盖高可用国内 CDN 与镜像代理)
    local download_urls=()
    if [ -n "$FILEBROWSER_DOWNLOAD_URL" ]; then
        download_urls+=("$FILEBROWSER_DOWNLOAD_URL")
    fi
    download_urls+=(
        "https://ghproxy.net/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://gh-proxy.net/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://ghfast.top/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://gh.ddlc.top/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://gh.api.99988866.xyz/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://gitproxy.click/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://ghproxy.cc/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://gh-proxy.com/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://github.chenby.cn/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://hub.gitmirror.com/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://mirror.ghproxy.com/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
    )

    local download_success=false
    local target_file="${tmp_dir}/${pkg_name}"

    for url in "${download_urls[@]}"; do
        log info "尝试从下载源获取: $url"
        rm -f "$target_file"
        
        if command -v curl >/dev/null 2>&1; then
            curl -k -f -L --connect-timeout 8 --max-time 120 --retry 1 -o "$target_file" "$url" 2>>"$logfile" || true
        elif command -v wget >/dev/null 2>&1; then
            wget --no-check-certificate -q --timeout=30 --tries=2 -O "$target_file" "$url" 2>>"$logfile" || true
        fi

        # 严格验证是否为有效的 tar.gz 文件（大小 > 1MB 且 tar -tzf 测试正常）
        local f_size=0
        if [ -f "$target_file" ]; then
            f_size=$(stat -c%s "$target_file" 2>/dev/null || wc -c < "$target_file" 2>/dev/null || echo 0)
        fi

        if [ "$f_size" -gt 1000000 ] && tar -tzf "$target_file" >/dev/null 2>&1; then
            log info "安装包下载成功且完整性校验通过 (大小: $((f_size / 1024 / 1024)) MB)！"
            download_success=true
            break
        else
            log warn "当前源下载速度过慢、超时或文件校验失败，切换下一个加速源..."
            rm -f "$target_file"
        fi
    done

    if [ "$download_success" = false ]; then
        echo ""
        echo -e "\033[31m==============================================================================\033[0m"
        echo -e "\033[31m❌ 无法从镜像源自动下载 FileBrowser 安装包 (${pkg_name})\033[0m"
        echo -e "\033[31m==============================================================================\033[0m"
        echo -e "\033[33m💡 离线包极简解决指南 (放置后重新运行脚本即可直接秒装):\033[0m"
        echo -e "   1. 请在宿主机/浏览器下载该安装包:"
        echo -e "      \033[36mhttps://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}\033[0m"
        echo -e "   2. 并将下载好的 \033[32m${pkg_name}\033[0m 上传/移动至以下任意目标路径:"
        echo -e "      • 当前脚本所在目录: \033[32m${SCRIPT_DIR}/${pkg_name}\033[0m"
        echo -e "      • 或系统临时目录:   \033[32m/tmp/${pkg_name}\033[0m"
        echo -e "\033[31m==============================================================================\033[0m"
        echo ""
        log error "无法下载 FileBrowser 安装包，请按上方提示放置离线包后重试。"
    fi

    log info "解压并安装二进制文件到 $INSTALL_BIN ..."
    tar -xzf "${tmp_dir}/${pkg_name}" -C "$tmp_dir" || log error "安装包解压失败！"
    
    if [ ! -f "${tmp_dir}/filebrowser" ]; then
        log error "解压后未找到 filebrowser 二进制文件！"
    fi

    cp -f "${tmp_dir}/filebrowser" "$INSTALL_BIN"
    chmod +x "$INSTALL_BIN"
    rm -rf "$tmp_dir"

    log info "FileBrowser 二进制安装成功: $("$INSTALL_BIN" version 2>/dev/null || echo "$version")"
}

# 配置数据库与初始化参数
function init_filebrowser_config {
    local root_dir="$1"
    local port="$2"
    local admin_pass="$3"
    local db_path="${4:-$DB_FILE}"

    DB_FILE="$db_path"
    local db_dir
    db_dir="$(dirname "$DB_FILE")"
    mkdir -p "$db_dir"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$root_dir"
    chmod -R 0777 "$root_dir" 2>/dev/null || true

    log info "正在初始化 FileBrowser 数据库 ($DB_FILE)..."

    if [ ! -f "$DB_FILE" ]; then
        "$INSTALL_BIN" config init -d "$DB_FILE" >> "$logfile" 2>&1
    fi

    # 解除最小密码长度限制并初始化系统配置 (开启命令执行权限 --disableExec=false)
    "$INSTALL_BIN" config set -d "$DB_FILE" \
        --minimumPasswordLength 1 \
        --address "0.0.0.0" \
        --port "$port" \
        --root "$root_dir" \
        --log "$LOG_PATH" \
        --locale "zh-cn" \
        --disableExec=false \
        --branding.name "云端文件管理器" >> "$logfile" 2>&1 || \
    "$INSTALL_BIN" config set -d "$DB_FILE" \
        --minimumPasswordLength 1 \
        --address "0.0.0.0" \
        --port "$port" \
        --root "$root_dir" \
        --log "$LOG_PATH" \
        --locale "zh-cn" \
        --disable-exec=false \
        --branding.name "云端文件管理器" >> "$logfile" 2>&1

    log info "正在配置默认管理员账户 (admin)..."

    local set_pwd_success=false
    local curr_pass="$admin_pass"

    while [ "$set_pwd_success" = false ]; do
        local err_output
        if "$INSTALL_BIN" users ls -d "$DB_FILE" 2>/dev/null | grep -qw "admin"; then
            err_output=$("$INSTALL_BIN" users update admin -p "$curr_pass" --perm.admin=true --perm.execute=true --scope "." -d "$DB_FILE" 2>&1 || true)
        else
            err_output=$("$INSTALL_BIN" users add admin "$curr_pass" --perm.admin=true --perm.execute=true --scope "." -d "$DB_FILE" 2>&1 || true)
        fi

        if [[ "$err_output" == *"Error:"* ]]; then
            log warn "管理员密码设置未通过安全策略校验: ${err_output}"
            log warn "提示: FileBrowser 拒绝常见弱口令 (如 admin/123456)，建议使用包含字母+数字或特殊字符的密码 (如 Admin@123456)。"
            if [ -t 0 ]; then
                read -r -s -p "请重新输入符合强度的管理员密码 [默认: Admin@123456]: " curr_pass
                echo ""
                curr_pass="${curr_pass:-Admin@123456}"
                ADMIN_PASS="$curr_pass"
            else
                log error "密码被安全策略拦截且处于非交互模式，请指定更强密码！"
            fi
        else
            set_pwd_success=true
            ADMIN_PASS="$curr_pass"
        fi
    done

    save_runtime_config "$root_dir" "$port" "$DB_FILE"
    log info "FileBrowser 基础配置与管理员账户配置完成。"
}

# 配置防火墙放行
function configure_firewall {
    local port="$1"
    log info "正在检查并配置防火墙放行端口: $port ..."

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log info "已在 firewalld 中放行 TCP ${port} 端口。"
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw "active"; then
        ufw allow "${port}/tcp" >/dev/null 2>&1 || true
        log info "已在 ufw 中放行 TCP ${port} 端口。"
    fi
}

# 精确安全地终止 FileBrowser 二进制进程 (严格排除自身脚本 PID，防止被自身误杀)
function stop_filebrowser_processes {
    local my_pid="$$"

    if [ -f "$PID_FILE" ]; then
        local p
        p=$(cat "$PID_FILE" 2>/dev/null || true)
        if [ -n "$p" ] && [ "$p" != "$my_pid" ] && kill -0 "$p" 2>/dev/null; then
            kill -15 "$p" 2>/dev/null || true
            sleep 0.5
            kill -9 "$p" 2>/dev/null || true
        fi
        rm -f "$PID_FILE" 2>/dev/null || true
    fi

    local pids
    pids=$(pgrep -x filebrowser 2>/dev/null || pidof filebrowser 2>/dev/null || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ "$pid" != "$my_pid" ]; then
                local cmd
                cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)
                if [[ "$cmd" != *".sh"* ]]; then
                    kill -15 "$pid" 2>/dev/null || true
                    sleep 0.2
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
        done
    fi
}

# 生成 SysVinit 启动脚本
function generate_sysvinit_script {
    mkdir -p /etc/init.d
    cat << EOF > "$SYSVINIT_FILE"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          filebrowser
# Required-Start:    \$network \$local_fs \$remote_fs
# Required-Stop:     \$network \$local_fs \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: FileBrowser Web File Manager Daemon
# Description:       FileBrowser Service Managed by filebrowser_install.sh
### END INIT INFO

BIN="${INSTALL_BIN}"
ENV_FILE="${ENV_FILE}"
DEFAULT_DB="${DB_FILE}"
PID_FILE="${PID_FILE}"
LOG_FILE="${LOG_PATH}"

if [ -f "\$ENV_FILE" ]; then
    . "\$ENV_FILE" 2>/dev/null || true
fi
DB_FILE="\${FILEBROWSER_DB:-\$DEFAULT_DB}"

start() {
    if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
        echo "FileBrowser is already running (PID: \$(cat "\$PID_FILE"))."
        return 0
    fi
    echo "Starting FileBrowser with DB: \$DB_FILE ..."
    nohup "\$BIN" -d "\$DB_FILE" >> "\$LOG_FILE" 2>&1 &
    echo \$! > "\$PID_FILE"
    sleep 1
    if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
        echo "FileBrowser started successfully (PID: \$(cat "\$PID_FILE"))."
    else
        echo "Failed to start FileBrowser, check log: \$LOG_FILE"
        return 1
    fi
}

stop() {
    if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
        local pid=\$(cat "\$PID_FILE")
        echo "Stopping FileBrowser (PID: \$pid)..."
        kill "\$pid" 2>/dev/null || true
        sleep 1
        kill -9 "\$pid" 2>/dev/null || true
        rm -f "\$PID_FILE"
        echo "FileBrowser stopped."
    else
        stop_filebrowser_processes
        rm -f "\$PID_FILE"
        echo "FileBrowser is not running."
    fi
}

status() {
    if [ -f "\$PID_FILE" ] && kill -0 \$(cat "\$PID_FILE") 2>/dev/null; then
        echo "🟢 FileBrowser is running (PID: \$(cat "\$PID_FILE"))"
        return 0
    elif pgrep -x filebrowser >/dev/null 2>&1; then
        echo "🟢 FileBrowser is running (PID: \$(pgrep filebrowser | tr '\n' ' '))"
        return 0
    else
        echo "🔴 FileBrowser is stopped."
        return 1
    fi
}

case "\$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)
        echo "Usage: service filebrowser {start|stop|restart|status}"
        exit 1
        ;;
esac
exit 0
EOF
    chmod +x "$SYSVINIT_FILE"
}

# 注册系统服务
function register_service {
    load_runtime_config
    log info "开始注册 FileBrowser 系统服务 (DB: $DB_FILE)..."
    local s_mgr
    s_mgr="$(detect_service_manager)"

    generate_sysvinit_script

    case "$s_mgr" in
        systemd)
            log info "【方案一：systemd 生效】检测到 systemctl 环境，正在注册 [${UNIFIED_SERVICE_NAME}.service]..."

            cat << EOF > "$SYSTEMD_FILE"
[Unit]
Description=FileBrowser Web File Manager Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-${ENV_FILE}
ExecStart=${INSTALL_BIN} -d ${DB_FILE} --disableExec=false
Restart=always
RestartSec=3s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
            chmod 644 "$SYSTEMD_FILE"
            systemctl daemon-reload
            systemctl enable "${UNIFIED_SERVICE_NAME}.service" 2>/dev/null || true
            systemctl restart "${UNIFIED_SERVICE_NAME}.service"

            log info "✅ systemd 服务注册并自启成功！"
            log info "   • 服务名称: ${UNIFIED_SERVICE_NAME}.service"
            log info "   • 运维命令: systemctl {start|stop|restart|status} filebrowser"
            ;;

        sysvinit|direct)
            log warn "ℹ️ 未检测到活跃的 systemd 守护进程 (常见于 Docker / 容器 / WSL1 环境)。"
            log info "【方案二：service 生效】正在注册为 SysVinit (service) 系统服务..."

            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "$UNIFIED_SERVICE_NAME" defaults 2>/dev/null || true
            elif command -v chkconfig >/dev/null 2>&1; then
                chkconfig --add "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
                chkconfig "$UNIFIED_SERVICE_NAME" on 2>/dev/null || true
            fi

            if command -v service >/dev/null 2>&1; then
                service "$UNIFIED_SERVICE_NAME" restart || "$SYSVINIT_FILE" restart
            else
                "$SYSVINIT_FILE" restart
            fi

            log info "✅ SysVinit (service) 服务注册并启动成功！"
            log info "   • 服务入口: $SYSVINIT_FILE"
            log info "   • 运维命令: service filebrowser {start|stop|restart|status}"
            ;;
    esac
}

# 注销系统服务
function unregister_service {
    log info "正在注销 FileBrowser 系统服务..."

    if [ -f "$SYSTEMD_FILE" ]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
            systemctl disable "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
        fi
        rm -f "$SYSTEMD_FILE"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload 2>/dev/null || true
        fi
        log info "已清理 systemd 单元: $SYSTEMD_FILE"
    fi

    if [ -f "$SYSVINIT_FILE" ]; then
        if command -v service >/dev/null 2>&1; then
            service "$UNIFIED_SERVICE_NAME" stop 2>/dev/null || true
        else
            "$SYSVINIT_FILE" stop 2>/dev/null || true
        fi

        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d -f "$UNIFIED_SERVICE_NAME" remove 2>/dev/null || true
        elif command -v chkconfig >/dev/null 2>&1; then
            chkconfig --del "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
        fi
        rm -f "$SYSVINIT_FILE"
        log info "已清理 SysVinit 服务文件: $SYSVINIT_FILE"
    fi

    stop_filebrowser_processes
    rm -f "$PID_FILE"
}

# 统一服务控制
function service_control {
    local action="$1"
    local s_mgr
    s_mgr="$(detect_service_manager)"

    log info "正在执行服务操作: $action ..."

    case "$s_mgr" in
        systemd)
            case "$action" in
                start|stop|restart)
                    systemctl "$action" "$UNIFIED_SERVICE_NAME"
                    log info "FileBrowser 服务 [$action] 完成。"
                    ;;
                status)
                    get_server_host
                    echo "--------------------------------------------------------"
                    echo "内网 IP: $LOCAL_IP"
                    echo "systemd 服务状态:"
                    systemctl status "$UNIFIED_SERVICE_NAME" --no-pager 2>/dev/null || true
                    echo "--------------------------------------------------------"
                    ;;
            esac
            ;;

        sysvinit|direct)
            if [ -f "$SYSVINIT_FILE" ]; then
                if command -v service >/dev/null 2>&1; then
                    service "$UNIFIED_SERVICE_NAME" "$action"
                else
                    "$SYSVINIT_FILE" "$action"
                fi
            else
                case "$action" in
                    start)
                        nohup "$INSTALL_BIN" -d "$DB_FILE" --disableExec=false >> "$LOG_PATH" 2>&1 &
                        echo $! > "$PID_FILE"
                        log info "FileBrowser 已在后台启动。"
                        ;;
                    stop)
                        stop_filebrowser_processes
                        rm -f "$PID_FILE"
                        log info "FileBrowser 已停止。"
                        ;;
                    restart)
                        stop_filebrowser_processes
                        rm -f "$PID_FILE"
                        sleep 1
                        nohup "$INSTALL_BIN" -d "$DB_FILE" --disableExec=false >> "$LOG_PATH" 2>&1 &
                        echo $! > "$PID_FILE"
                        log info "FileBrowser 已重启。"
                        ;;
                    status)
                        if pgrep filebrowser >/dev/null 2>&1; then
                            echo "🟢 FileBrowser 正在运行 (PID: $(pgrep filebrowser | tr '\n' ' '))"
                        else
                            echo "🔴 FileBrowser 未运行"
                        fi
                        ;;
                esac
            fi

            if [ "$action" = "status" ]; then
                get_server_host
                echo "--------------------------------------------------------"
                echo "内网 IP: $LOCAL_IP"
                echo "日志文件: $LOG_PATH"
                echo "--------------------------------------------------------"
            fi
            ;;
    esac
}

# 判断 FileBrowser 守护进程/服务是否正在运行
function is_service_running {
    local s_mgr
    s_mgr="$(detect_service_manager)"
    case "$s_mgr" in
        systemd)
            if systemctl is-active --quiet "$UNIFIED_SERVICE_NAME" 2>/dev/null; then
                return 0
            fi
            ;;
    esac

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        return 0
    fi
    if pgrep -x filebrowser >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# 数据库操作前：若服务正在运行则临时暂停（释放 BoltDB 数据库独占写锁）
function pause_service_if_running {
    if is_service_running; then
        WAS_RUNNING=true
        log info "检测到 FileBrowser 服务正在运行 (锁定数据库)，正在临时暂停服务以释放数据库锁..."
        local s_mgr
        s_mgr="$(detect_service_manager)"
        case "$s_mgr" in
            systemd)
                systemctl stop "$UNIFIED_SERVICE_NAME" >/dev/null 2>&1 || true
                ;;
            *)
                if [ -f "$SYSVINIT_FILE" ]; then
                    "$SYSVINIT_FILE" stop >/dev/null 2>&1 || true
                fi
                stop_filebrowser_processes
                ;;
        esac
        sleep 1
    else
        WAS_RUNNING=false
    fi
}

# 数据库操作后：若先前在运行则自动恢复运行
function resume_service_if_was_running {
    if [ "${WAS_RUNNING:-false}" = true ]; then
        log info "数据库配置更新完成，正在自动恢复 FileBrowser 服务运行..."
        local s_mgr
        s_mgr="$(detect_service_manager)"
        case "$s_mgr" in
            systemd)
                systemctl start "$UNIFIED_SERVICE_NAME" >/dev/null 2>&1 || true
                ;;
            *)
                if [ -f "$SYSVINIT_FILE" ]; then
                    "$SYSVINIT_FILE" start >/dev/null 2>&1 || true
                else
                    nohup "$INSTALL_BIN" -d "$DB_FILE" --disableExec=false >> "$LOG_PATH" 2>&1 &
                    echo $! > "$PID_FILE"
                fi
                ;;
        esac
        WAS_RUNNING=false
    fi
}

# 智能解析用户隔离物理路径与 FileBrowser Scope 相对路径
# 核心原理: FileBrowser 的 Scope 是基于全局 Root (如 /personal/samba) 的相对路径
function resolve_user_scope_and_dir {
    local username="$1"
    local raw_input="$2"
    local s_root="${FILEBROWSER_ROOT:-${ROOT_DIR:-/data}}"
    s_root="${s_root%/}"

    # 默认路径
    if [ -z "$raw_input" ]; then
        raw_input="${s_root}/${username}"
    fi

    # 去除末尾斜杠
    raw_input="${raw_input%/}"

    if [[ "$raw_input" == "$s_root"/* ]]; then
        # 输入的是全局 Root 下的绝对路径 (如 /personal/samba/spz)
        local rel_path="${raw_input#"$s_root"}"
        rel_path="${rel_path#/}"
        RESOLVED_SCOPE="/${rel_path}"
        RESOLVED_DIR="${raw_input}"
    elif [[ "$raw_input" == "$s_root" ]]; then
        RESOLVED_SCOPE="/"
        RESOLVED_DIR="${raw_input}"
    elif [[ "$raw_input" == /* ]]; then
        # 输入的是全局 Root 之外的独立物理路径 (如 /mnt/disk2/spz)
        # 在全局根目录下自动创建软链接映射，以防无法访问且无需修改外部目录属性
        local link_name="users_${username}"
        local link_path="${s_root}/${link_name}"
        if [ ! -e "$link_path" ] && [ ! -L "$link_path" ]; then
            ln -s "$raw_input" "$link_path" 2>/dev/null || true
            log info "已在全局根目录建立软链接映射: $link_path -> $raw_input"
        fi
        RESOLVED_SCOPE="/${link_name}"
        RESOLVED_DIR="${raw_input}"
    else
        # 输入的是相对路径 (如 spz 或 users/spz)
        local rel_path="${raw_input#/}"
        RESOLVED_SCOPE="/${rel_path}"
        RESOLVED_DIR="${s_root}/${rel_path}"
    fi
}

# 添加多用户 (Scope 隔离)
function do_adduser {
    load_runtime_config
    local username="$1"
    local password="$2"
    local user_input_scope="$3"

    if [ ! -f "$INSTALL_BIN" ] || [ ! -f "$DB_FILE" ]; then
        log warn "未检测到已安装的 FileBrowser 数据库 ($DB_FILE)，请先运行选项 1 完成初次安装！"
        return 0
    fi

    if [ -z "$username" ]; then
        read -r -p "请输入要创建的用户名: " username
    fi

    local default_scope="${ROOT_DIR}/${username}"
    if [ -z "$user_input_scope" ]; then
        read -r -p "请输入该用户的私有隔离目录 [默认: ${default_scope}]: " user_input_scope
        user_input_scope="${user_input_scope:-$default_scope}"
    fi

    resolve_user_scope_and_dir "$username" "$user_input_scope"

    if [ ! -d "$RESOLVED_DIR" ]; then
        mkdir -p "$RESOLVED_DIR"
        log info "已自动创建用户隔离物理目录: $RESOLVED_DIR"
    else
        log info "检测到已有物理目录: $RESOLVED_DIR (保留原始文件属性与权限，兼容 Samba)"
    fi

    pause_service_if_running
    trap resume_service_if_was_running RETURN

    local user_added=false
    local curr_pass="$password"

    while [ "$user_added" = false ]; do
        if [ -z "$curr_pass" ]; then
            while true; do
                read -r -s -p "请输入 [$username] 的登录密码 [建议大小写字母+数字/特殊字符]: " curr_pass
                echo ""
                if [ -z "$curr_pass" ]; then
                    echo "密码不能为空！"
                    continue
                fi
                read -r -s -p "请再次确认密码: " password_confirm
                echo ""
                if [ "$curr_pass" != "$password_confirm" ]; then
                    echo "两次输入的密码不一致，请重试！"
                else
                    break
                fi
            done
        fi

        local err_output
        if "$INSTALL_BIN" users ls -d "$DB_FILE" 2>/dev/null | grep -qw "$username"; then
            log warn "用户 [$username] 已存在，正在更新其密码与 Scope 隔离路径..."
            err_output=$("$INSTALL_BIN" users update "$username" \
                --password "$curr_pass" \
                --scope "$RESOLVED_SCOPE" \
                --database "$DB_FILE" 2>&1 || true)
        else
            err_output=$("$INSTALL_BIN" users add "$username" "$curr_pass" \
                --scope "$RESOLVED_SCOPE" \
                --locale "zh-cn" \
                --perm.create=true \
                --perm.delete=true \
                --perm.download=true \
                --perm.modify=true \
                --perm.share=true \
                --perm.admin=false \
                --database "$DB_FILE" 2>&1 || true)
        fi

        if [[ "$err_output" == *"Error:"* ]]; then
            log warn "创建/更新用户 [$username] 失败: $err_output"
            if [[ "$err_output" == *"timeout"* ]]; then
                log warn "原因: 数据库文件 ($DB_FILE) 锁获取超时，请检查是否有其他 FileBrowser 进程占用。"
            elif [[ "$err_output" == *"password is too easy"* || "$err_output" == *"password is too short"* ]]; then
                log warn "原因: 密码安全策略拦截 (密码过于简单)，请包含大小写字母、数字或特殊字符。"
            fi
            if [ -t 0 ]; then
                curr_pass=""
            else
                log error "非交互模式下操作失败，终止执行。"
            fi
        else
            user_added=true
        fi
    done

    log info "✅ 用户 [$username] 配置成功！"
    log info "   • 实际物理存储目录: $RESOLVED_DIR"
    log info "   • FileBrowser Scope: $RESOLVED_SCOPE (登录后以此目录为根目录，隔离且完整可见该目录下文件)"
}

# 列出所有用户
function do_lsusers {
    load_runtime_config
    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi
    pause_service_if_running
    trap resume_service_if_was_running RETURN

    echo "========================================================"
    echo "            FileBrowser 用户列表                        "
    echo "            数据库: $DB_FILE                            "
    echo "========================================================"
    "$INSTALL_BIN" users ls -d "$DB_FILE"
    echo "========================================================"
}

# 删除用户
function do_deluser {
    load_runtime_config
    local username="$1"
    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi

    if [ -z "$username" ]; then
        read -r -p "请输入要删除的用户名: " username
    fi

    if [ "$username" = "admin" ]; then
        log error "不能删除默认管理员账户 admin！"
    fi

    pause_service_if_running
    trap resume_service_if_was_running RETURN

    local err_output
    err_output=$("$INSTALL_BIN" users rm "$username" -d "$DB_FILE" 2>&1 || true)
    if [[ "$err_output" == *"Error:"* ]]; then
        log error "删除用户 [$username] 失败: $err_output"
    else
        log info "用户 [$username] 已从 FileBrowser 数据库中移除。"
    fi
}

# 重置密码
function do_setpasswd {
    load_runtime_config
    local target_user="${1:-admin}"
    local new_pass="$2"

    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi

    pause_service_if_running
    trap resume_service_if_was_running RETURN

    local pwd_updated=false
    local curr_pass="$new_pass"

    while [ "$pwd_updated" = false ]; do
        if [ -z "$curr_pass" ]; then
            while true; do
                read -r -s -p "请输入用户 [$target_user] 的新密码: " curr_pass
                echo ""
                if [ -z "$curr_pass" ]; then
                    echo "密码不能为空！"
                    continue
                fi
                read -r -s -p "请再次确认新密码: " new_pass_confirm
                echo ""
                if [ "$curr_pass" != "$new_pass_confirm" ]; then
                    echo "两次输入的密码不一致，请重试！"
                else
                    break
                fi
            done
        fi

        local err_output
        err_output=$("$INSTALL_BIN" users update "$target_user" -p "$curr_pass" -d "$DB_FILE" 2>&1 || true)
        if [[ "$err_output" == *"Error:"* ]]; then
            log warn "密码修改失败: $err_output"
            if [[ "$err_output" == *"timeout"* ]]; then
                log warn "原因: 数据库文件 ($DB_FILE) 锁获取超时，请检查是否有其他 FileBrowser 进程占用。"
            elif [[ "$err_output" == *"password is too easy"* || "$err_output" == *"password is too short"* ]]; then
                log warn "原因: 密码安全策略拦截 (密码过于简单)，请包含大小写字母、数字或特殊字符。"
            fi
            if [ -t 0 ]; then
                curr_pass=""
            else
                log error "非交互模式下新密码不符合策略，操作终止。"
            fi
        else
            pwd_updated=true
        fi
    done

    log info "用户 [$target_user] 密码修改成功！"
}

# 修改监听端口
function do_setport {
    load_runtime_config
    local new_port="$1"

    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi

    if [ -z "$new_port" ]; then
        read -r -p "请输入新的监听端口 [1-65535]: " new_port
    fi

    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        log error "无效的端口号: $new_port"
    fi

    pause_service_if_running
    trap resume_service_if_was_running RETURN

    "$INSTALL_BIN" config set -p "$new_port" -d "$DB_FILE" >> "$logfile" 2>&1
    save_runtime_config "${ROOT_DIR:-/data}" "$new_port" "$DB_FILE"
    configure_firewall "$new_port"
    service_control restart
    log info "端口已修改为 $new_port 并已重启服务！"
}

# 安装流程汇总
function do_install {
    load_runtime_config
    local input_root_dir="$1"
    local input_port="$2"
    local input_admin_pass="$3"
    local input_db_path="$4"

    echo ""
    echo "========================================================"
    echo "            FileBrowser 自动化安装向导                  "
    echo "========================================================"
    echo ""

    if [ -n "$input_root_dir" ]; then
        ROOT_DIR="$input_root_dir"
    else
        read -r -p "请输入 Web 全局文件根目录 [默认: /data, 回车确认]: " ROOT_DIR
        ROOT_DIR="${ROOT_DIR:-/data}"
    fi

    if [ -n "$input_port" ]; then
        PORT="$input_port"
    else
        read -r -p "请输入 Web 访问端口 [默认: 8080]: " PORT
        PORT="${PORT:-8080}"
    fi

    if [ -n "$input_admin_pass" ]; then
        ADMIN_PASS="$input_admin_pass"
    else
        while true; do
            read -r -s -p "请输入管理员 (admin) 的登录密码 [默认: Admin@123456]: " ADMIN_PASS
            echo ""
            ADMIN_PASS="${ADMIN_PASS:-Admin@123456}"
            if [ "$ADMIN_PASS" = "Admin@123456" ]; then
                log warn "您使用了默认推荐密码 'Admin@123456'，上线后可在控制台按需修改！"
                break
            fi
            read -r -s -p "请再次确认密码: " ADMIN_PASS_CONFIRM
            echo ""
            if [ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]; then
                echo "两次输入的密码不一致，请重新输入！"
            else
                break
            fi
        done
    fi

    if [ -n "$input_db_path" ]; then
        DB_FILE="$input_db_path"
    else
        read -r -p "请输入数据库存储路径 [默认: /etc/filebrowser/filebrowser.db, 回车确认]: " input_custom_db
        DB_FILE="${input_custom_db:-/etc/filebrowser/filebrowser.db}"
    fi

    log info "配置参数确认:"
    log info "  全局根目录: $ROOT_DIR (管理员可俯瞰全部，普通用户通过 Scope 隔离)"
    log info "  监听端口:   $PORT"
    log info "  数据库路径: $DB_FILE"
    log info "  默认管理员: admin"

    prompt_server_host
    install_dependencies
    download_filebrowser
    init_filebrowser_config "$ROOT_DIR" "$PORT" "$ADMIN_PASS" "$DB_FILE"
    configure_firewall "$PORT"
    register_service
    get_server_host

    local s_mgr
    s_mgr="$(detect_service_manager)"

    echo ""
    echo -e "\033[32m========================================================\033[0m"
    echo -e "\033[32m          FileBrowser Web 文件管理器部署成功！          \033[0m"
    echo -e "\033[32m========================================================\033[0m"
    echo -e "Web 访问地址:  \033[36mhttp://${SERVER_HOST}:${PORT}\033[0m"
    echo -e "超级管理员:    \033[36madmin\033[0m"
    echo -e "管理员密码:    \033[36m${ADMIN_PASS}\033[0m"
    echo -e "全局数据根目录:\033[36m${ROOT_DIR}\033[0m"
    echo -e "数据库文件:    \033[36m${DB_FILE}\033[0m"
    if [ "$s_mgr" = "systemd" ]; then
        echo -e "服务托管模式:  \033[36msystemd (systemctl status filebrowser)\033[0m"
    else
        echo -e "服务托管模式:  \033[36mSysVinit (service filebrowser status)\033[0m"
    fi
    echo "--------------------------------------------------------"
    echo "👥 添加隔离普通用户:"
    echo "    执行: sudo ./filebrowser_install.sh adduser <用户名> <密码> [隔离目录]"
    echo "    (支持与 Samba 隔离目录 /data/users/<用户名> 协同)"
    echo "========================================================"
    echo ""
}

# 卸载流程
function do_uninstall {
    load_runtime_config
    echo ""
    echo "========================================================"
    echo "            FileBrowser 卸载向导                        "
    echo "========================================================"
    echo ""

    read -r -p "确定要彻底卸载 FileBrowser 吗？此操作将注销服务并清理配置 (y/N): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        log info "用户取消卸载操作。"
        exit 0
    fi

    unregister_service

    log info "正在删除二进制文件与配置..."
    rm -f "$INSTALL_BIN"

    read -r -p "是否删除数据库文件 ($DB_FILE) 与配置目录 ($CONFIG_DIR)? [y/N]: " clean_conf
    if [[ "$clean_conf" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -f "$DB_FILE"
        rm -f "$LOG_PATH"
        rm -f "$HOST_RECORD_FILE"
        log info "已清理数据库文件、/etc/filebrowser 及运行日志。"
    else
        log info "已保留数据库文件与配置文件。"
    fi

    log info "注意: 您的实际文件数据目录未被删除以防数据丢失。"
    log info "FileBrowser 卸载完成！"
}

# 主菜单入口
function main_menu {
    load_runtime_config
    while true; do
        echo ""
        echo "========================================================"
        echo "       FileBrowser 一键管理脚本 (带多用户隔离)          "
        echo "========================================================"
        echo " 1. 安装并配置 FileBrowser (Install)"
        echo " 2. 单独注册系统服务并开启自启 (Service Register)"
        echo " 3. 注销系统服务 (Service Unregister)"
        echo " 4. 查看运行状态 (Status)"
        echo " 5. 启动服务 (Start)"
        echo " 6. 停止服务 (Stop)"
        echo " 7. 重启服务 (Restart)"
        echo " 8. 添加新用户 (指定独立隔离目录 Scope)"
        echo " 9. 查看所有用户列表 (List Users)"
        echo " 10. 删除用户 (Delete User)"
        echo " 11. 重置用户密码 (Set Password)"
        echo " 12. 修改监听端口 (Set Port)"
        echo " 13. 修改 Web 访问 IP / 域名 (当前: \033[36m${SERVER_HOST}\033[0m)"
        echo " 14. 完全卸载 FileBrowser (Uninstall)"
        echo " 0. 退出 (Exit)"
        echo "========================================================"
        read -r -p "请输入选项 [0-14]: " choice

        case "$choice" in
            1)
                do_install
                ;;
            2)
                register_service
                ;;
            3)
                unregister_service
                ;;
            4)
                service_control status
                ;;
            5)
                service_control start
                ;;
            6)
                service_control stop
                ;;
            7)
                service_control restart
                ;;
            8)
                do_adduser
                ;;
            9)
                do_lsusers
                ;;
            10)
                do_deluser
                ;;
            11)
                do_setpasswd
                ;;
            12)
                do_setport
                ;;
            13)
                echo -n "当前 Web 访问目标地址为 [${SERVER_HOST}]，按回车直接使用，或输入新IP/域名: "
                read -r new_h
                if [ -n "$new_h" ]; then
                    SERVER_HOST="$new_h"
                    save_server_host "$SERVER_HOST"
                    log info "Web 访问地址已成功更新为: $SERVER_HOST"
                fi
                ;;
            14)
                do_uninstall
                ;;
            0)
                echo "已退出。"
                exit 0
                ;;
            *)
                echo "无效输入，请输入 0-13。"
                ;;
        esac
    done
}

# ==============================================================================
# 脚本入口
# ==============================================================================
check_permission
get_original_user
detect_system
load_runtime_config

# 解析全局选项 (例如 --host 指定 IP / 域名)
POSITIONAL_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -H|--host)
            CUSTOM_HOST="$2"
            save_server_host "$CUSTOM_HOST"
            shift 2
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL_ARGS[@]}"

ACTION="${1:-}"

case "$ACTION" in
    install|-i|--install)
        do_install "$2" "$3" "$4" "$5"
        ;;
    uninstall|-u|--uninstall)
        do_uninstall
        ;;
    service)
        case "${2:-register}" in
            register|enable)
                register_service
                ;;
            unregister|disable)
                unregister_service
                ;;
            *)
                log error "未知服务命令: $2。支持 register | unregister"
                ;;
        esac
        ;;
    status|-s|--status)
        service_control status
        ;;
    start)
        service_control start
        ;;
    stop)
        service_control stop
        ;;
    restart)
        service_control restart
        ;;
    adduser|add-user)
        do_adduser "$2" "$3" "$4"
        ;;
    lsusers|ls-users|users)
        do_lsusers
        ;;
    deluser|del-user)
        do_deluser "$2"
        ;;
    setpasswd|passwd)
        do_setpasswd "$2" "$3"
        ;;
    setport|port)
        do_setport "$2"
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0                                                 # 交互式菜单"
        echo "  sudo $0 install [全局目录] [端口] [管理员密码] [DB路径]   # 完整安装与注册"
        echo "  sudo $0 adduser [用户名] [密码] [隔离目录]                # 添加隔离用户"
        echo "  sudo $0 lsusers                                         # 查看所有用户"
        echo "  sudo $0 deluser [用户名]                                 # 删除用户"
        echo "  sudo $0 service register                                # 仅注册系统服务"
        echo "  sudo $0 service unregister                              # 注销系统服务"
        echo "  sudo $0 start|stop|restart|status                       # 服务启停状态"
        echo "  sudo $0 setpasswd [用户名] [新密码]                       # 重置密码"
        echo "  sudo $0 setport [新端口号]                               # 修改 Web 端口"
        echo "  sudo $0 uninstall                                       # 卸载 FileBrowser"
        ;;
    "")
        main_menu
        ;;
    *)
        log error "未知命令: $ACTION。使用 '$0 help' 查看帮助。"
        ;;
esac

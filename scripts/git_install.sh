#!/bin/bash
#
# 自动下载并编译安装 Git
# 用法：sudo ./git_install.sh [version]

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"

logfile=$SCRIPT_ROOT/init.log

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

if [ -z "$1" ]; then
  git_version="2.42.0"
  log info "未指定版本，使用默认版本: $git_version"
else
  git_version="$1"
  log info "使用指定版本: $git_version"
fi

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

# 系统与架构检测
UNAME_S=$(uname -s)
ARCH=$(uname -m)

if [ "$UNAME_S" = "Darwin" ]; then
    OS="darwin"
    VERSION=$(sw_vers -productVersion 2>/dev/null || uname -r)
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    OS="unknown"
    VERSION=$(uname -r)
fi

log info "检测到系统架构: $ARCH"
log info "检测到操作系统: $OS $VERSION"

# 判断是否安装过git，如果有再确认是否卸载原安装的git
if command -v git >/dev/null 2>&1; then
    cur_gitversion=$(git --version 2>&1 | sed '1!d' | sed -e 's/"//g' | awk '{print $3}')
    log info "当前git版本为$cur_gitversion"
    if [ "$cur_gitversion" = "$git_version" ]; then
        log info "已安装的版本和将要安装的版本相同 ($git_version), 不进行安装"
        exit 0
    else
        log info "已安装的版本 ($cur_gitversion) 和将要安装的版本 ($git_version) 不同"
        if [ -t 0 ]; then
            read -p "是否删除已安装的git $cur_gitversion？(y/n): " is_del_git
            if [ "$is_del_git" = "y" ]; then
                case $OS in
                    'rhel'|'centos'|'fedora'|'rocky'|'almalinux')
                        yum remove git -y || dnf remove git -y
                        ;;
                    'ubuntu'|'debian')
                        apt remove git -y
                        ;;
                    'darwin')
                        log warn "macOS 自带或 brew 安装的 git，建议保留或通过 brew uninstall git 卸载"
                        ;;
                    *)
                        log warn "未知系统类型，请手动卸载git"
                        ;;
                esac
            fi
        fi
    fi
fi

# 安装编译依赖
install_dependencies() {
    log info "正在安装Git编译依赖..."

    case $OS in
        'rhel'|'centos'|'fedora'|'rocky'|'almalinux')
            if command -v dnf >/dev/null 2>&1; then
                dnf update -y
                dnf groupinstall -y "Development Tools"
                dnf install -y curl-devel expat-devel gettext-devel openssl-devel zlib-devel gcc perl-ExtUtils-MakeMaker git-lfs
            else
                yum update -y
                yum groupinstall -y "Development Tools"
                yum install -y epel-release.noarch && yum update -y && yum install -y curl-devel expat-devel gettext-devel openssl-devel zlib-devel gcc perl-ExtUtils-MakeMaker git-lfs.x86_64
            fi
            ;;
        'ubuntu'|'debian')
            apt update -y
            apt install -y build-essential libcurl4-openssl-dev libexpat1-dev gettext libssl-dev zlib1g-dev autoconf git-lfs
            ;;
        'darwin')
            if command -v brew >/dev/null 2>&1; then
                brew install curl expat gettext openssl zlib autoconf git-lfs || true
            else
                log warn "macOS 检测到未安装 Homebrew，若编译缺少依赖请先安装 Homebrew"
            fi
            ;;
        *)
            log warn "未知操作系统: $OS，尝试继续编译..."
            ;;
    esac

    log info "依赖包准备完成"
}

# 执行依赖安装
install_dependencies

# 选择下载镜像
select_mirror() {
    # 中国镜像站点
    CHINA_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/pub/software/scm/git"
    # 官方镜像
    OFFICIAL_MIRROR="https://mirrors.edge.kernel.org/pub/software/scm/git"

    # 检测网络连接，优先选择中国镜像
    if curl -s --connect-timeout 5 "$CHINA_MIRROR/" > /dev/null 2>&1; then
        MIRROR_URL="$CHINA_MIRROR"
        log info "使用清华大学镜像源"
    else
        MIRROR_URL="$OFFICIAL_MIRROR"
        log info "使用官方镜像源"
    fi
}

# 下载 Git 源码包
log info "正在下载 Git 源码包..."
select_mirror

download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --connect-timeout 30 --retry 3 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --timeout=30 --tries=3 -O "$dest" "$url"
    else
        return 1
    fi
}

if [ -f "/tmp/git-$git_version.tar.gz" ]; then
    log info "已存在 Git 源码包，跳过下载"
else
    log info "准备下载 Git $git_version 源码包..."
    cd /tmp || log error "无法切换到 /tmp 目录"
    download_file "$MIRROR_URL/git-$git_version.tar.gz" "/tmp/git-$git_version.tar.gz" || {
        log warn "从主镜像下载失败，尝试备用镜像..."
        if [ "$MIRROR_URL" != "$OFFICIAL_MIRROR" ]; then
            download_file "$OFFICIAL_MIRROR/git-$git_version.tar.gz" "/tmp/git-$git_version.tar.gz" || log error "所有镜像下载失败，请手动下载后重试"
        else
            log error "下载失败，请手动下载后重试，下载地址：$MIRROR_URL/git-$git_version.tar.gz"
        fi
    }
fi

# 解压 Git 源码包
log info "正在解压 Git 源码包..."
cd /tmp || log error "无法切换到 /tmp 目录"
rm -rf "git-$git_version" 2>/dev/null || true
tar -xzf "git-$git_version.tar.gz" || log error "解压失败"

# 编译安装 Git
log info "正在编译安装 Git..."
cd "/tmp/git-$git_version" || log error "无法进入源码目录"

NPROC=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)

# 配置编译选项
./configure \
    --prefix=/usr/local/git \
    --with-curl \
    --with-expat \
    --with-openssl \
    --with-perl \
    --with-zlib \
    --with-libpango \
    --enable-utf8 \
    CFLAGS="-O2" || log error "配置失败"

# 编译
make -j"$NPROC" || log error "编译失败"

# 安装
make install -j"$NPROC" || log error "安装失败"

# 复制自动补全脚本
if [ -f "/tmp/git-$git_version/contrib/completion/git-completion.bash" ]; then
    cp "/tmp/git-$git_version/contrib/completion/git-completion.bash" "$ORIGINAL_HOME/.git-completion.bash"
    chown "$ORIGINAL_USER:$ORIGINAL_GROUP" "$ORIGINAL_HOME/.git-completion.bash" 2>/dev/null || chown "$ORIGINAL_USER" "$ORIGINAL_HOME/.git-completion.bash" 2>/dev/null || true
fi

# 配置环境变量函数
configure_git_env() {
    local user_home="$1"
    local targets=()

    [ -f "$user_home/.bashrc" ] && targets+=("$user_home/.bashrc")
    [ -f "$user_home/.zshrc" ] && targets+=("$user_home/.zshrc")
    [ -f "$user_home/.bash_profile" ] && targets+=("$user_home/.bash_profile")
    [ -f "$user_home/.zprofile" ] && targets+=("$user_home/.zprofile")

    if [ ${#targets[@]} -eq 0 ]; then
        if [ "$UNAME_S" = "Darwin" ]; then
            targets=("$user_home/.zshrc")
        else
            targets=("$user_home/.bashrc")
        fi
    fi

    for target_file in "${targets[@]}"; do
        if grep -q "# Set PATH to include Git" "$target_file" 2>/dev/null; then
            log warn "$target_file 已包含 Git 环境变量配置，请检查配置是否正确"
        else
            cat << 'EOF' >> "$target_file"

# Set PATH to include Git
export PATH=/usr/local/git/bin:$PATH
# Load Git auto-completion
if [ -f ~/.git-completion.bash ]; then
    . ~/.git-completion.bash
fi
EOF
            log info "已添加 Git 环境变量配置到 $target_file"
        fi
    done
}

# 为当前用户配置环境变量
configure_git_env "$HOME"

# 如果使用sudo执行，也为原始用户配置环境变量
if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
    log info "为原始用户 $ORIGINAL_USER 配置环境变量..."
    configure_git_env "$ORIGINAL_HOME"
fi

# 创建软链接到系统路径（可选）
if [ -d "/usr/local/git/bin" ]; then
    mkdir -p /usr/local/bin 2>/dev/null || true
    if [ -w "/usr/local/bin" ]; then
        ln -sf /usr/local/git/bin/git /usr/local/bin/git
        log info "已创建 git 软链接到 /usr/local/bin/git"
    elif [ -w "/usr/bin" ]; then
        ln -sf /usr/local/git/bin/git /usr/bin/git
        log info "已创建 git 软链接到 /usr/bin/git"
    fi
fi

# 验证安装
log info "正在验证 Git 安装..."
if [ -f "/usr/local/git/bin/git" ]; then
    export PATH="/usr/local/git/bin:$PATH"
    installed_version=$(git --version 2>&1 | awk '{print $3}')
    if [ "$installed_version" = "$git_version" ]; then
        log info "Git 版本验证成功: $installed_version"

        # 配置 Git 全局设置
        log info "正在配置 Git 全局设置..."

        # 为原始用户配置Git设置
        if [ "$ORIGINAL_USER" != "$USER" ]; then
            sudo -u "$ORIGINAL_USER" git config --global credential.helper store
            sudo -u "$ORIGINAL_USER" git config --global core.longpaths true
            sudo -u "$ORIGINAL_USER" git config --global core.quotepath off
            log info "已为用户 $ORIGINAL_USER 配置 Git 全局设置"
        else
            git config --global credential.helper store
            git config --global core.longpaths true
            git config --global core.quotepath off
            command -v git-lfs >/dev/null 2>&1 && git lfs install --skip-repo 2>/dev/null || true
            log info "已配置 Git 全局设置"
        fi

        log info "Git 安装成功！版本: $(git --version)"
        if [ "$UNAME_S" = "Darwin" ]; then
            log info "请执行 'source ~/.zshrc' (或 ~/.bashrc) 加载环境变量"
        else
            log info "请执行 'source ~/.bashrc' 或重新登录以加载环境变量"
        fi
        if [ "$ORIGINAL_USER" != "$USER" ]; then
            log info "原始用户 $ORIGINAL_USER 的环境变量已配置，请重新登录以生效"
        fi
    else
        log error "Git 版本不匹配，期望: $git_version，实际: $installed_version"
    fi
else
    log error "Git 二进制文件未找到: /usr/local/git/bin/git，安装可能失败"
fi

# 清理临时文件
log info "正在清理临时文件..."
rm -rf "/tmp/git-$git_version"
rm -f "/tmp/git-$git_version.tar.gz"
log info "临时文件清理完成"
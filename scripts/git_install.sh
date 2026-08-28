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
    # 非root用户，检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        log error "当前用户没有sudo权限，请以root用户或使用sudo命令执行此脚本"
    else
        log info "检测到非root用户但有sudo权限，继续执行..."
    fi
else
    log info "检测到root用户执行，继续执行..."
fi

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

# 卸载 Git 函数
function do_uninstall {
    log info "开始卸载编译安装的 Git..."

    if [ -d "/usr/local/git" ]; then
        rm -rf /usr/local/git
        log info "已删除 /usr/local/git"
    fi

    if [ -L "/usr/bin/git" ]; then
        local link_target
        link_target=$(readlink /usr/bin/git || true)
        if [[ "$link_target" == *"/usr/local/git"* ]]; then
            rm -f /usr/bin/git
            log info "已删除 /usr/bin/git 软链接"
        fi
    fi

    # 清理补全脚本
    rm -f "$ORIGINAL_HOME/.git-completion.bash" "$HOME/.git-completion.bash"

    # 清理 .bashrc 中的配置
    cleanup_git_bashrc() {
        local user_home="$1"
        local user_bashrc="$user_home/.bashrc"
        if [ -f "$user_bashrc" ] && grep -q "# Set PATH to include Git" "$user_bashrc"; then
            sed -i.bak '/# Set PATH to include Git/,/fi/d' "$user_bashrc" 2>/dev/null || true
            rm -f "$user_bashrc.bak"
            log info "已清理 $user_bashrc 中的 Git 环境变量"
        fi
    }

    cleanup_git_bashrc "$HOME"
    if [ "$ORIGINAL_USER" != "$USER" ] && [ "$ORIGINAL_HOME" != "$HOME" ]; then
        cleanup_git_bashrc "$ORIGINAL_HOME"
    fi

    log info "Git 卸载清理完成！请执行 'source ~/.bashrc'。"
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
        echo "  sudo $0 [版本号]     # 编译安装指定版本 Git (默认: 2.42.0)"
        echo "  sudo $0 uninstall    # 卸载编译安装的 Git 并清理环境变量"
        exit 0
        ;;
esac

if [ -z "$1" ]; then
  git_version="2.42.0"
  log info "未指定版本，使用默认版本: $git_version"
else
  git_version="$1"
  log info "使用指定版本: $git_version"
fi

# 判断是否安装过git，如果有再确认是否卸载原安装的git
if [ `command  -v git` ];then
    cur_gitversion=`git --version 2>&1 | sed '1!d' | sed -e 's/"//g' | awk '{print $3}'`
    log info "当前git版本为$cur_gitversion"
    if [[ $cur_gitversion == $git_version  ]];then
        log info "已安装的版本和将要安装的版本相同,不进行安装"
        exit 0
    else
        log info "已安装的版本和将要安装的版本不同"
        read -p "是否删除已安装的git$cur_gitversion？(y/n):" is_del_git

        if [[ $is_del_git == 'y' ]];then
            # 获取系统版本信息（用于卸载）
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS=$ID
            else
                OS="unknown"
            fi

            case $OS in
                'rhel'|'centos'|'fedora'|'rocky'|'almalinux')
                    yum remove git -y || dnf remove git -y
                    ;;
                'ubuntu'|'debian')
                    apt remove git -y
                    ;;
                *)
                    log warn "未知系统类型，请手动卸载git"
                    ;;
            esac
        fi
    fi
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
    exit 1
fi

# 打印系统信息
log info "检测到系统架构: $ARCH"
log info "检测到操作系统: $OS $VERSION"

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
        *)
            log error "不支持的操作系统: $OS，请手动安装依赖包"
            exit 1
            ;;
    esac

    log info "依赖包安装完成"
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

if [ -f "/tmp/git-$git_version.tar.gz" ]; then
    log info "已存在 Git 源码包，跳过下载"
else
    log info "准备下载 Git $git_version 源码包..."
    cd /tmp || log error "无法切换到 /tmp 目录"
    wget --timeout=30 --tries=3 "$MIRROR_URL/git-$git_version.tar.gz" || {
        log warn "从主镜像下载失败，尝试备用镜像..."
        if [ "$MIRROR_URL" != "$OFFICIAL_MIRROR" ]; then
            wget --timeout=30 --tries=3 "$OFFICIAL_MIRROR/git-$git_version.tar.gz" || log error "所有镜像下载失败，请手动下载后重试"
        else
            log error "下载失败，请手动下载后重试，下载地址：$MIRROR_URL/git-$git_version.tar.gz"
        fi
    }
fi

# 解压 Git 源码包
log info "正在解压 Git 源码包..."
cd /tmp || log error "无法切换到 /tmp 目录"
tar -xzf "git-$git_version.tar.gz" || log error "解压失败"

# 编译安装 Git
log info "正在编译安装 Git..."
cd "/tmp/git-$git_version" || log error "无法进入源码目录"

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
make -j$(nproc) || log error "编译失败"

# 安装
make install -j$(nproc) || log error "安装失败"

# 复制自动补全脚本
cp "/tmp/git-$git_version/contrib/completion/git-completion.bash" "$ORIGINAL_HOME/.git-completion.bash"
chown "$ORIGINAL_USER:$ORIGINAL_USER" "$ORIGINAL_HOME/.git-completion.bash" 2>/dev/null || true

# 配置环境变量函数
configure_git_env() {
    local user_home="$1"
    local user_bashrc="$user_home/.bashrc"

    if grep -q "# Set PATH to include Git" "$user_bashrc" 2>/dev/null; then
        log warn "$user_bashrc 已包含 Git 环境变量配置，请检查配置是否正确"
        return 0
    else
        cat << EOF >> "$user_bashrc"

# Set PATH to include Git
export PATH=\$PATH:/usr/local/git/bin
# Load Git auto-completion
if [ -f ~/.git-completion.bash ]; then
    . ~/.git-completion.bash
fi
EOF
        log info "已添加 Git 环境变量配置到 $user_bashrc"
        return 0
    fi
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
    if [ -w "/usr/bin" ]; then
        ln -sf /usr/local/git/bin/git /usr/bin/git
        log info "已创建 git 软链接到 /usr/bin/git"
    else
        log info "没有 /usr/bin 写权限，请手动将 /usr/local/git/bin 添加到 PATH"
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
            git lfs install --skip-repo
            log info "已配置 Git 全局设置"
        fi

        log info "Git 安装成功！版本: $(git --version)"
        log info "请执行 'source ~/.bashrc' 或重新登录以加载环境变量"
        if [ "$ORIGINAL_USER" != "$USER" ]; then
            log info "原始用户 $ORIGINAL_USER 的环境变量已配置，请重新登录以生效"
        fi

        # 安装 Git LFS（可选）
        if command -v git-lfs >/dev/null 2>&1; then
            log info "Git LFS 已安装"
        else
            log info "建议安装 Git LFS 以支持大文件："
            case $OS in
                'rhel'|'centos'|'fedora'|'rocky'|'almalinux')
                    echo "dnf install git-lfs 或 yum install git-lfs"
                    ;;
                'ubuntu'|'debian')
                    echo "apt install git-lfs"
                    ;;
            esac
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
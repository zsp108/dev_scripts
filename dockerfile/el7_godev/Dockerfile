FROM centos:7

# 设置维护者信息
LABEL maintainer="zsp108"
LABEL description="CentOS 7 with Go and Git development environment"

# 修复 CentOS 7 镜像源
RUN mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup && \
curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo && \
sed -i -e '/mirrors.cloud.aliyuncs.com/d' -e '/mirrors.aliyuncs.com/d' /etc/yum.repos.d/CentOS-Base.repo && \
yum makecache

# 更新系统并安装基础工具
RUN yum update -y && \
    yum install -y \
    wget \
    curl \
    tar \
    gcc \
    make \
    perl-ExtUtils-MakeMaker \
    curl-devel \
    expat-devel \
    gettext-devel \
    openssl-devel \
    zlib-devel \
    && yum clean all

# 创建工作目录
WORKDIR /opt/scripts

# 复制安装脚本
COPY scripts/go_install.sh /opt/scripts/
COPY scripts/git_install.sh /opt/scripts/
COPY scripts/gitlint_install.sh /opt/scripts/
COPY packages/git*.tar.gz /tmp/
COPY packages/go*.tar.gz /tmp/

# 设置脚本执行权限
RUN chmod +x /opt/scripts/go_install.sh /opt/scripts/git_install.sh /opt/scripts/gitlint_install.sh

# 执行 Git 安装脚本（使用默认版本）
# 预先卸载系统自带的 git，避免交互确认
ARG GIT_VERSION
RUN yum remove -y git || true && \
    echo "y" | /opt/scripts/git_install.sh ${GIT_VERSION}

# 执行 Go 安装脚本（指定版本）
ARG GO_VERSION
RUN /opt/scripts/go_install.sh ${GO_VERSION} 

# 执行 gitlint 安装脚本
# RUN source ~/.bashrc && /opt/scripts/gitlint_install.sh


# 创建工作空间
RUN mkdir -p /root/workspace 

# 设置默认工作目录
WORKDIR /root/workspace

# 设置默认命令
CMD ["/bin/bash"]

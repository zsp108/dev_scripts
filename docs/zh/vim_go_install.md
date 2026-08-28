# vim_go_install.sh 使用说明

## 脚本简介
Vim-go 是经典的 Vim 环境下 Go 语言开发神器。此脚本负责克隆 vim-go 插件代码，并且自动注入相关的 `.vimrc` 配置，为终端重度使用者快速搭建顺滑的 Go 编码环境。

## 使用示例

### 1. 默认安装
安装 vim-go 到系统，默认使用最新 master 代码：
```bash
./scripts/vim_go_install.sh
```

### 2. 安装指定版本分支或 Tag
```bash
./scripts/vim_go_install.sh v1.28
```

### 3. 卸载配置
自动移除由该脚本添加的 vim 插件与配置文件变更：
```bash
./scripts/vim_go_install.sh uninstall
```


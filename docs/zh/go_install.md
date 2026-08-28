# go_install.sh 使用说明

## 脚本简介
自动下载、配置并安装 Golang 语言环境，配置全局 GOPATH 和 GOROOT，极大简化 Go 环境的搭建流程。

## 使用示例

### 1. 自动安装默认推荐版本
一键配置好 Go 环境：
```bash
sudo ./scripts/go_install.sh
```

### 2. 安装指定版本的 Go
若老项目依赖特定版本的 Go 编译器（如 1.20.1）：
```bash
sudo ./scripts/go_install.sh 1.20.1
```

### 3. 查看可用版本列表
```bash
./scripts/go_install.sh list
```

### 4. 卸载 Go 环境
清除环境和二进制文件：
```bash
sudo ./scripts/go_install.sh uninstall
```


# protobuf_install.sh 使用说明

## 脚本简介
自动下载、解压并安装 Google Protobuf 编译器 (`protoc`)，以及为 Golang 准备的代码生成插件 (`protoc-gen-go` / `protoc-gen-go-grpc`)。专为微服务和 gRPC 开发者设计。

## 使用示例

### 1. 默认参数一键安装
如果不带参数，脚本将安装内置推荐版本的 protoc 及相关的 go 插件：
```bash
./scripts/protobuf_install.sh
```

### 2. 安装指定的版本组合
您可以明确指定 `protoc` 的版本和 `protoc-gen-go` 的版本：
```bash
# 格式: ./protobuf_install.sh [protoc_version] [protoc_gen_go_version]
./scripts/protobuf_install.sh 24.3 v1.31.0
```

### 3. 列出常用版本
```bash
./scripts/protobuf_install.sh list
```

### 4. 卸载
```bash
./scripts/protobuf_install.sh uninstall
```


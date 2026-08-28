# protobuf_install.sh Usage Guide

## Introduction
Automatically downloads, extracts, and installs the Google Protobuf compiler (`protoc`), along with the code generation plugins for Golang (`protoc-gen-go` / `protoc-gen-go-grpc`). Designed specifically for microservices and gRPC developers.

## Usage Examples

### 1. One-click Default Installation
If no arguments are provided, the script installs the built-in recommended version of protoc and related go plugins:
```bash
./scripts/protobuf_install.sh
```

### 2. Install Specific Version Combinations
You can explicitly define the versions for `protoc` and `protoc-gen-go`:
```bash
# Format: ./protobuf_install.sh [protoc_version] [protoc_gen_go_version]
./scripts/protobuf_install.sh 24.3 v1.31.0
```

### 3. List Common Versions
```bash
./scripts/protobuf_install.sh list
```

### 4. Uninstall
```bash
./scripts/protobuf_install.sh uninstall
```


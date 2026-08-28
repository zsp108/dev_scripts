# gitlint_install.sh 使用说明

## 脚本简介
团队协作中规范的 Git Commit Message 极其重要。该脚本将自动安装 `gitlint` 工具，并配置相关的预检查（Pre-commit/Commit-msg Hook），确保所有提交信息严格遵循社区常用的规范体系。

## 使用示例

### 1. 一键安装并配置
```bash
./scripts/gitlint_install.sh
```
执行完毕后，您可以配合 Makefile 执行诸如 `make pre-commit` 钩子绑定。

### 2. 卸载
```bash
./scripts/gitlint_install.sh uninstall
```


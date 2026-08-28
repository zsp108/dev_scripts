# codex_switch.sh 使用说明

## 脚本简介
开发环境中常常需要频繁在多个 Codex 账号或环境配置间切换。本工具将配置抽象为不同“组件”，实现了在 `auth.json` 与 `config.toml` 等多重状态间的无缝备份与一键切换。

## 使用示例

### 1. 备份当前配置
在操作配置前，安全保存当前状态：
```bash
./scripts/tools/codex_switch.sh config backup
./scripts/tools/codex_switch.sh auth backup
```

### 2. 切换至特定的账号/配置文件
假设你有一个名为 `prod` 的备份配置 (`config_prod.toml`)：
```bash
./scripts/tools/codex_switch.sh config switch prod
```

### 3. 查看当前正在使用哪个配置的凭证
```bash
./scripts/tools/codex_switch.sh auth status
```


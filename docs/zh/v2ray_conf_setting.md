# v2ray_conf_setting.sh 使用说明

## 脚本简介
V2Ray 客户端配置文件（JSON）往往结构复杂，容易出错。此工具提供了一个基于命令行的问答式交互引导，能够帮助您快速、无错地生成合规的 V2Ray Client 代理配置文件。

## 使用示例

进入该工具的交互生成引导：
```bash
./scripts/tools/v2ray_conf_setting.sh
```
根据终端提示，依次输入您的入站端口、节点地址、UUID、额外 ID 等关键信息，脚本结束后会在当前目录生成一份名为 `config.json` 的标准配置文件。


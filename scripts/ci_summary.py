#!/usr/bin/env python3
import os
import sys

lint_res = os.environ.get("LINT_RES", "unknown")
matrix_res = os.environ.get("MATRIX_RES", "unknown")
centos_res = os.environ.get("CENTOS_RES", "unknown")
lifecycle_res = os.environ.get("LIFECYCLE_RES", "unknown")

def badge(s):
    if s == "success":
        return "✅ Passed"
    elif s == "skipped":
        return "⚪ Skipped"
    else:
        return "❌ Failed"

passed = (lint_res == "success" and matrix_res == "success" and centos_res == "success" and lifecycle_res == "success")
overall = "✅ ALL CHECKS PASSED (全部通过)" if passed else "❌ SOME CHECKS FAILED (部分检查未通过)"

branch = os.environ.get("GITHUB_REF_NAME", "develop")
commit = os.environ.get("GITHUB_SHA", "")[:7]

lines = [
    "# 🚀 Dev Scripts CI 全矩阵测试汇总报告\n\n",
    f"> **分支 (Branch)**: `{branch}` | **提交 (Commit)**: `{commit}`  \n",
    f"> **整体执行状态**: **{overall}**\n\n---\n\n",
    "### 📋 测试阶段与架构矩阵详情\n\n",
    "| 测试阶段 (Job) | 目标架构与运行环境 | 状态 |\n",
    "| :--- | :--- | :---: |\n",
    f"| 🔍 **代码与语法自检** | `Ubuntu 24.04` (x86_64) | {badge(lint_res)} |\n",
    f"| 🐧 **Ubuntu 官方矩阵** | `Ubuntu 24.04` / `Ubuntu 22.04` (x86_64) | {badge(matrix_res)} |\n",
    f"| 🔴 **CentOS 7 跨架构矩阵** | `CentOS 7` (x86_64 & ARM64 Docker 容器) | {badge(centos_res)} |\n",
    f"| 🍎 **macOS Apple Silicon** | `macOS 14+` (Apple M-Series ARM64) | {badge(matrix_res)} |\n",
    f"| 🔄 **工具链生命周期闭环** | `Ubuntu 24.04` (x86_64) | {badge(lifecycle_res)} |\n\n---\n\n",
    "### 📦 覆盖的自动化运维与开发脚本 (共 16 个)\n",
    "- 🧰 **基础开发工具**: `go_install.sh`、`nodejs_install.sh`、`git_install.sh`、`protobuf_install.sh`、`vim_go_install.sh`、`gitlint_install.sh`、`env_init.sh`\n",
    "- 🌐 **服务与存储组件**: `filebrowser_install.sh`、`samba_install.sh`、`nginx_download_install.sh`、`derper_install.sh`\n",
    "- 🐳 **容器引擎**: `docker_install.sh`\n",
    "- ⚙️ **工具集**: `tools/codex_switch.sh`、`tools/scan_ip.sh`、`tools/scan_ip2.sh`、`tools/v2ray_conf_setting.sh`\n"
]

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    with open(summary_path, "a", encoding="utf-8") as sf:
        sf.writelines(lines)

print("".join(lines))

if not passed:
    print("CI 存在未通过的 Job，请检查详细日志。")
    sys.exit(1)

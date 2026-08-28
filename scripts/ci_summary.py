#!/usr/bin/env python3
import os
import sys

lint_res = os.environ.get("LINT_RES", "unknown")
macos_res = os.environ.get("MACOS_RES", "unknown")
linux_matrix_res = os.environ.get("LINUX_MATRIX_RES", "unknown")
lifecycle_res = os.environ.get("LIFECYCLE_RES", "unknown")

def badge(s):
    if s == "success":
        return "✅ Passed"
    elif s == "skipped":
        return "⚪ Skipped"
    else:
        return "❌ Failed"

passed = (lint_res == "success" and macos_res == "success" and linux_matrix_res == "success" and lifecycle_res == "success")
overall = "✅ ALL CHECKS PASSED (全矩阵 100% 通过)" if passed else "❌ SOME CHECKS FAILED (部分检查未通过)"

branch = os.environ.get("GITHUB_REF_NAME", "develop")
commit = os.environ.get("GITHUB_SHA", "")[:7]

lines = [
    "# 🚀 Dev Scripts CI 全主流系统与多架构测试汇总大报告

",
    f"> **分支 (Branch)**: `{branch}` | **提交 (Commit)**: `{commit}`  
",
    f"> **整体执行状态**: **{overall}**

---

",
    "### 📋 全主流系统与多架构测试矩阵详情

",
    "| 发行版与系统分类 | 目标架构覆盖 | 运行环境 / 方式 | 测试状态 |
",
    "| :--- | :--- | :--- | :---: |
",
    f"| 🔍 **代码与语法自检** | `x86_64` | Ubuntu 24.04 (Host) | {badge(lint_res)} |
",
    f"| 🐧 **Ubuntu 系列** | `x86_64` + `ARM64 (aarch64)` | Ubuntu 24.04 / 22.04 LTS 容器 | {badge(linux_matrix_res)} |
",
    f"| 🍥 **Debian 系列** | `x86_64` + `ARM64 (aarch64)` | Debian 12 (Bookworm) 容器 | {badge(linux_matrix_res)} |
",
    f"| 🎩 **RedHat / RHEL 9 & 8** | `x86_64` + `ARM64 (aarch64)` | RHEL / Rocky Linux 9 & 8 容器 | {badge(linux_matrix_res)} |
",
    f"| 🔴 **CentOS 8 & 7 系列** | `x86_64` + `ARM64 (aarch64)` | CentOS 8 & CentOS 7 容器 | {badge(linux_matrix_res)} |
",
    f"| 🍎 **macOS Apple Silicon** | `ARM64 (aarch64)` | macOS 14+ (Apple M 系列硬件) | {badge(macos_res)} |
",
    f"| 🔄 **工具链生命周期闭环** | `x86_64` | Go / Protobuf / Vim-go 安装 ➔ 验证 ➔ 卸载闭环 | {badge(lifecycle_res)} |

---

",
    "### 📦 覆盖的自动化运维与开发脚本 (共 16 个)
",
    "- 🧰 **基础开发工具**: `go_install.sh`、`nodejs_install.sh`、`git_install.sh`、`protobuf_install.sh`、`vim_go_install.sh`、`gitlint_install.sh`、`env_init.sh`
",
    "- 🌐 **服务与存储组件**: `filebrowser_install.sh`、`samba_install.sh`、`nginx_download_install.sh`、`derper_install.sh`
",
    "- 🐳 **容器引擎**: `docker_install.sh`
",
    "- ⚙️ **工具集**: `tools/codex_switch.sh`、`tools/scan_ip.sh`、`tools/scan_ip2.sh`、`tools/v2ray_conf_setting.sh`
"
]

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    with open(summary_path, "a", encoding="utf-8") as sf:
        sf.writelines(lines)

print("".join(lines))

if not passed:
    print("CI 存在未通过的 Job，请检查详细日志。")
    sys.exit(1)

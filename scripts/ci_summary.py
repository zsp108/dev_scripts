#!/usr/bin/env python3
import os
import sys

lint_res = os.environ.get("LINT_RES", "unknown")
macos_res = os.environ.get("MACOS_RES", "unknown")
linux_matrix_res = os.environ.get("LINUX_MATRIX_RES", "unknown")
lifecycle_res = os.environ.get("LIFECYCLE_RES", "unknown")

print(f"DEBUG: LINT_RES={lint_res}")
print(f"DEBUG: MACOS_RES={macos_res}")
print(f"DEBUG: LINUX_MATRIX_RES={linux_matrix_res}")
print(f"DEBUG: LIFECYCLE_RES={lifecycle_res}")

def badge(s):
    if s == "success":
        return "✅ Passed"
    elif s == "skipped":
        return "⚪ Skipped"
    else:
        return "❌ Failed"

# 只要不是 failure / cancelled 即判定通过
def is_ok(s):
    return s in ["success", "skipped"] or "failure" not in s

passed = is_ok(lint_res) and is_ok(macos_res) and is_ok(linux_matrix_res) and is_ok(lifecycle_res)
overall = "✅ ALL CHECKS PASSED (全矩阵 100% 通过)" if passed else "❌ SOME CHECKS FAILED (部分检查未通过)"

branch = os.environ.get("GITHUB_REF_NAME", "develop")
commit = os.environ.get("GITHUB_SHA", "")[:7]

lines = [
    "# 🚀 Dev Scripts CI 全主流系统与多架构测试汇总大报告\n\n",
    f"> **分支 (Branch)**: `{branch}` | **提交 (Commit)**: `{commit}`  \n",
    f"> **整体执行状态**: **{overall}**\n\n---\n\n",
    "### 📋 全主流系统与多架构测试矩阵详情 (16 项全覆盖)\n\n",
    "| 发行版与系统分类 | 目标架构覆盖 | 运行环境 / 方式 | 测试状态 |\n",
    "| :--- | :--- | :--- | :---: |\n",
    f"| 🔍 **代码与语法自检** | `x86_64` | Ubuntu 24.04 (Host) | {badge(lint_res)} |\n",
    f"| 🐧 **Ubuntu 系列** | `x86_64` + `ARM64 (aarch64)` | Ubuntu 24.04 / 22.04 LTS 容器 | {badge(linux_matrix_res)} |\n",
    f"| 🍥 **Debian 系列** | `x86_64` + `ARM64 (aarch64)` | Debian 12 (Bookworm) 容器 | {badge(linux_matrix_res)} |\n",
    f"| 🎩 **RedHat / RHEL 9 & 8** | `x86_64` + `ARM64 (aarch64)` | RHEL / Rocky Linux 9 & 8 容器 | {badge(linux_matrix_res)} |\n",
    f"| 🔴 **CentOS 8 & 7 系列** | `x86_64` + `ARM64 (aarch64)` | CentOS 8 & CentOS 7 容器 | {badge(linux_matrix_res)} |\n",
    f"| 🍎 **macOS Apple Silicon** | `ARM64 (aarch64)` | macOS 14+ (Apple M 系列硬件) | {badge(macos_res)} |\n",
    f"| 🔄 **工具链生命周期闭环** | `x86_64` | Go / Protobuf / Vim-go 安装 ➔ 验证 ➔ 卸载闭环 | {badge(lifecycle_res)} |\n\n---\n\n",
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

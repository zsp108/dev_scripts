#!/usr/bin/env bash

# 统一配置目录
CODEX_DIR="$HOME/.codex"

# 定义支持的管理组件及其对应的【真实文件、备份前缀、后缀】
# 格式: component_name:real_file:prefix:suffix
COMPONENTS=(
    "auth:${CODEX_DIR}/auth.json:${CODEX_DIR}/auth_:.json"
    "config:${CODEX_DIR}/config.toml:${CODEX_DIR}/config_:.toml"
)

usage() {
    echo "用法: $0 <组件> <命令> [参数]"
    echo "组件:"
    echo "  auth      管理 auth.json"
    echo "  config    管理 config.toml"
    echo ""
    echo "命令:"
    echo "  save <env_name>  【保存】将当前真实的配置文件固化并备份为指定环境"
    echo "  use <env_name>   【切换】修改软链接，指向已有的环境"
    echo "  add              【新增】断开当前软链接，腾出位置让你放入新的配置文件"
    echo "  list             【查看】查看所有可用的环境列表"
    echo ""
    echo "示例:"
    echo "  $0 auth save dev      # 保存当前的 auth.json 为 dev 环境"
    echo "  $0 config use prod    # 将 config.toml 切换到 prod 环境"
    exit 1
}

# 解析组件配置
parse_component() {
    local target_comp=$1
    for comp in "${COMPONENTS[@]}"; do
        IFS=":" read -r name real_file prefix suffix <<< "$comp"
        if [ "$name" = "$target_comp" ]; then
            REAL_FILE="$real_file"
            PREFIX="$prefix"
            SUFFIX="$suffix"
            return 0
        fi
    done
    return 1
}

# 1. 保存当前真实文件
case_save() {
    local env_name=$1
    if [ -z "$env_name" ]; then
        echo "❌ 错误: 请指定要保存的环境名称。例如: $0 $COMP save dev"
        exit 1
    fi

    local target_bak="${PREFIX}${env_name}${SUFFIX}"

    # 严格判断：如果是软链接，直接拒绝
    if [ -L "$REAL_FILE" ]; then
        echo "❌ 拒绝保存: 当前 $(basename "$REAL_FILE") 是一个软链接，无法再次保存！"
        echo "💡 如果你想切换环境，请使用: $0 $COMP use <环境名>"
        echo "💡 如果你想存入新配置，请先运行: $0 $COMP add"
        exit 1
    fi

    # 检查真实文件是否存在
    if [ ! -f "$REAL_FILE" ]; then
        echo "❌ 错误: 未在 ${CODEX_DIR} 下找到真实的 $(basename "$REAL_FILE") 文件，无法保存。"
        exit 1
    fi

    # 检查目标备份是否会发生冲突
    if [ -f "$target_bak" ]; then
        echo "⚠️ 错误: 备份文件 $(basename "$target_bak") 已存在。为防止覆盖，请更换环境名。"
        exit 1
    fi

    # 执行固化与软链转换
    mv "$REAL_FILE" "$target_bak"
    ln -s "$target_bak" "$REAL_FILE"
    echo "💾 成功将当前真实配置保存为 [$COMP] 的环境 [$env_name]，并已自动转换为软链接。"
}

# 2. 切换环境
case_use() {
    local env_name=$1
    if [ -z "$env_name" ]; then
        echo "❌ 错误: 请指定要切换的环境名称。例如: $0 $COMP use dev"
        exit 1
    fi

    local target_bak="${PREFIX}${env_name}${SUFFIX}"

    if [ ! -f "$target_bak" ]; then
        echo "❌ 错误: 未找到组件 [$COMP] 环境 [$env_name] 对应的备份文件。"
        echo "💡 请先确保该环境存在，或者使用 list 命令查看。"
        exit 1
    fi

    # 安全检查：如果当前是真实文件，不让切
    if [ -e "$REAL_FILE" ] && [ ! -L "$REAL_FILE" ]; then
        echo "⚠️ 警告: 检测到当前 $(basename "$REAL_FILE") 是一个新放入的真实文件，尚未保存！"
        echo "💡 请先运行 \`$0 $COMP save <新环境名>\` 将其固化，否则直接切换会导致当前配置丢失。"
        exit 1
    fi

    # 安全通过，删除旧链接（如果是链接），重新建立新链接
    [ -L "$REAL_FILE" ] && rm "$REAL_FILE"
    ln -s "$target_bak" "$REAL_FILE"
    echo "✨ [$COMP] 成功切换到环境 [$env_name] -> 指向 $(basename "$target_bak")"
}

# 3. 新增环境（解开软链腾出位置）
case_add() {
    local base_name=$(basename "$REAL_FILE")
    if [ -L "$REAL_FILE" ]; then
        rm "$REAL_FILE"
        echo "🔓 成功断开当前 [$COMP] 的软链接。"
        echo "💡 现在你可以把全新的真实 $base_name 文件放入 ${CODEX_DIR} 目录，配置好后运行: $0 $COMP save [新环境名]"
    elif [ -f "$REAL_FILE" ]; then
        echo "⚠️ 当前已经是有真实 $base_name 文件了，不需要 add。请直接修改后运行: $0 $COMP save [环境名]"
    else
        echo "ℹ️ 当前没有 $base_name，你可以直接在 ${REAL_FILE} 新建真实文件，配置后运行: $0 $COMP save [环境名]"
    fi
}

# 4. 列表查看
case_list() {
    local current_target=""
    if [ -L "$REAL_FILE" ]; then
        current_target=$(readlink "$REAL_FILE")
    fi

    echo "📂 可用 [$COMP] 环境列表:"
    local found=0

    # 这里的通配符匹配绝对路径前缀
    for file in ${PREFIX}*${SUFFIX}; do
        [ -e "$file" ] || continue
        found=1

        # 提取环境名
        local filename=$(basename "$file")
        local env_name="${filename#$(basename "$PREFIX")}"
        env_name="${env_name%${SUFFIX}}"

        if [ "$file" = "$current_target" ]; then
            echo -e "  -> \033[32m${env_name} (当前生效中)\033[0m"
        else
            echo "     ${env_name}"
        fi
    done

    if [ $found -eq 0 ]; then
        echo "     (暂无备份环境)"
    fi
}

# --- 核心主控逻辑 ---

# 至少需要两个参数 (组件 和 命令)
if [ $# -lt 2 ]; then
    usage
fi

COMP="$1"
CMD="$2"
shift 2 # 移出前两个参数，让 $1 变成具体命令的参数（如 env_name）

# 校验并解析组件
if ! parse_component "$COMP"; then
    echo "❌ 错误: 不支持的组件类型 [$COMP]"
    usage
fi

# 路由命令
case "$CMD" in
    save) case_save "$1" ;;
    use)  case_use "$1" ;;
    add)  case_add ;;
    list) case_list ;;
    *)    usage ;;
esac
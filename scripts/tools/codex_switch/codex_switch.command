#!/bin/zsh
set -euo pipefail

AUTH_FILE="$HOME/.codex/auth.json"
PROFILE_DIR="$HOME/.codex/account_profiles"
CURRENT_FILE="$PROFILE_DIR/.current_profile"
SCRIPT_NAME="$(basename "$0")"

mkdir -p "$PROFILE_DIR"

red() { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

usage() {
  cat <<USAGE
用法:
  $SCRIPT_NAME list
  $SCRIPT_NAME save <账号名>
  $SCRIPT_NAME switch <账号名>
  $SCRIPT_NAME delete <账号名>
  $SCRIPT_NAME current

说明:
  1) 先用 codex 正常登录某个账号
  2) 执行 save <账号名> 把当前登录态保存为一个配置
  3) 之后用 switch <账号名> 快速切换
USAGE
}

check_auth() {
  if [[ ! -f "$AUTH_FILE" ]]; then
    red "未找到 $AUTH_FILE，请先在 Codex 中登录一个账号。"
    exit 1
  fi
}

profile_path() {
  local name="$1"
  printf "%s/%s.auth.json" "$PROFILE_DIR" "$name"
}

current_profile() {
  if [[ -f "$CURRENT_FILE" ]]; then
    <"$CURRENT_FILE"
  fi
}

show_profile_file() {
  local name="$1"

  if [[ -n "$name" ]]; then
    echo "当前账号: $name"
    echo "当前配置文件: $(profile_path "$name")"
  else
    yellow "当前没有标记账号（可能是首次使用或手工登录后未 save/switch）。"
  fi
}

list_profiles() {
  local found=0
  echo "已保存账号列表:"
  for f in "$PROFILE_DIR"/*.auth.json(N); do
    found=1
    local n
    n="$(basename "$f" .auth.json)"
    if [[ -f "$CURRENT_FILE" ]] && [[ "$(<"$CURRENT_FILE")" == "$n" ]]; then
      echo "  - $n (当前)"
    else
      echo "  - $n"
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    yellow "  (暂无)"
  fi
}

save_profile() {
  local name="$1"
  check_auth
  local dst
  dst="$(profile_path "$name")"
  cp "$AUTH_FILE" "$dst"
  chmod 600 "$dst"
  echo "$name" > "$CURRENT_FILE"
  green "已保存当前账号为: $name"
  show_profile_file "$name"
}

switch_profile() {
  local name="$1"
  local src
  src="$(profile_path "$name")"
  if [[ ! -f "$src" ]]; then
    red "账号不存在: $name"
    exit 1
  fi

  if [[ -f "$AUTH_FILE" ]]; then
    local current_name
    local current_path=""
    current_name="$(current_profile)"
    if [[ -n "$current_name" ]]; then
      current_path="$(profile_path "$current_name")"
    fi

    if [[ -n "$current_path" && -f "$current_path" ]] && cmp -s "$AUTH_FILE" "$current_path"; then
      yellow "当前登录态与已保存账号 '$current_name' 一致，跳过备份。"
    elif cmp -s "$AUTH_FILE" "$src"; then
      yellow "当前登录态已经是账号 '$name'，跳过备份。"
    else
      local backup_name="auto_backup_$(date +%Y%m%d_%H%M%S)"
      cp "$AUTH_FILE" "$(profile_path "$backup_name")"
      chmod 600 "$(profile_path "$backup_name")"
      yellow "已自动备份当前登录态为: $backup_name"
    fi
  fi

  cp "$src" "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"
  echo "$name" > "$CURRENT_FILE"
  green "已切换到账号: $name"
  show_profile_file "$name"
  echo "请重启当前 Codex 会话以生效。"
}

delete_profile() {
  local name="$1"
  local p
  p="$(profile_path "$name")"
  if [[ ! -f "$p" ]]; then
    red "账号不存在: $name"
    exit 1
  fi
  rm -f "$p"
  if [[ -f "$CURRENT_FILE" ]] && [[ "$(<"$CURRENT_FILE")" == "$name" ]]; then
    rm -f "$CURRENT_FILE"
  fi
  green "已删除账号: $name"
}

show_current() {
  show_profile_file "$(current_profile)"
}

interactive_menu() {
  echo "========== Codex 账号切换 =========="
  echo "1) 列出账号"
  echo "2) 保存当前账号"
  echo "3) 切换到某个账号"
  echo "4) 删除某个账号"
  echo "5) 查看当前账号标记"
  echo "0) 退出"
  echo -n "请选择: "
  read -r choice

  case "$choice" in
    1) list_profiles ;;
    2)
      echo -n "输入账号名: "
      read -r name
      [[ -n "$name" ]] || { red "账号名不能为空"; exit 1; }
      save_profile "$name"
      ;;
    3)
      echo -n "输入要切换的账号名: "
      read -r name
      [[ -n "$name" ]] || { red "账号名不能为空"; exit 1; }
      switch_profile "$name"
      ;;
    4)
      echo -n "输入要删除的账号名: "
      read -r name
      [[ -n "$name" ]] || { red "账号名不能为空"; exit 1; }
      delete_profile "$name"
      ;;
    5) show_current ;;
    0) exit 0 ;;
    *) red "无效选项"; exit 1 ;;
  esac
}

cmd="${1:-}"
case "$cmd" in
  "") interactive_menu ;;
  list) list_profiles ;;
  save)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    save_profile "$2"
    ;;
  switch)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    switch_profile "$2"
    ;;
  delete)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    delete_profile "$2"
    ;;
  current) show_current ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac

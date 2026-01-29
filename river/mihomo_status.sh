#!/bin/bash

API_URL="http://127.0.0.1:9090"
MAIN_GROUP="🚀 节点切换"
FLAG="/tmp/waybar_mihomo_show_node"

# --- 递归函数 ---
trace_node() {
  local name=$(echo "$1" | sed 's/"//g' | xargs)
  local encoded=$(echo -n "$name" | jq -sRr @uri)
  local info=$(curl -s "$API_URL/proxies/$encoded")
  local type=$(echo "$info" | jq -r .type)
  local next=$(echo "$info" | jq -r .now)

  if [[ "$type" =~ ^(Selector|URLTest|Fallback)$ ]] && [[ "$next" != "null" ]] && [[ "$next" != "$name" ]]; then
    trace_node "$next"
  else
    echo "$name"
  fi
}

# --- 基础检查 ---
if ! curl -s --max-time 0.5 "$API_URL/configs" >/dev/null; then
  [ "$1" == "status" ] && echo '{"text":"","class":"offline"}'
  exit 0
fi

# --- 动作处理 ---
case "$1" in
"toggle_display")
  [ -f "$FLAG" ] && rm "$FLAG" || touch "$FLAG"
  pkill -RTMIN+8 waybar
  exit 0
  ;;
"toggle_mode")
  MODE=$(curl -s "$API_URL/configs" | jq -r .mode | tr '[:upper:]' '[:lower:]')
  case "$MODE" in "rule") NEXT="Global" ;; "global") NEXT="Direct" ;; *) NEXT="Rule" ;; esac
  curl -s -X PATCH "$API_URL/configs" -d "{\"mode\": \"$NEXT\"}"
  pkill -RTMIN+8 waybar
  exit 0
  ;;
esac

# --- 状态捕获 (核心修复区) ---
CONFIG=$(curl -s "$API_URL/configs")
RAW_MODE=$(echo "$CONFIG" | jq -r .mode)
MODE=$(echo "$RAW_MODE" | tr '[:upper:]' '[:lower:]')
TUN=$(echo "$CONFIG" | jq -r .tun.enable)
[ "$TUN" == "true" ] && TUN_STR="接管中" || TUN_STR="未开启"

# 无论是否右键点击，我们先确定当前应该追溯的节点名
# 第一性原理：先算变量，后定显示，防止显示时变量为空
if [ "$MODE" == "direct" ]; then
  FINAL_NODE="Direct"
else
  [ "$MODE" == "global" ] && START="GLOBAL" || START="$MAIN_GROUP"
  START_NODE=$(curl -s "$API_URL/proxies/$(echo -n "$START" | jq -sRr @uri)" | jq -r .now)
  # 执行递归，确保变量被赋值
  FINAL_NODE=$(trace_node "$START_NODE")
fi

# --- 最终输出 ---
# 根据图标和模式定图标
case "$MODE" in "direct") ICON="󱡀" ;; "global") ICON="󰣩" ;; *) ICON="󰖂" ;; esac

# 决定面板文字
if [ -f "$FLAG" ]; then
  DISPLAY_TEXT="$FINAL_NODE"
else
  DISPLAY_TEXT="$ICON"
fi

# 这里是你想要加的部分：确保 tooltip 引用的是刚刚算出来的 $FINAL_NODE
echo "{\"text\":\"$DISPLAY_TEXT\",\"tooltip\":\"📍 出口：$FINAL_NODE\n📡 TUN：$TUN_STR\n⚙️ 模式：$RAW_MODE\",\"class\":\"$MODE\"}"

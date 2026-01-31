#!/bin/bash

# --- 核心配置 ---
API_URL="http://127.0.0.1:9090"
API_SECRET="001101" # 已根据你的测试结果填入
MAIN_GROUP="🚀 节点切换"
FLAG="/tmp/waybar_mihomo_show_node"

# --- 封装带鉴权的 curl 函数 ---
api_curl() {
  # 必须确保 $API_SECRET 在双引号内以防解析错误
  curl -s -H "Authorization: Bearer $API_SECRET" "$@"
}

# --- 递归函数：寻找最底层的真实服务器名 ---
trace_node() {
  local name=$(echo "$1" | sed 's/"//g' | xargs)
  # 这里的 URL 编码处理很关键，防止节点名有特殊字符
  local encoded=$(echo -n "$name" | jq -sRr @uri)

  local info=$(api_curl "$API_URL/proxies/$encoded")
  local type=$(echo "$info" | jq -r .type)
  local next=$(echo "$info" | jq -r .now)

  # 如果是选择器组，递归向下查找
  if [[ "$type" =~ ^(Selector|URLTest|Fallback)$ ]] && [[ "$next" != "null" ]] && [[ "$next" != "$name" ]]; then
    trace_node "$next"
  else
    echo "$name"
  fi
}

# --- 获取基础配置信息 ---
# 增加超时保护，防止 Mihomo 未启动时卡死
CONFIG=$(api_curl --max-time 1 "$API_URL/configs")

if [[ "$CONFIG" == *"Unauthorized"* ]] || [ -z "$CONFIG" ]; then
  echo "{\"text\":\"󰂭 ERR\",\"tooltip\":\"鉴权失败或服务未启动\",\"class\":\"offline\"}"
  exit 0
fi

# 提取关键字段
RAW_MODE=$(echo "$CONFIG" | jq -r .mode)
MODE=$(echo "$RAW_MODE" | tr '[:upper:]' '[:lower:]')
TUN=$(echo "$CONFIG" | jq -r .tun.enable)
[ "$TUN" == "true" ] && TUN_STR="运行中" || TUN_STR="未开启"

# --- 处理命令动作 ---
case "$1" in
"toggle_display")
  [ -f "$FLAG" ] && rm "$FLAG" || touch "$FLAG"
  pkill -RTMIN+8 waybar
  exit 0
  ;;
"toggle_mode")
  case "$MODE" in "rule") NEXT="Global" ;; "global") NEXT="Direct" ;; *) NEXT="Rule" ;; esac
  api_curl -X PATCH "$API_URL/configs" -d "{\"mode\": \"$NEXT\"}"
  pkill -RTMIN+8 waybar
  exit 0
  ;;
esac

# --- 计算显示节点 ---
if [ "$MODE" == "direct" ]; then
  FINAL_NODE="直连模式"
else
  # 确定起点：Global 模式从 GLOBAL 找，Rule 模式从主代理组找
  [ "$MODE" == "global" ] && START_GROUP="GLOBAL" || START_GROUP="$MAIN_GROUP"

  ENCODED_GROUP=$(echo -n "$START_GROUP" | jq -sRr @uri)
  START_NODE=$(api_curl "$API_URL/proxies/$ENCODED_GROUP" | jq -r .now)

  if [ "$START_NODE" == "null" ]; then
    FINAL_NODE="未找到代理组"
  else
    FINAL_NODE=$(trace_node "$START_NODE")
  fi
fi

# --- 最终输出 JSON (供 Waybar 使用) ---
case "$MODE" in "direct") ICON="󱡀" ;; "global") ICON="󰣩" ;; *) ICON="󰖂" ;; esac

if [ -f "$FLAG" ]; then
  # 如果存在标志文件，显示具体节点名
  DISPLAY_TEXT="$ICON $FINAL_NODE"
else
  # 否则只显示模式
  DISPLAY_TEXT="$ICON $RAW_MODE"
fi

echo "{\"text\":\"$DISPLAY_TEXT\",\"tooltip\":\"📍 当前节点：$FINAL_NODE\n📡 TUN：$TUN_STR\n⚙️ 模式：$RAW_MODE\",\"class\":\"$MODE\"}"

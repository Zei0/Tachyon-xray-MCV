#!/bin/sh
# ==============================================================================
# update-xray-sub.sh - Subscription Updater for Tachyon + Xray (MyCloudVault)
# ==============================================================================

CONF_FILE="/etc/xray/config.json"
URL_FILE="/etc/xray/sub.url"

# Цвета для терминала
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -n "$1" ]; then
    SUB_URL="$1"
    mkdir -p /etc/xray
    echo "$SUB_URL" > "$URL_FILE"
elif [ -f "$URL_FILE" ]; then
    SUB_URL=$(cat "$URL_FILE" | tr -d '\r\n')
else
    echo -e "${RED}[ERROR] URL подписки не найден. Укажите ссылку: $0 'https://mycloudvault.de/workspace/<UUID>'${NC}"
    exit 1
fi

echo -e "${YELLOW}[*] Загрузка подписки:${NC} $SUB_URL"
RAW_DATA=$(curl -s -k --connect-timeout 10 -m 20 "$SUB_URL" 2>/dev/null || wget -qO- --timeout=20 --no-check-certificate "$SUB_URL" 2>/dev/null)

if [ -z "$RAW_DATA" ]; then
    echo -e "${RED}[ERROR] Пустой ответ от сервера подписки или нет связи.${NC}"
    exit 1
fi

FIRST_LINE=$(echo "$RAW_DATA" | head -n 1 | tr -d '\r')

if echo "$FIRST_LINE" | grep -q "^vless://"; then
    VLESS_LINK="$FIRST_LINE"
else
    DECODED=$(echo "$FIRST_LINE" | base64 -d 2>/dev/null | tr -d '\r')
    if echo "$DECODED" | grep -q "^vless://"; then
        VLESS_LINK=$(echo "$DECODED" | head -n 1)
    else
        echo -e "${RED}[ERROR] Не найдена ссылка формата vless:// в ответе подписки.${NC}"
        exit 1
    fi
fi

# Парсинг URL формата: vless://UUID@HOST:PORT?QUERY#TAG
UUID=$(echo "$VLESS_LINK" | sed -n 's|^vless://\([^@]*\)@.*|\1|p')
HOST=$(echo "$VLESS_LINK" | sed -n 's|^vless://[^@]*@\([^:]*\):.*|\1|p')
PORT=$(echo "$VLESS_LINK" | sed -n 's|^vless://[^@]*@[^:]*:\([0-9]*\)?.*|\1|p')
QUERY=$(echo "$VLESS_LINK" | sed -n 's|^vless://[^?]*?\([^#]*\).*|\1|p')

get_param() {
    echo "$QUERY" | tr '&' '\n' | grep "^$1=" | head -n 1 | cut -d'=' -f2-
}

PBK=$(get_param pbk)
SID=$(get_param sid)
SNI=$(get_param sni)
SPX=$(get_param spx | sed 's|%2F|/|g')
FLOW=$(get_param flow)
[ -z "$FLOW" ] && FLOW="xtls-rprx-vision"
[ -z "$SNI" ] && SNI="$HOST"

if [ -z "$UUID" ] || [ -z "$HOST" ] || [ -z "$PORT" ] || [ -z "$PBK" ]; then
    echo -e "${RED}[ERROR] Не удалось распарсить обязательные параметры VLESS (UUID, HOST, PORT, PBK).${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Параметры VLESS Reality успешно получены:${NC}"
echo "    Сервер: $HOST:$PORT"
echo "    SNI:    $SNI"
echo "    UUID:   $UUID"
echo "    Flow:   $FLOW"

mkdir -p /etc/xray
cat << EOF_JSON > "$CONF_FILE"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10853,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$HOST",
            "port": $PORT,
            "users": [
              {
                "id": "$UUID",
                "flow": "$FLOW",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "firefox",
          "serverName": "$SNI",
          "publicKey": "$PBK",
          "shortId": "$SID",
          "spiderX": "$SPX"
        }
      }
    }
  ]
}
EOF_JSON

echo -e "${GREEN}[+] Конфигурация $CONF_FILE обновлена.${NC}"

# Обновляем прямой обход для IP и SNI сервера в Tachyon (если Tachyon установлен)
if command -v uci >/dev/null 2>&1 && uci get tachyon >/dev/null 2>&1; then
    DOMAIN_BASE=$(echo "$SNI" | sed 's|^www\.||')
    uci set tachyon.server_direct=section 2>/dev/null || true
    uci set tachyon.server_direct.enabled='1'
    uci set tachyon.server_direct.action='bypass'
    uci set tachyon.server_direct.ip_cidr="$HOST"
    uci set tachyon.server_direct.domain="$DOMAIN_BASE"
    uci commit tachyon
fi

if [ -x /etc/init.d/xray ]; then
    echo -e "${YELLOW}[*] Перезапуск службы Xray...${NC}"
    /etc/init.d/xray restart
fi

#!/bin/sh
# ==============================================================================
# Tachyon + Xray (VLESS Reality) All-in-One Auto Installer
# Repository: https://github.com/Zei0/Tachyon-xray-MCV
# ==============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear 2>/dev/null || true
echo ""
echo -e "${CYAN}==================================================================${NC}"
echo -e "${CYAN}    Tachyon + Xray (VLESS Reality) All-in-One Auto Installer      ${NC}"
echo -e "${CYAN}          https://github.com/Zei0/Tachyon-xray-MCV                ${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo ""

SUB_URL="$1"

if [ -z "$SUB_URL" ]; then
    echo -n "Введите вашу ссылку на подписку (https://mycloudvault.de/workspace/...): "
    read SUB_URL
fi

if [ -z "$SUB_URL" ]; then
    echo -e "${RED}[ERROR] Ссылка на подписку не введена. Установка прервана.${NC}"
    exit 1
fi

echo -e "${BLUE}[*] Ссылка подписки:${NC} $SUB_URL"

# 1. Проверка архитектуры
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64)
        XRAY_ARCH="arm64-v8a"
        ;;
    armv7l|armv7|cortex-a7|cortex-a9)
        XRAY_ARCH="arm32-v7a"
        ;;
    mips|mipsel)
        if grep -q "little endian" /proc/cpuinfo 2>/dev/null; then
            XRAY_ARCH="mips32le"
        else
            XRAY_ARCH="mips32"
        fi
        ;;
    x86_64|amd64)
        XRAY_ARCH="64"
        ;;
    i386|i686)
        XRAY_ARCH="32"
        ;;
    *)
        echo -e "${RED}[ERROR] Неизвестная архитектура: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}[+] Архитектура:${NC} $ARCH (бинарник Xray: ${XRAY_ARCH})"

# 2. Подготовка и загрузка Xray
mkdir -p /etc/xray /tmp/xray_inst

if [ -f /etc/xray/xray.tar.gz ] && [ -s /etc/xray/xray.tar.gz ]; then
    echo -e "${GREEN}[+] Архив /etc/xray/xray.tar.gz уже присутствует, загрузка пропущена.${NC}"
else
    echo -e "${YELLOW}[*] Загрузка Xray-core (${XRAY_ARCH}) с GitHub...${NC}"
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
    
    cd /tmp/xray_inst
    rm -f xray.zip xray
    if command -v curl >/dev/null 2>&1; then
        curl -s -L -k -o xray.zip "$XRAY_URL"
    else
        wget -q -O xray.zip "$XRAY_URL"
    fi

    if [ ! -s xray.zip ]; then
        echo -e "${RED}[ERROR] Не удалось скачать Xray. Проверьте интернет-соединение роутера.${NC}"
        rm -rf /tmp/xray_inst
        exit 1
    fi

    echo -e "${BLUE}[*] Сжатие Xray для безопасного хранения во Flash...${NC}"
    unzip -q -o xray.zip xray
    tar -czf /etc/xray/xray.tar.gz xray
    rm -rf /tmp/xray_inst
    echo -e "${GREEN}[+] Архив сохранен в /etc/xray/xray.tar.gz ($(ls -lh /etc/xray/xray.tar.gz | awk '{print $5}')).${NC}"
fi

# 3. Установка procd сервиса
echo -e "${BLUE}[*] Установка службы автозапуска /etc/init.d/xray...${NC}"
cat << 'EOF_INIT' > /etc/init.d/xray
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=95
STOP=10

PROG=/tmp/xray
CONF=/etc/xray/config.json
ARCHIVE=/etc/xray/xray.tar.gz

init_bin() {
    if [ ! -x "$PROG" ]; then
        if [ -f "$ARCHIVE" ]; then
            tar -xzf "$ARCHIVE" -C /tmp
            chmod +x "$PROG"
        fi
    fi
}

start_service() {
    init_bin
    [ -x "$PROG" ] || return 1
    [ -f "$CONF" ] || return 1

    procd_open_instance
    procd_set_param command "$PROG" run -c "$CONF"
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall xray 2>/dev/null
}
EOF_INIT

chmod +x /etc/init.d/xray
/etc/init.d/xray enable

# 4. Установка скрипта обновления подписки
echo -e "${BLUE}[*] Установка скрипта обновления подписки /usr/bin/update-xray-sub.sh...${NC}"
cat << 'EOF_SUB' > /usr/bin/update-xray-sub.sh
#!/bin/sh
CONF_FILE="/etc/xray/config.json"
URL_FILE="/etc/xray/sub.url"

if [ -n "$1" ]; then
    SUB_URL="$1"
    mkdir -p /etc/xray
    echo "$SUB_URL" > "$URL_FILE"
elif [ -f "$URL_FILE" ]; then
    SUB_URL=$(cat "$URL_FILE" | tr -d '\r\n')
else
    echo "ОШИБКА: URL подписки не найден."
    exit 1
fi

echo "Загрузка подписки: $SUB_URL"
RAW_DATA=$(curl -s -k --connect-timeout 10 -m 20 "$SUB_URL" 2>/dev/null || wget -qO- --timeout=20 --no-check-certificate "$SUB_URL" 2>/dev/null)

if [ -z "$RAW_DATA" ]; then
    echo "ОШИБКА: Пустой ответ или сервер недоступен."
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
        echo "ОШИБКА: Не найдена ссылка vless:// в ответе подписки."
        exit 1
    fi
fi

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
    echo "ОШИБКА: Не удалось распарсить параметры VLESS."
    exit 1
fi

echo "Параметры успешно получены: $HOST:$PORT (SNI: $SNI, UUID: $UUID)"

mkdir -p /etc/xray
cat << EOF_JSON > "$CONF_FILE"
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 10853,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": { "auth": "noauth", "udp": true }
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
            "users": [ { "id": "$UUID", "flow": "$FLOW", "encryption": "none" } ]
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
    /etc/init.d/xray restart
fi
EOF_SUB

chmod +x /usr/bin/update-xray-sub.sh

# 5. Установка утилиты mcv
echo -e "${BLUE}[*] Установка консольной утилиты управления mcv (/usr/bin/mcv)...${NC}"
cat << 'EOF_MCV' > /usr/bin/mcv
#!/bin/sh
case "$1" in
    status)
        echo "=== Статус Xray Моста ==="
        ps | grep '/tmp/xray' | grep -v grep >/dev/null && echo "Процесс:   РАБОТАЕТ" || echo "Процесс:   ОСТАНОВЛЕН"
        netstat -tulpn 2>/dev/null | grep -q ":10853 " && echo "SOCKS5:    127.0.0.1:10853 (OK)" || echo "SOCKS5:    НЕ ОТВЕЧАЕТ"
        [ -f /etc/xray/sub.url ] && echo "Подписка:  $(cat /etc/xray/sub.url)"
        RES=$(curl -s -m 5 --socks5-hostname 127.0.0.1:10853 https://cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
        IP=$(echo "$RES" | grep "^ip=" | cut -d'=' -f2)
        LOC=$(echo "$RES" | grep "^loc=" | cut -d'=' -f2)
        [ -n "$IP" ] && echo "Внешний IP: $IP (Локация: $LOC)" || echo "Внешний IP: Таймаут"
        ;;
    update) /usr/bin/update-xray-sub.sh "$2" ;;
    restart) /etc/init.d/xray restart ;;
    log) logread | grep xray | tail -n 30 ;;
    test) curl -v -m 6 --socks5-hostname 127.0.0.1:10853 https://cloudflare.com/cdn-cgi/trace ;;
    uninstall) /usr/bin/uninstall-xray.sh ;;
    *)
        echo "Использование утилиты mcv:"
        echo "  mcv status      - Проверить статус службы, порт и внешний IP"
        echo "  mcv update      - Обновить подписку"
        echo "  mcv restart     - Перезапустить службу Xray"
        echo "  mcv log         - Показать журнал соединений"
        echo "  mcv test        - Подробный тест туннеля через curl"
        echo "  mcv uninstall   - Удалить Xray и восстановить настройки Tachyon"
        ;;
esac
EOF_MCV

chmod +x /usr/bin/mcv

# 6. Установка деинсталлятора
cat << 'EOF_UN' > /usr/bin/uninstall-xray.sh
#!/bin/sh
/etc/init.d/xray stop 2>/dev/null || true
/etc/init.d/xray disable 2>/dev/null || true
rm -f /etc/init.d/xray /tmp/xray /usr/bin/update-xray-sub.sh /usr/bin/mcv /usr/bin/uninstall-xray.sh
rm -rf /etc/xray
[ -f /etc/crontabs/root ] && sed -i '/update-xray-sub.sh/d' /etc/crontabs/root && /etc/init.d/cron restart 2>/dev/null || true
if command -v uci >/dev/null 2>&1 && uci get tachyon.main >/dev/null 2>&1; then
    CURR=$(uci get tachyon.main.selector_proxy_links 2>/dev/null || true)
    echo "$CURR" | grep -q "127.0.0.1:10853" && uci delete tachyon.main.selector_proxy_links 2>/dev/null || true
    uci delete tachyon.server_direct 2>/dev/null || true
    uci commit tachyon
    /etc/init.d/tachyon restart 2>/dev/null || true
fi
echo "Xray-мост удален. Настройки Tachyon восстановлены."
EOF_UN

chmod +x /usr/bin/uninstall-xray.sh

# 7. Первый запуск и обновление
echo -e "${BLUE}[*] Применение подписки и запуск Xray...${NC}"
/usr/bin/update-xray-sub.sh "$SUB_URL"
sleep 2

# 8. Привязка к Tachyon
if command -v uci >/dev/null 2>&1 && uci get tachyon.main >/dev/null 2>&1; then
    echo -e "${BLUE}[*] Интеграция с Tachyon (привязка SOCKS5 127.0.0.1:10853)...${NC}"
    uci set tachyon.main.selector_proxy_links='socks5://127.0.0.1:10853#Takehost-Xray'
    uci set tachyon.@subscription_url[0].enabled='0' 2>/dev/null || true
    uci commit tachyon
    echo -e "${BLUE}[*] Перезапуск Tachyon для применения новых правил...${NC}"
    /etc/init.d/tachyon restart
fi

# 9. Crontab
mkdir -p /etc/crontabs
touch /etc/crontabs/root
if ! grep -q "update-xray-sub.sh" /etc/crontabs/root; then
    echo "0 4 * * * /usr/bin/update-xray-sub.sh >/dev/null 2>&1" >> /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
fi

# 10. Проверка
echo ""
echo -e "${CYAN}=== Итоговая проверка соединения ===${NC}"
TEST_RES=$(curl -s -m 6 --socks5-hostname 127.0.0.1:10853 https://cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
if echo "$TEST_RES" | grep -q "ip="; then
    OUT_IP=$(echo "$TEST_RES" | grep "^ip=" | cut -d'=' -f2)
    OUT_LOC=$(echo "$TEST_RES" | grep "^loc=" | cut -d'=' -f2)
    echo -e "${GREEN}[УСПЕХ] Туннель VLESS Reality работает штатно!${NC}"
    echo -e "  Внешний IP: ${YELLOW}$OUT_IP${NC} (Страна: ${YELLOW}$OUT_LOC${NC})"
else
    echo -e "${YELLOW}[!] Сервис запущен. Проверьте статус командой: mcv status${NC}"
fi

echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}                 УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                     ${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo -e "Для управления используйте короткую команду: ${CYAN}mcv${NC}"
echo -e "  • ${CYAN}mcv status${NC}  - проверить статус и внешний IP"
echo -e "  • ${CYAN}mcv update${NC}  - обновить подписку"
echo -e "  • ${CYAN}mcv restart${NC} - перезапустить туннель"
echo ""

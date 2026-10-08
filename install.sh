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
        # Определение Little Endian (mipsel/mips32le) vs Big Endian (mips/mips32)
        IS_LE=0
        if [ "$ARCH" = "mipsel" ]; then
            IS_LE=1
        elif [ -f /etc/openwrt_release ] && grep -q "mipsel" /etc/openwrt_release; then
            IS_LE=1
        elif [ -f /etc/apk/arch ] && grep -q "mipsel" /etc/apk/arch; then
            IS_LE=1
        elif command -v apk >/dev/null 2>&1 && apk --print-arch 2>/dev/null | grep -q "mipsel"; then
            IS_LE=1
        elif [ -f /etc/opkg.conf ] && grep -q "mipsel" /etc/opkg.conf; then
            IS_LE=1
        elif grep -q "little endian" /proc/cpuinfo 2>/dev/null; then
            IS_LE=1
        elif grep -q -i -E "mt7621|mt7628|mt7620|ralink|ramips" /proc/cpuinfo 2>/dev/null; then
            IS_LE=1
        elif echo -n I | od -to2 2>/dev/null | head -n1 | grep -q "000001"; then
            IS_LE=1
        elif hexdump -s 5 -n 1 -e '1/1 "%d"' /bin/busybox 2>/dev/null | grep -q "1"; then
            IS_LE=1
        fi

        if [ "$IS_LE" -eq 1 ]; then
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

# 2. Проверка и установка зависимостей (unzip, curl)
UNZIP_CMD=""
if command -v unzip >/dev/null 2>&1; then
    UNZIP_CMD="unzip"
elif busybox unzip --help >/dev/null 2>&1; then
    UNZIP_CMD="busybox unzip"
fi

NEED_DEPS=0
[ -z "$UNZIP_CMD" ] && NEED_DEPS=1
! command -v curl >/dev/null 2>&1 && NEED_DEPS=1

if [ "$NEED_DEPS" -eq 1 ]; then
    echo -e "${YELLOW}[*] Проверка системных утилит (unzip, curl)...${NC}"
    if command -v opkg >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Обновление списков пакетов (opkg update)...${NC}"
        opkg update || true
        if [ -z "$UNZIP_CMD" ]; then
            echo -e "${YELLOW}[*] Установка unzip через opkg...${NC}"
            opkg install unzip || true
        fi
        if ! command -v curl >/dev/null 2>&1; then
            echo -e "${YELLOW}[*] Установка curl через opkg...${NC}"
            opkg install curl || true
        fi
    elif command -v apk >/dev/null 2>&1; then
        if [ -z "$UNZIP_CMD" ]; then
            echo -e "${YELLOW}[*] Установка unzip через apk...${NC}"
            apk -U add unzip || true
        fi
        if ! command -v curl >/dev/null 2>&1; then
            echo -e "${YELLOW}[*] Установка curl через apk...${NC}"
            apk -U add curl || true
        fi
    fi

    if command -v unzip >/dev/null 2>&1; then
        UNZIP_CMD="unzip"
    elif busybox unzip --help >/dev/null 2>&1; then
        UNZIP_CMD="busybox unzip"
    fi
fi

if [ -z "$UNZIP_CMD" ]; then
    echo -e "${RED}[ERROR] Утилита unzip не найдена и не удалось установить её автоматически.${NC}"
    echo -e "${YELLOW}[*] Пожалуйста, выполните команду вручную:${NC} opkg update && opkg install unzip"
    exit 1
fi

# Проверка свободного места во Flash (/overlay или /)
FREE_KB=$(df -k /etc 2>/dev/null | awk 'NR>1 {print $(NF-2)}' | tail -n 1)
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt 10240 ] 2>/dev/null; then
    FREE_MB=$((FREE_KB / 1024))
    echo -e "${YELLOW}[!] ВНИМАНИЕ: Свободного места во Flash памяти: ${FREE_MB} МБ.${NC}"
    echo -e "${YELLOW}[!] Для сохранения архива Xray рекомендуется иметь минимум 10-12 МБ Flash.${NC}"
fi

# 3. Подготовка и загрузка Xray
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
    $UNZIP_CMD -q -o xray.zip xray
    rm -f xray.zip
    tar -czf /etc/xray/xray.tar.gz xray
    rm -rf /tmp/xray_inst

    if [ ! -s /etc/xray/xray.tar.gz ]; then
        echo -e "${RED}[ERROR] Ошибка создания архива /etc/xray/xray.tar.gz. Недостаточно места во Flash?${NC}"
        rm -f /etc/xray/xray.tar.gz
        exit 1
    fi
    echo -e "${GREEN}[+] Архив сохранен в /etc/xray/xray.tar.gz ($(ls -lh /etc/xray/xray.tar.gz | awk '{print $5}')).${NC}"
fi

# 4. Установка procd сервиса
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

# 5. Установка скрипта обновления подписки
echo -e "${BLUE}[*] Установка скрипта обновления подписки /usr/bin/update-xray-sub.sh...${NC}"
cat << 'EOF_SUB' > /usr/bin/update-xray-sub.sh
#!/bin/sh
CONF_FILE="/etc/xray/config.json"
URL_FILE="/etc/xray/sub.url"

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
    echo -e "${RED}[ERROR] URL подписки не найден.${NC}"
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
        echo -e "${RED}[ERROR] Не найдена ссылка vless:// в ответе подписки.${NC}"
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
    echo -e "${RED}[ERROR] Не удалось распарсить параметры VLESS (UUID, HOST, PORT, PBK).${NC}"
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

echo -e "${GREEN}[+] Конфигурация $CONF_FILE обновлена.${NC}"

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
EOF_SUB

chmod +x /usr/bin/update-xray-sub.sh

# 6. Установка утилиты mcv
echo -e "${BLUE}[*] Установка консольной утилиты управления mcv (/usr/bin/mcv)...${NC}"
cat << 'EOF_MCV' > /usr/bin/mcv
#!/bin/sh
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

case "$1" in
    status)
        echo -e "${CYAN}=== Статус Xray Моста ===${NC}"
        if ps | grep -E '/tmp/xray' | grep -v grep >/dev/null; then
            PID=$(ps | grep '/tmp/xray' | grep -v grep | awk '{print $1}')
            echo -e "Процесс Xray:   ${GREEN}РАБОТАЕТ${NC} (PID: $PID)"
        else
            echo -e "Процесс Xray:   ${RED}ОСТАНОВЛЕН${NC}"
        fi
        if netstat -tulpn 2>/dev/null | grep -q ":10853 "; then
            echo -e "SOCKS5 порт:    ${GREEN}127.0.0.1:10853 (Слушает)${NC}"
        else
            echo -e "SOCKS5 порт:    ${RED}Не отвечает${NC}"
        fi
        [ -f /etc/xray/sub.url ] && echo -e "URL подписки:   $(cat /etc/xray/sub.url)"
        echo ""
        echo -e "${CYAN}=== Проверка внешнего IP ===${NC}"
        RES=$(curl -s -m 5 --socks5-hostname 127.0.0.1:10853 https://cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
        if echo "$RES" | grep -q "ip="; then
            IP=$(echo "$RES" | grep "^ip=" | cut -d'=' -f2)
            LOC=$(echo "$RES" | grep "^loc=" | cut -d'=' -f2)
            echo -e "IP через прокси: ${GREEN}$IP${NC} (Страна: ${GREEN}$LOC${NC})"
        else
            echo -e "Проверка curl:  ${RED}Таймаут или ошибка подключения${NC}"
        fi
        ;;
    update) /usr/bin/update-xray-sub.sh "$2" ;;
    restart)
        echo -e "${YELLOW}[*] Перезапуск службы Xray...${NC}"
        /etc/init.d/xray restart
        sleep 1
        $0 status
        ;;
    log)
        echo -e "${CYAN}=== Последние 30 записей лога Xray ===${NC}"
        logread | grep xray | tail -n 30
        ;;
    test)
        echo -e "${CYAN}Тестирование через SOCKS5 127.0.0.1:10853...${NC}"
        curl -v -m 6 --socks5-hostname 127.0.0.1:10853 https://cloudflare.com/cdn-cgi/trace
        ;;
    uninstall)
        if [ -x /usr/bin/uninstall-xray.sh ]; then
            /usr/bin/uninstall-xray.sh
        else
            echo "Файл деинсталляции не найден."
        fi
        ;;
    *)
        echo -e "${CYAN}Управление Xray + MyCloudVault для Tachyon:${NC}"
        echo "  mcv status         - Проверить статус службы, порт и внешний IP"
        echo "  mcv update [URL]   - Обновить подписку (из сохраненного URL или нового)"
        echo "  mcv restart        - Перезапустить службу Xray"
        echo "  mcv log            - Показать недавние соединения"
        echo "  mcv test           - Подробный тест соединения через curl"
        echo "  mcv uninstall      - Полное удаление и возврат к стандартному Tachyon"
        ;;
esac
EOF_MCV

chmod +x /usr/bin/mcv

# 7. Установка деинсталлятора
cat << 'EOF_UN' > /usr/bin/uninstall-xray.sh
#!/bin/sh
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[*] Остановка и отключение службы Xray...${NC}"
/etc/init.d/xray stop 2>/dev/null || true
/etc/init.d/xray disable 2>/dev/null || true

echo -e "${YELLOW}[*] Удаление файлов Xray...${NC}"
rm -f /etc/init.d/xray
rm -rf /etc/xray
rm -f /tmp/xray
rm -f /usr/bin/update-xray-sub.sh
rm -f /usr/bin/mcv
rm -f /usr/bin/uninstall-xray.sh

echo -e "${YELLOW}[*] Удаление задания из crontab...${NC}"
if [ -f /etc/crontabs/root ]; then
    sed -i '/update-xray-sub.sh/d' /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
fi

echo -e "${YELLOW}[*] Восстановление настроек Tachyon...${NC}"
if command -v uci >/dev/null 2>&1 && uci get tachyon.main >/dev/null 2>&1; then
    CURR=$(uci get tachyon.main.selector_proxy_links 2>/dev/null || true)
    if echo "$CURR" | grep -q "127.0.0.1:10853"; then
        uci delete tachyon.main.selector_proxy_links 2>/dev/null || true
    fi
    uci delete tachyon.server_direct 2>/dev/null || true
    uci commit tachyon
    /etc/init.d/tachyon restart 2>/dev/null || true
fi
echo -e "${GREEN}[+] Xray-мост полностью удален. Роутер возвращен в исходное состояние.${NC}"
EOF_UN

chmod +x /usr/bin/uninstall-xray.sh

# 8. Первый запуск и обновление
echo -e "${BLUE}[*] Применение подписки и запуск Xray...${NC}"
/usr/bin/update-xray-sub.sh "$SUB_URL"
sleep 2

# 9. Привязка к Tachyon
if command -v uci >/dev/null 2>&1 && uci get tachyon.main >/dev/null 2>&1; then
    echo -e "${BLUE}[*] Интеграция с Tachyon (привязка SOCKS5 127.0.0.1:10853)...${NC}"
    uci set tachyon.main.selector_proxy_links='socks5://127.0.0.1:10853#Takehost-Xray'
    uci set tachyon.@subscription_url[0].enabled='0' 2>/dev/null || true
    uci commit tachyon
    echo -e "${BLUE}[*] Перезапуск Tachyon для применения новых правил...${NC}"
    /etc/init.d/tachyon restart
fi

# 10. Crontab
mkdir -p /etc/crontabs
touch /etc/crontabs/root
if ! grep -q "update-xray-sub.sh" /etc/crontabs/root; then
    echo "0 4 * * * /usr/bin/update-xray-sub.sh >/dev/null 2>&1" >> /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
fi

# 11. Итоговая проверка соединения
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

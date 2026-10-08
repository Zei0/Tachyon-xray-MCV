#!/bin/sh
# ==============================================================================
# uninstall.sh - Удаление Xray-моста и возврат Tachyon к исходному состоянию
# ==============================================================================

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
    # Если ссылка была настроена на локальный SOCKS5, сбрасываем ее
    CURR_LINK=$(uci get tachyon.main.selector_proxy_links 2>/dev/null || true)
    if echo "$CURR_LINK" | grep -q "127.0.0.1:10853"; then
        uci delete tachyon.main.selector_proxy_links 2>/dev/null || true
    fi
    uci delete tachyon.server_direct 2>/dev/null || true
    uci commit tachyon
    /etc/init.d/tachyon restart 2>/dev/null || true
fi

echo -e "${GREEN}[+] Xray-мост полностью удален. Роутер возвращен в исходное состояние.${NC}"

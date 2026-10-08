# Tachyon + Xray (VLESS Reality) Hybrid for OpenWrt

[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.x-blue)](https://openwrt.org/)
[![Xray-core](https://img.shields.io/badge/Xray--core-v26.x-brightgreen.svg)](https://github.com/XTLS/Xray-core)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Готовое решение оптимизированное для подписок VLESS Reality.

---

## Быстрая установка

Подключитесь к вашему роутеру по SSH (`ssh root@[IP_ADDRESS]`) и выполните одну команду:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Zei0/Tachyon-xray-MCV/main/install.sh)" -- "https://mycloudvault.de/workspace/<ВАШ_UUID>"
```

*(Если на роутере нет `curl`, используйте `wget`):*

```sh
wget -qO- https://raw.githubusercontent.com/Zei0/Tachyon-xray-MCV/main/install.sh | sh -s -- "https://mycloudvault.de/workspace/<ВАШ_UUID>"
```

Инсталлятор автоматически:

* Определит архитектуру процессора (`aarch64`, `armv7l`, `mips`, `mipsel`, `x86_64`).
* Проверит и установит недостающие пакеты (`unzip`, `curl`).
* Загрузит и оптимизирует `xray-core`.
* Расшифрует подписку VLESS Reality и настроит конфиг.
* Свяжет Tachyon с локальным шлюзом `127.0.0.1:10853`.
* Настроит ежедневное автообновление ключей в 04:00 утра.
* Проверит соединение и выведет статус.

> [!TIP]
> На чистых образах OpenWrt можно предварительно установить зависимости вручную:
> ```sh
> # Для OpenWrt 24.10 и старше (opkg):
> opkg update && opkg install unzip curl
> 
> # Для OpenWrt 25.12+ (apk):
> apk -U add unzip curl
> ```

---

## Управление через утилиту `mcv`

После установки на роутере доступна быстрая консольная утилита **`mcv`**:

| Команда | Описание |
| :--- | :--- |
| `mcv status` | Показать статус службы, порт и внешний IP через прокси |
| `mcv update` | Обновить подписку (скачать свежие ключи Reality) |
| `mcv update <URL>` | Сменить ссылку на подписку и применить её |
| `mcv restart` | Перезапустить службу Xray |
| `mcv log` | Просмотреть недавние соединения Xray |
| `mcv test` | Провести подробный тест туннеля через curl |
| `mcv uninstall` | Полное удаление сборки и возврат Tachyon к стандартным настройкам |

---

## Структура репозитория

* [`install.sh`](install.sh) - Универсальный скрипт автоустановки и первичной настройки.
* [`update-xray-sub.sh`](update-xray-sub.sh) - Парсер подписки и генератор конфигурации.
* [`xray.init`](xray.init) - Системный procd-сервис OpenWrt для запуска из оперативной памяти.
* [`mcv`](mcv) - Консольная утилита управления.
* [`uninstall.sh`](uninstall.sh) - Скрипт полного и безопасного удаления.

---

## Совместимость

Протестировано и гарантированно работает на:

* **Архитектуры:** `aarch64` (ARM64), `x86_64`.
* **Роутеры:** Xiaomi AX3000T, Redmi AX6000, x86 мини-ПК.
* **Прошивки:** OpenWrt 24.10, ImmortalWrt.

---

## Лицензия

Распространяется под лицензией [MIT](LICENSE).

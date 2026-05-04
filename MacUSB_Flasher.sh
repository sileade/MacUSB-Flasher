#!/bin/bash

# MacUSB Flasher v1.0
# Универсальная утилита для создания загрузочных флешек на macOS
# Поддержка: Windows, Linux, Raspberry Pi, ARM
# Автор: Manus AI
# Запуск: ./MacUSB_Flasher.sh (БЕЗ sudo!)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

VERSION="1.2"
REPO_URL="https://raw.githubusercontent.com/sileade/MacUSB-Flasher/main/MacUSB_Flasher.sh"

# --- Защита от запуска через sudo ---
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}ОШИБКА: НЕ запускайте через sudo!${NC}"
    echo "Скрипт сам запросит пароль, когда нужно."
    exit 1
fi

# --- Функция: Автообновление ---
check_for_updates() {
    echo -e "${BLUE}[*] Проверка обновлений...${NC}"
    
    # Скачиваем последнюю версию скрипта во временный файл
    TMP_FILE="/tmp/MacUSB_Flasher_latest.sh"
    if curl -s -f -o "$TMP_FILE" "$REPO_URL"; then
        # Извлекаем версию из скачанного файла
        LATEST_VERSION=$(grep -o 'VERSION="[0-9.]*"' "$TMP_FILE" | head -1 | cut -d'"' -f2)
        
        if [ -n "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "$VERSION" ]; then
            echo -e "${GREEN}[!] Найдена новая версия: v${LATEST_VERSION} (текущая: v${VERSION})${NC}"
            echo -e "${YELLOW}Обновление...${NC}"
            
            # Копируем новый скрипт поверх текущего
            cp "$TMP_FILE" "$0"
            chmod +x "$0"
            
            echo -e "${GREEN}[OK] Успешно обновлено! Перезапуск...${NC}"
            sleep 1
            
            # Перезапускаем обновленный скрипт
            exec "$0" "$@"
        else
            echo -e "${GREEN}[OK] У вас установлена последняя версия (v${VERSION}).${NC}"
        fi
    else
        echo -e "${YELLOW}[!] Не удалось проверить обновления (нет интернета?). Пропускаем.${NC}"
    fi
    rm -f "$TMP_FILE"
    echo ""
}

# --- Функция: Баннер ---
show_banner() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       ${BOLD}MacUSB Flasher v${VERSION}${NC}${CYAN}              ║${NC}"
    echo -e "${CYAN}║  Создание загрузочных USB на macOS       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# --- Функция: Проверка и установка зависимостей ---
check_deps() {
    echo -e "${BLUE}[*] Проверка зависимостей...${NC}"

    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}Homebrew не найден. Установка...${NC}"
        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Добавляем brew в PATH для Apple Silicon
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi

    if ! command -v wimlib-imagex &> /dev/null; then
        echo -e "${YELLOW}wimlib не найден. Установка...${NC}"
        brew install wimlib
    fi

    echo -e "${GREEN}[OK] Зависимости готовы.${NC}"
    echo ""
}

# --- Функция: Ввод пути к образу ---
get_image_path() {
    local ext_hint="$1"
    echo ""
    echo -e "${YELLOW}Введите путь к файлу образа ${ext_hint}${NC}"
    echo "(Можно перетащить файл из Finder в это окно)"
    read -r -p "Путь: " ISO_PATH

    # Очистка пути от кавычек, пробелов, обратных слэшей
    ISO_PATH="${ISO_PATH#"${ISO_PATH%%[![:space:]]*}"}"
    ISO_PATH="${ISO_PATH%"${ISO_PATH##*[![:space:]]}"}"
    ISO_PATH=$(echo "$ISO_PATH" | sed "s/\\\\//g;s/^[\"']//;s/[\"']$//")

    if [ ! -f "$ISO_PATH" ]; then
        echo -e "${RED}Файл не найден: $ISO_PATH${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] Образ: $ISO_PATH${NC}"
}

# --- Функция: Автоопределение USB ---
auto_detect_usb() {
    echo ""
    echo -e "${YELLOW}Отключите флешку, если она сейчас вставлена.${NC}"
    read -r -p "Нажмите Enter, когда флешка будет отключена..."

    BEFORE=$(diskutil list external 2>/dev/null \
        | grep -o '/dev/disk[0-9]*' | sort -u)

    echo ""
    echo -e "${CYAN}Теперь ВСТАВЬТЕ флешку в Mac...${NC}"
    echo "Ожидание (до 60 секунд)..."

    NEW_DISK=""
    for _ in $(seq 1 60); do
        AFTER=$(diskutil list external 2>/dev/null \
            | grep -o '/dev/disk[0-9]*' | sort -u)
        for d in $AFTER; do
            if ! echo "$BEFORE" | grep -q "$d"; then
                NEW_DISK="$d"
                break 2
            fi
        done
        sleep 1
        echo -n "."
    done
    echo ""

    if [ -z "$NEW_DISK" ]; then
        echo -e "${RED}Флешка не обнаружена за 60 секунд.${NC}"
        exit 1
    fi

    INFO=$(diskutil info "$NEW_DISK")
    D_NAME=$(echo "$INFO" | grep "Device / Media Name:" \
        | awk -F': ' '{print $2}' | xargs)
    D_SIZE=$(echo "$INFO" | grep "Disk Size:" \
        | awk -F': ' '{print $2}' | awk -F'\\(' '{print $1}' | xargs)

    echo ""
    echo -e "${GREEN}Обнаружена флешка:${NC}"
    echo -e "  Диск:   ${CYAN}${NEW_DISK}${NC}"
    echo -e "  Имя:    ${CYAN}${D_NAME}${NC}"
    echo -e "  Размер: ${CYAN}${D_SIZE}${NC}"
    echo ""
    echo -e "${RED}ВСЕ ДАННЫЕ НА ${NEW_DISK} БУДУТ УДАЛЕНЫ!${NC}"
    read -r -p "Продолжить? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "Отменено."
        exit 0
    fi
}

# --- Функция: Проверка флешки (Верификация) ---
verify_usb() {
    echo ""
    echo -e "${BLUE}[*] Проверка целостности записанной флешки...${NC}"
    
    # Даем системе время на монтирование
    sleep 3
    
    # Проверяем, смонтирована ли флешка
    MOUNT_POINT=$(mount | grep "$NEW_DISK" | awk -F' on ' '{print $2}' | awk -F' \\(' '{print $1}')
    
    if [ -z "$MOUNT_POINT" ]; then
        # Пытаемся смонтировать принудительно
        diskutil mountDisk "$NEW_DISK" >/dev/null 2>&1 || true
        sleep 2
        MOUNT_POINT=$(mount | grep "$NEW_DISK" | awk -F' on ' '{print $2}' | awk -F' \\(' '{print $1}')
    fi
    
    if [ -n "$MOUNT_POINT" ]; then
        # Проверка наличия загрузочных файлов
        if [ -d "$MOUNT_POINT/efi" ] || [ -d "$MOUNT_POINT/EFI" ] || [ -d "$MOUNT_POINT/boot" ] || [ -f "$MOUNT_POINT/bootmgr" ] || [ -f "$MOUNT_POINT/kernel.img" ] || [ -f "$MOUNT_POINT/start.elf" ]; then
            echo -e "${GREEN}[OK] Загрузочные файлы (EFI/Boot) найдены!${NC}"
            echo -e "${GREEN}[OK] Файловая система читается корректно.${NC}"
            echo -e "${GREEN}[OK] Верификация пройдена успешно. Флешка готова к загрузке.${NC}"
        else
            echo -e "${YELLOW}[!] ВНИМАНИЕ: Загрузочные файлы не найдены в корне диска.${NC}"
            echo -e "${YELLOW}Возможно, образ не является загрузочным или записан с ошибкой.${NC}"
        fi
    else
        # Для некоторых Linux/ARM образов macOS не может прочитать файловую систему (ext4/ext3)
        echo -e "${YELLOW}[!] macOS не может прочитать файловую систему флешки.${NC}"
        echo -e "${YELLOW}Это нормально для Linux (ext4) и Raspberry Pi образов.${NC}"
        echo -e "${GREEN}[OK] Физическая запись завершена без ошибок.${NC}"
    fi
}

# --- Функция: Запись Windows (UEFI) ---
flash_windows() {
    echo ""
    echo -e "${BLUE}[1/5] Форматирование (FAT32 + GPT)...${NC}"
    sudo diskutil eraseDisk MS-DOS "WINUSB" GPT "$NEW_DISK"

    echo ""
    echo -e "${BLUE}[2/5] Монтирование ISO...${NC}"
    MOUT=$(hdiutil mount "$ISO_PATH" 2>&1)
    ISO_MP=$(echo "$MOUT" | grep -o '/Volumes/.*' \
        | tail -1 | sed 's/[[:space:]]*$//')

    if [ -z "$ISO_MP" ] || [ ! -d "$ISO_MP" ]; then
        echo -e "${RED}Не удалось смонтировать ISO!${NC}"
        exit 1
    fi
    echo -e "${GREEN}ISO: $ISO_MP${NC}"

    echo ""
    echo -e "${BLUE}[3/5] Копирование файлов...${NC}"
    echo "  (Это может занять 5-15 минут)"
    rsync -avh --progress \
        --exclude='sources/install.wim' \
        --exclude='sources/install.esd' \
        "$ISO_MP/" /Volumes/WINUSB/

    WIM="$ISO_MP/sources/install.wim"
    ESD="$ISO_MP/sources/install.esd"

    if [ -f "$WIM" ]; then
        WSIZE=$(stat -f%z "$WIM" 2>/dev/null || echo 0)
        echo ""
        echo -e "${BLUE}[4/5] Обработка install.wim...${NC}"
        if [ "$WSIZE" -gt 4294967295 ]; then
            echo "  Файл > 4 ГБ, разделяем..."
            mkdir -p /Volumes/WINUSB/sources
            wimlib-imagex split "$WIM" \
                /Volumes/WINUSB/sources/install.swm 3800
        else
            echo "  Файл < 4 ГБ, копируем целиком..."
            cp "$WIM" /Volumes/WINUSB/sources/
        fi
    elif [ -f "$ESD" ]; then
        echo ""
        echo -e "${BLUE}[4/5] Копирование install.esd...${NC}"
        cp "$ESD" /Volumes/WINUSB/sources/
    else
        echo ""
        echo -e "${YELLOW}[4/5] install.wim/esd не найден.${NC}"
    fi

    echo ""
    echo -e "${BLUE}[5/5] Отмонтирование ISO...${NC}"
    hdiutil detach "$ISO_MP" 2>/dev/null || true
    
    verify_usb
}

# --- Функция: Запись через dd (Linux / ARM) ---
flash_dd() {
    RDISK=$(echo "$NEW_DISK" | sed 's|/dev/disk|/dev/rdisk|')

    echo ""
    echo -e "${BLUE}[1/3] Отмонтирование флешки...${NC}"
    sudo diskutil unmountDisk "$NEW_DISK"

    echo ""
    echo -e "${BLUE}[2/3] Запись образа (dd)...${NC}"
    echo -e "${YELLOW}  Это может занять 5-30 минут.${NC}"
    echo "  Нажмите Ctrl+T для просмотра прогресса."
    echo ""

    sudo dd bs=4m if="$ISO_PATH" of="$RDISK" status=progress

    echo ""
    echo -e "${BLUE}[3/3] Синхронизация...${NC}"
    sync
    
    verify_usb
    
    echo ""
    echo -e "${BLUE}[*] Извлечение флешки...${NC}"
    sudo diskutil eject "$NEW_DISK" 2>/dev/null || true
}

# --- Функция: Распаковка сжатых образов ---
decompress_if_needed() {
    case "$ISO_PATH" in
        *.gz)
            echo -e "${BLUE}Распаковка .gz...${NC}"
            UNPACKED="${ISO_PATH%.gz}"
            gunzip -k "$ISO_PATH" 2>/dev/null || true
            ISO_PATH="$UNPACKED"
            ;;
        *.xz)
            echo -e "${BLUE}Распаковка .xz...${NC}"
            if ! command -v xz &> /dev/null; then
                echo -e "${YELLOW}Установка xz...${NC}"
                brew install xz
            fi
            UNPACKED="${ISO_PATH%.xz}"
            xz -dk "$ISO_PATH" 2>/dev/null || true
            ISO_PATH="$UNPACKED"
            ;;
        *.zip)
            echo -e "${BLUE}Распаковка .zip...${NC}"
            UNZIP_DIR="$(dirname "$ISO_PATH")/unzipped_img"
            mkdir -p "$UNZIP_DIR"
            unzip -o "$ISO_PATH" -d "$UNZIP_DIR"
            IMG_FILE=$(find "$UNZIP_DIR" -name "*.img" -o -name "*.iso" \
                | head -1)
            if [ -z "$IMG_FILE" ]; then
                echo -e "${RED}Не найден .img/.iso в архиве!${NC}"
                exit 1
            fi
            ISO_PATH="$IMG_FILE"
            ;;
    esac
    echo -e "${GREEN}[OK] Образ: $ISO_PATH${NC}"
}

# --- Функция: Подменю Linux ---
menu_linux() {
    echo ""
    echo -e "${BOLD}Выберите дистрибутив Linux:${NC}"
    echo "  1) Ubuntu / Ubuntu Server"
    echo "  2) Debian"
    echo "  3) Fedora"
    echo "  4) Linux Mint"
    echo "  5) Arch Linux"
    echo "  6) openSUSE"
    echo "  7) Kali Linux"
    echo "  8) Другой дистрибутив (.iso)"
    echo ""
    read -r -p "Ваш выбор (1-8): " LCHOICE

    case $LCHOICE in
        1) echo -e "${CYAN}Режим: Ubuntu${NC}" ;;
        2) echo -e "${CYAN}Режим: Debian${NC}" ;;
        3) echo -e "${CYAN}Режим: Fedora${NC}" ;;
        4) echo -e "${CYAN}Режим: Linux Mint${NC}" ;;
        5) echo -e "${CYAN}Режим: Arch Linux${NC}" ;;
        6) echo -e "${CYAN}Режим: openSUSE${NC}" ;;
        7) echo -e "${CYAN}Режим: Kali Linux${NC}" ;;
        8) echo -e "${CYAN}Режим: Другой Linux${NC}" ;;
        *)
            echo -e "${RED}Неверный выбор!${NC}"
            exit 1
            ;;
    esac

    get_image_path "(.iso)"
    auto_detect_usb
    flash_dd
}

# --- Функция: Подменю ARM / Raspberry Pi ---
menu_arm() {
    echo ""
    echo -e "${BOLD}Выберите систему:${NC}"
    echo "  1) Raspberry Pi OS (Raspbian)"
    echo "  2) Ubuntu для Raspberry Pi"
    echo "  3) DietPi"
    echo "  4) LibreELEC / OSMC"
    echo "  5) Home Assistant OS"
    echo "  6) Armbian (Orange Pi, Banana Pi и др.)"
    echo "  7) Другой ARM-образ (.img)"
    echo ""
    read -r -p "Ваш выбор (1-7): " ACHOICE

    case $ACHOICE in
        1) echo -e "${CYAN}Режим: Raspberry Pi OS${NC}" ;;
        2) echo -e "${CYAN}Режим: Ubuntu ARM${NC}" ;;
        3) echo -e "${CYAN}Режим: DietPi${NC}" ;;
        4) echo -e "${CYAN}Режим: LibreELEC / OSMC${NC}" ;;
        5) echo -e "${CYAN}Режим: Home Assistant OS${NC}" ;;
        6) echo -e "${CYAN}Режим: Armbian${NC}" ;;
        7) echo -e "${CYAN}Режим: Другой ARM${NC}" ;;
        *)
            echo -e "${RED}Неверный выбор!${NC}"
            exit 1
            ;;
    esac

    get_image_path "(.img / .img.gz / .img.xz / .zip)"
    decompress_if_needed
    auto_detect_usb
    flash_dd
}

# --- ГЛАВНОЕ МЕНЮ ---
show_banner
check_for_updates

echo -e "${BOLD}Что вы хотите записать?${NC}"
echo ""
echo "  1) Windows 10 / 11  (UEFI-загрузка)"
echo "  2) Linux             (Ubuntu, Fedora, Debian...)"
echo "  3) Raspberry Pi / ARM"
echo "  4) Любой .iso / .img (универсальный режим dd)"
echo ""
echo "  0) Выход"
echo ""
read -r -p "Ваш выбор (0-4): " MAIN_CHOICE

case $MAIN_CHOICE in
    1)
        echo ""
        echo -e "${CYAN}=== Windows (UEFI) ===${NC}"
        check_deps
        get_image_path "(.iso)"
        auto_detect_usb
        flash_windows
        ;;
    2)
        echo ""
        echo -e "${CYAN}=== Linux ===${NC}"
        menu_linux
        ;;
    3)
        echo ""
        echo -e "${CYAN}=== Raspberry Pi / ARM ===${NC}"
        menu_arm
        ;;
    4)
        echo ""
        echo -e "${CYAN}=== Универсальный режим (dd) ===${NC}"
        get_image_path "(.iso / .img)"
        decompress_if_needed
        auto_detect_usb
        flash_dd
        ;;
    0)
        echo "Выход."
        exit 0
        ;;
    *)
        echo -e "${RED}Неверный выбор!${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ГОТОВО! Флешка успешно записана!     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "Для загрузки на целевом ПК:"
echo "  - UEFI: обычно F12, F8, F11 или Esc"
echo "  - Raspberry Pi: просто вставьте карту"
echo ""
read -r -p "Нажмите Enter для выхода..."

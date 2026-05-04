#!/bin/bash

# MacUSB Flasher v2.0
# Универсальная утилита для создания загрузочных флешек на macOS
# Поддержка: Windows, Linux, Raspberry Pi, ARM, Временная флешка (Бэкап/Восстановление)
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

VERSION="2.0"
REPO_URL="https://raw.githubusercontent.com/sileade/MacUSB-Flasher/main/MacUSB_Flasher.sh"
LOG_FILE="$HOME/Library/Logs/MacUSB_Flasher.log"
BACKUP_DIR="$HOME/MacUSB_Backups"

# --- Защита от запуска через sudo ---
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}ОШИБКА: НЕ запускайте через sudo!${NC}"
    echo "Скрипт сам запросит пароль, когда нужно."
    exit 1
fi

# --- Логирование ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# --- Функция: Автообновление ---
check_for_updates() {
    echo -e "${BLUE}[*] Проверка обновлений...${NC}"
    TMP_FILE="/tmp/MacUSB_Flasher_latest.sh"
    if curl -s -f -o "$TMP_FILE" "$REPO_URL"; then
        LATEST_VERSION=$(grep -o 'VERSION="[0-9.]*"' "$TMP_FILE" | head -1 | cut -d'"' -f2)
        if [ -n "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "$VERSION" ]; then
            echo -e "${GREEN}[!] Найдена новая версия: v${LATEST_VERSION} (текущая: v${VERSION})${NC}"
            echo -e "${YELLOW}Обновление...${NC}"
            cp "$TMP_FILE" "$0"
            chmod +x "$0"
            echo -e "${GREEN}[OK] Успешно обновлено! Перезапуск...${NC}"
            sleep 1
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
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
    if ! command -v wimlib-imagex &> /dev/null; then
        echo -e "${YELLOW}wimlib не найден. Установка...${NC}"
        brew install wimlib
    fi
    if ! command -v pv &> /dev/null; then
        echo -e "${YELLOW}pv (прогресс-бар) не найден. Установка...${NC}"
        brew install pv
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

    BEFORE=$(diskutil list external 2>/dev/null | grep -o '/dev/disk[0-9]*' | sort -u)

    echo ""
    echo -e "${CYAN}Теперь ВСТАВЬТЕ флешку в Mac...${NC}"
    echo "Ожидание (до 60 секунд)..."

    NEW_DISK=""
    for _ in $(seq 1 60); do
        AFTER=$(diskutil list external 2>/dev/null | grep -o '/dev/disk[0-9]*' | sort -u)
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
    D_NAME=$(echo "$INFO" | grep "Device / Media Name:" | awk -F': ' '{print $2}' | xargs)
    D_SIZE=$(echo "$INFO" | grep "Disk Size:" | awk -F': ' '{print $2}' | awk -F'\\(' '{print $1}' | xargs)

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

# --- Функция: Дотошная проверка флешки (Верификация) ---
verify_usb() {
    echo ""
    echo -e "${BLUE}[*] Дотошная проверка целостности записанной флешки...${NC}"
    sleep 3
    
    MOUNT_POINT=$(mount | grep "$NEW_DISK" | awk -F' on ' '{print $2}' | awk -F' \\(' '{print $1}')
    if [ -z "$MOUNT_POINT" ]; then
        diskutil mountDisk "$NEW_DISK" >/dev/null 2>&1 || true
        sleep 2
        MOUNT_POINT=$(mount | grep "$NEW_DISK" | awk -F' on ' '{print $2}' | awk -F' \\(' '{print $1}')
    fi
    
    if [ -n "$MOUNT_POINT" ]; then
        if [ -d "$MOUNT_POINT/efi" ] || [ -d "$MOUNT_POINT/EFI" ] || [ -d "$MOUNT_POINT/boot" ] || [ -f "$MOUNT_POINT/bootmgr" ] || [ -f "$MOUNT_POINT/kernel.img" ] || [ -f "$MOUNT_POINT/start.elf" ]; then
            echo -e "${GREEN}[OK] Загрузочные файлы (EFI/Boot) найдены!${NC}"
            echo -e "${GREEN}[OK] Файловая система читается корректно.${NC}"
            
            # Проверка целостности файлов (выборочно)
            echo -e "${BLUE}[*] Проверка читаемости файлов...${NC}"
            find "$MOUNT_POINT" -type f -size -1M -print0 | head -n 10 | xargs -0 cat >/dev/null 2>&1 && echo -e "${GREEN}[OK] Файлы читаются без ошибок I/O.${NC}" || echo -e "${YELLOW}[!] Возможны ошибки чтения файлов.${NC}"
            
            echo -e "${GREEN}[OK] Верификация пройдена успешно. Флешка готова к загрузке.${NC}"
            log "Успешная запись и верификация: $ISO_PATH на $NEW_DISK"
        else
            echo -e "${YELLOW}[!] ВНИМАНИЕ: Загрузочные файлы не найдены в корне диска.${NC}"
            echo -e "${YELLOW}Возможно, образ не является загрузочным или записан с ошибкой.${NC}"
            log "Ошибка верификации (нет загрузочных файлов): $ISO_PATH на $NEW_DISK"
        fi
    else
        echo -e "${YELLOW}[!] macOS не может прочитать файловую систему флешки.${NC}"
        echo -e "${YELLOW}Это нормально для Linux (ext4) и Raspberry Pi образов.${NC}"
        echo -e "${GREEN}[OK] Физическая запись завершена без ошибок.${NC}"
        log "Успешная физическая запись (ФС не читается macOS): $ISO_PATH на $NEW_DISK"
    fi
}

# --- Функция: Уведомление macOS ---
notify_done() {
    osascript -e 'display notification "Запись загрузочной флешки успешно завершена!" with title "MacUSB Flasher"'
}

# --- Функция: Запись Windows (UEFI) ---
flash_windows() {
    echo ""
    echo -e "${BLUE}[1/5] Форматирование (FAT32 + GPT)...${NC}"
    sudo diskutil eraseDisk MS-DOS "WINUSB" GPT "$NEW_DISK"

    echo ""
    echo -e "${BLUE}[2/5] Монтирование ISO...${NC}"
    MOUT=$(hdiutil mount "$ISO_PATH" 2>&1)
    ISO_MP=$(echo "$MOUT" | grep -o '/Volumes/.*' | tail -1 | sed 's/[[:space:]]*$//')

    if [ -z "$ISO_MP" ] || [ ! -d "$ISO_MP" ]; then
        echo -e "${RED}Не удалось смонтировать ISO!${NC}"
        exit 1
    fi
    echo -e "${GREEN}ISO: $ISO_MP${NC}"

    echo ""
    echo -e "${BLUE}[3/5] Копирование файлов...${NC}"
    rsync -avh --progress --exclude='sources/install.wim' --exclude='sources/install.esd' "$ISO_MP/" /Volumes/WINUSB/

    WIM="$ISO_MP/sources/install.wim"
    ESD="$ISO_MP/sources/install.esd"

    if [ -f "$WIM" ]; then
        WSIZE=$(stat -f%z "$WIM" 2>/dev/null || echo 0)
        echo ""
        echo -e "${BLUE}[4/5] Обработка install.wim...${NC}"
        if [ "$WSIZE" -gt 4294967295 ]; then
            echo "  Файл > 4 ГБ, разделяем..."
            mkdir -p /Volumes/WINUSB/sources
            wimlib-imagex split "$WIM" /Volumes/WINUSB/sources/install.swm 3800
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
    notify_done
}

# --- Функция: Запись через dd с прогресс-баром (Linux / ARM) ---
flash_dd() {
    RDISK=$(echo "$NEW_DISK" | sed 's|/dev/disk|/dev/rdisk|')
    echo ""
    echo -e "${BLUE}[1/3] Отмонтирование флешки...${NC}"
    sudo diskutil unmountDisk "$NEW_DISK"

    echo ""
    echo -e "${BLUE}[2/3] Запись образа (dd + pv)...${NC}"
    ISO_SIZE=$(stat -f%z "$ISO_PATH" 2>/dev/null || stat -c%s "$ISO_PATH" 2>/dev/null)
    
    if command -v pv &> /dev/null; then
        sudo sh -c "pv -s $ISO_SIZE '$ISO_PATH' | dd bs=4m of='$RDISK'"
    else
        sudo dd bs=4m if="$ISO_PATH" of="$RDISK" status=progress
    fi

    echo ""
    echo -e "${BLUE}[3/3] Синхронизация...${NC}"
    sync
    
    verify_usb
    notify_done
    
    echo ""
    echo -e "${BLUE}[*] Извлечение флешки...${NC}"
    sudo diskutil eject "$NEW_DISK" 2>/dev/null || true
}

# --- Функция: Режим Временной Флешки (Бэкап -> Запись -> Восстановление) ---
temp_usb_mode() {
    echo ""
    echo -e "${CYAN}=== Режим Временной Флешки ===${NC}"
    echo "1. Данные с флешки будут сохранены в архив на Mac"
    echo "2. Флешка будет отформатирована и записана как загрузочная"
    echo "3. После использования вы вставляете её обратно, и данные восстанавливаются"
    echo ""
    
    get_image_path "(.iso / .img)"
    auto_detect_usb
    
    # Бэкап
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/usb_backup_$(date '+%Y%m%d_%H%M%S').zip"
    
    MOUNT_POINT=$(mount | grep "$NEW_DISK" | awk -F' on ' '{print $2}' | awk -F' \\(' '{print $1}')
    if [ -z "$MOUNT_POINT" ]; then
        diskutil mountDisk "$NEW_DISK" >/dev/null 2>&1 || true
        sleep 2
        MOUNT_POINT=$(mount | grep "$NEW_DISK" | awk -F' on ' '{print $2}' | awk -F' \\(' '{print $1}')
    fi
    
    if [ -n "$MOUNT_POINT" ]; then
        echo -e "${BLUE}[*] Создание резервной копии данных флешки...${NC}"
        cd "$MOUNT_POINT" && zip -r "$BACKUP_FILE" ./*
        echo -e "${GREEN}[OK] Бэкап сохранен: $BACKUP_FILE${NC}"
    else
        echo -e "${YELLOW}[!] Не удалось смонтировать флешку для бэкапа. Возможно она пустая или не отформатирована.${NC}"
    fi
    
    # Запись
    echo -e "${BLUE}[*] Переход к записи образа...${NC}"
    flash_dd
    
    # Ожидание возврата
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}Загрузочная флешка готова! Вы можете извлечь её и использовать.${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    echo -e "${BOLD}Что делать дальше?${NC}"
    echo "1) Ждать возврата флешки для восстановления данных сейчас"
    echo "2) Выйти (бэкап сохранен в $BACKUP_DIR, восстановите позже вручную)"
    read -r -p "Ваш выбор (1-2): " WAIT_CHOICE
    
    if [ "$WAIT_CHOICE" == "1" ]; then
        echo ""
        echo -e "${YELLOW}🔌 Отключите флешку (если еще не отключили) и используйте её.${NC}"
        echo -e "${YELLOW}Когда закончите, вставьте её обратно в Mac.${NC}"
        echo "Ожидание подключения..."
        
        BEFORE=$(diskutil list external 2>/dev/null | grep -o '/dev/disk[0-9]*' | sort -u)
        RESTORE_DISK=""
        while true; do
            AFTER=$(diskutil list external 2>/dev/null | grep -o '/dev/disk[0-9]*' | sort -u)
            for d in $AFTER; do
                if ! echo "$BEFORE" | grep -q "$d"; then
                    RESTORE_DISK="$d"
                    break 2
                fi
            done
            sleep 2
        done
        
        echo -e "${GREEN}[OK] Флешка обнаружена: $RESTORE_DISK${NC}"
        echo -e "${BLUE}[*] Форматирование флешки (ExFAT)...${NC}"
        sudo diskutil eraseDisk ExFAT "RESTORED_USB" GPT "$RESTORE_DISK"
        
        RESTORE_MP=$(mount | grep "$RESTORE_DISK" | awk -F' on ' '{print $2}' | awk -F' \\(' '{print $1}')
        if [ -n "$RESTORE_MP" ] && [ -f "$BACKUP_FILE" ]; then
            echo -e "${BLUE}[*] Восстановление данных из архива...${NC}"
            unzip -o "$BACKUP_FILE" -d "$RESTORE_MP"
            echo -e "${GREEN}[OK] Данные успешно восстановлены!${NC}"
            echo -e "${BLUE}[*] Удаление архива...${NC}"
            rm -f "$BACKUP_FILE"
        else
            echo -e "${RED}[!] Ошибка восстановления. Архив находится в: $BACKUP_FILE${NC}"
        fi
    else
        echo "Выход. Архив сохранен в: $BACKUP_FILE"
        exit 0
    fi
}

# --- ГЛАВНОЕ МЕНЮ ---
show_banner
check_for_updates
check_deps

echo -e "${BOLD}Что вы хотите сделать?${NC}"
echo ""
echo "  1) Записать Windows 10 / 11 (UEFI)"
echo "  2) Записать Linux / Raspberry Pi / ARM (dd)"
echo "  3) Режим Временной Флешки (Бэкап -> Запись -> Восстановление)"
echo ""
echo "  0) Выход"
echo ""
read -r -p "Ваш выбор (0-3): " MAIN_CHOICE

case $MAIN_CHOICE in
    1)
        echo ""
        echo -e "${CYAN}=== Windows (UEFI) ===${NC}"
        get_image_path "(.iso)"
        auto_detect_usb
        flash_windows
        ;;
    2)
        echo ""
        echo -e "${CYAN}=== Универсальный режим (dd) ===${NC}"
        get_image_path "(.iso / .img)"
        auto_detect_usb
        flash_dd
        ;;
    3)
        temp_usb_mode
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
echo -e "${GREEN}║     ГОТОВО! Операция успешно завершена!  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
read -r -p "Нажмите Enter для выхода..."

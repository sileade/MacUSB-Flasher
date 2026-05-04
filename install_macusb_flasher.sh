#!/bin/bash

# Установщик MacUSB Flasher v1.0
# Копирует утилиту на рабочий стол и настраивает права

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}НЕ запускайте установщик через sudo!${NC}"
    exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    Установка MacUSB Flasher v1.0         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

INSTALL_DIR="$HOME/Desktop/MacUSB_Flasher"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${YELLOW}Установка в: $INSTALL_DIR${NC}"
mkdir -p "$INSTALL_DIR"

echo -e "${YELLOW}Копирование файлов...${NC}"
cp "$SCRIPT_DIR/MacUSB_Flasher.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/MacUSB_Flasher.command" "$INSTALL_DIR/"

echo -e "${YELLOW}Установка прав...${NC}"
chmod +x "$INSTALL_DIR/MacUSB_Flasher.sh"
chmod +x "$INSTALL_DIR/MacUSB_Flasher.command"

# Снимаем карантин macOS
xattr -cr "$INSTALL_DIR" 2>/dev/null || true

echo ""
echo -e "${GREEN}Установка завершена!${NC}"
echo ""
echo "На рабочем столе создана папка MacUSB_Flasher."
echo "Для запуска дважды кликните MacUSB_Flasher.command"
echo ""
echo -e "${YELLOW}Если macOS заблокирует запуск:${NC}"
echo "  Системные настройки > Конфиденциальность > Всё равно открыть"
echo ""
read -r -p "Нажмите Enter для выхода..."

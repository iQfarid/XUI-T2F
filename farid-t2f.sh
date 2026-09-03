#!/bin/bash
set -euo pipefail

trap '' HUP

ensure_service_up_on_exit() {
    remove_temp_swap || true
    if ! systemctl is-active --quiet x-ui; then
        systemctl start x-ui >/dev/null 2>&1 || true
    fi
}
trap ensure_service_up_on_exit EXIT

clear

BIN="/usr/local/x-ui/x-ui"
REPO="https://github.com/MHSanaei/3x-ui.git"

BASE_DIR="/root/FARID-T2F"
BACKUP_DIR="$BASE_DIR/backups"
BASE_BACKUP_DIR="$BASE_DIR/base"
FACTOR_FILE="$BASE_DIR/current_factor"
INBOUND_FILTER_FILE="$BASE_DIR/inbound_filter"
APPLIED_INBOUND_FILTER_FILE="$BASE_DIR/applied_inbound_filter"

mkdir -p "$BASE_DIR" "$BACKUP_DIR" "$BASE_BACKUP_DIR"

INBOUND_FILTER=""
INBOUND_TAG=""

if [ -f "$INBOUND_FILTER_FILE" ]; then
    INBOUND_DATA="$(cat "$INBOUND_FILTER_FILE" 2>/dev/null || true)"
    INBOUND_FILTER="${INBOUND_DATA%%:*}"
    INBOUND_TAG="${INBOUND_DATA##*:}"
fi

LAST_BACKUP_DIR=""
VERSION=""
SRC_DIR=""
SRC=""
TEMP_SWAP_CREATED=0

if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_GREEN="\033[1;32m"
    C_YELLOW="\033[1;33m"
    C_RED="\033[1;31m"
    C_CYAN="\033[1;36m"
    C_MAGENTA="\033[1;35m"
    C_BOLD="\033[1m"
else
    C_RESET=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_CYAN=""
    C_MAGENTA=""
    C_BOLD=""
fi

line() {
    echo "================================================"
}

pause() {
    echo
    read -r -p " برای ادامه کلید Enter را بزنید..." _
}

error_exit() {
    echo
    echo -e "${C_RED}[!] $1${C_RESET}"
    echo
    exit 1
}

get_current_factor() {
    if [ -f "$FACTOR_FILE" ]; then
        cat "$FACTOR_FILE"
    else
        echo "1"
    fi
}

save_factor() {
    echo "$1" > "$FACTOR_FILE"
}

save_applied_inbound_filter() {
    echo "$INBOUND_FILTER" > "$APPLIED_INBOUND_FILTER_FILE"
}

show_header() {
    clear
    echo
    line
    echo -e "                 ${C_CYAN}${C_BOLD}FARID - X-UI T2F${C_RESET}"
    line
    echo
}

if [ "$(id -u)" -ne 0 ]; then
    error_exit "اجرای اسکریپت نیازمند دسترسی root است."
fi

check_panel() {
    [ -x "$BIN" ] || return 1
}

ensure_temp_swap() {
    local MEM_FREE
    MEM_FREE="$(free -m | awk '/^Mem:/{print $7}')"
    local SWAP_FREE
    SWAP_FREE="$(free -m | awk '/^Swap:/{print $4}')"
    
    if [ "$((MEM_FREE + SWAP_FREE))" -lt 1500 ]; then
        echo -e "${C_YELLOW}در حال ایجاد حافظه موقت (Swap)...${C_RESET}"
        if fallocate -l 2G /swapfile_farid_temp 2>/dev/null || dd if=/dev/zero of=/swapfile_farid_temp bs=1M count=2048 2>/dev/null; then
            chmod 600 /swapfile_farid_temp
            mkswap /swapfile_farid_temp >/dev/null 2>&1
            swapon /swapfile_farid_temp >/dev/null 2>&1
            TEMP_SWAP_CREATED=1
            echo -e "${C_GREEN}[+] حافظه موقت فعال شد.${C_RESET}"
        fi
    fi
}

remove_temp_swap() {
    if [ "$TEMP_SWAP_CREATED" -eq 1 ] && [ -f /swapfile_farid_temp ]; then
        swapoff /swapfile_farid_temp >/dev/null 2>&1 || true
        rm -f /swapfile_farid_temp
        TEMP_SWAP_CREATED=0
    fi
}

list_inbounds() {
    local DB QUERY RESULT
    install_sqlite3
    DB="$(find_database || true)"

    if [ -z "$DB" ] || [ ! -f "$DB" ]; then
        echo -e "${C_RED}[!] دیتابیس یافت نشد.${C_RESET}"
        return 1
    fi

    QUERY="SELECT id, tag, port, protocol FROM inbounds WHERE enable = 1 ORDER BY id;"
    RESULT="$(sqlite3 "$DB" "$QUERY" 2>/dev/null || true)"

    if [ -z "$RESULT" ]; then
        echo -e "${C_RED}[!] هیچ اینباند فعالی یافت نشد.${C_RESET}"
        return 1
    fi

    echo "$RESULT"
}

select_inbound_if_needed() {
    echo
    echo -e "  ${C_CYAN}تنظیمات اینباند${C_RESET}"
    echo

    if [ -n "$INBOUND_FILTER" ]; then
        echo -e "  اینباندهای فعال فعلی: ${C_MAGENTA}$INBOUND_TAG${C_RESET}"
        echo
    fi

    echo -e "  انتخاب اینباندهای هدف:"
    echo -e "  [1] همه اینباندها"

    if [ -n "$INBOUND_FILTER" ]; then
        echo -e "  [2] افزودن به انتخاب فعلی"
        echo -e "  [3] شروع از نو (جایگزینی)"
    else
        echo -e "  [2] انتخاب اینباندهای مشخص"
    fi

    echo
    read -r -p "  انتخاب شما: " MODE_CHOICE

    case "$MODE_CHOICE" in
        1)
            rm -f "$INBOUND_FILTER_FILE" "$APPLIED_INBOUND_FILTER_FILE"
            INBOUND_FILTER=""
            INBOUND_TAG=""
            echo -e "${C_GREEN}[+] اعمال روی تمامی اینباندها.${C_RESET}"
            ;;
        2)
            if [ -n "$INBOUND_FILTER" ]; then
                _select_new_inbounds "add"
            else
                _select_new_inbounds "replace"
            fi
            ;;
        3)
            if [ -n "$INBOUND_FILTER" ]; then
                _select_new_inbounds "replace"
            else
                echo -e "${C_RED}[!] انتخاب نامعتبر.${C_RESET}"
                return 1
            fi
            ;;
        *)
            echo -e "${C_RED}[!] انتخاب نامعتبر.${C_RESET}"
            return 1
            ;;
    esac
}

_select_new_inbounds() {
    local ACTION="$1"
    echo
    echo -e "  ${C_CYAN}اینباندهای فعال:${C_RESET}"
    echo

    local INBOUNDS
    INBOUNDS="$(list_inbounds)" || return 1

    local COUNTER=0
    local DB_IDS=()
    local DB_TAGS=()

    while IFS='|' read -r ID TAG PORT PROTOCOL; do
        [ -z "$ID" ] && continue
        COUNTER=$((COUNTER + 1))
        DB_IDS+=("$ID")
        DB_TAGS+=("$TAG")
        echo -e "  [$COUNTER] Tag: ${C_BOLD}$TAG${C_RESET} | Port: ${C_YELLOW}$PORT${C_RESET} | Protocol: $PROTOCOL"
    done <<< "$INBOUNDS"

    echo
    read -r -p "  انتخاب کنید (مثال: 1,2): " CHOICE_INPUT

    if [ -z "$CHOICE_INPUT" ]; then
        echo -e "${C_RED}[!] ورودی نامعتبر.${C_RESET}"
        return 1
    fi

    local NEW_IDS=()
    local NEW_TAGS=()
    local OLD_IFS="$IFS"
    IFS=','

    for CHOICE_NUM in $CHOICE_INPUT; do
        CHOICE_NUM="$(echo "$CHOICE_NUM" | tr -d ' ')"

        if ! [[ "$CHOICE_NUM" =~ ^[0-9]+$ ]] || [ "$CHOICE_NUM" -lt 1 ] || [ "$CHOICE_NUM" -gt "$COUNTER" ]; then
            IFS="$OLD_IFS"
            echo -e "${C_RED}[!] گزینه نامعتبر: $CHOICE_NUM${C_RESET}"
            return 1
        fi

        local INDEX=$((CHOICE_NUM - 1))
        NEW_IDS+=("${DB_IDS[$INDEX]}")
        NEW_TAGS+=("${DB_TAGS[$INDEX]}")
    done
    IFS="$OLD_IFS"

    local ALL_IDS_STR=""
    local ALL_TAGS_STR=""

    if [ "$ACTION" = "add" ] && [ -n "$INBOUND_FILTER" ]; then
        ALL_IDS_STR="$INBOUND_FILTER,$(printf "%s," "${NEW_IDS[@]}")"
        ALL_TAGS_STR="$INBOUND_TAG, $(printf "%s, " "${NEW_TAGS[@]}")"
    else
        ALL_IDS_STR="$(printf "%s," "${NEW_IDS[@]}")"
        ALL_TAGS_STR="$(printf "%s, " "${NEW_TAGS[@]}")"
    fi

    local UNIQUE_IDS UNIQUE_TAGS
    UNIQUE_IDS="$(echo "$ALL_IDS_STR" | tr ',' '\n' | sed '/^$/d' | tr -d ' ' | sort -u | tr '\n' ',' | sed 's/,$//')"
    UNIQUE_TAGS="$(echo "$ALL_TAGS_STR" | tr ',' '\n' | sed '/^$/d' | sed 's/^ *//;s/ *$//' | sort -u | tr '\n' ', ' | sed 's/, $//')"

    INBOUND_FILTER="$UNIQUE_IDS"
    INBOUND_TAG="$UNIQUE_TAGS"
    echo "$UNIQUE_IDS:$UNIQUE_TAGS" > "$INBOUND_FILTER_FILE"
    echo -e "${C_GREEN}[+] انتخاب شد: $UNIQUE_TAGS${C_RESET}"
}

detect_installed_version() {
    local RAW="" FLAG

    for FLAG in "-v" "--version" "version" "-version"; do
        RAW="$(timeout 3 "$BIN" "$FLAG" 2>/dev/null | head -n1 || true)"
        [ -n "$RAW" ] && break
    done

    VERSION="$(printf '%s' "$RAW" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"

    if [ -n "$VERSION" ] && [[ "$VERSION" != v* ]]; then
        VERSION="v$VERSION"
    fi

    if [ -z "$VERSION" ]; then
        echo
        echo -e "${C_YELLOW}[!] نسخه پنل به صورت خودکار تشخیص داده نشد.${C_RESET}"
        read -r -p "  نسخه را وارد کنید (مثال: v2.8.11): " VERSION
        [ -n "$VERSION" ] || error_exit "ورودی نسخه الزامی است."
        [[ "$VERSION" == v* ]] || VERSION="v$VERSION"
    fi

    SRC_DIR="/root/3x-ui-$VERSION"
    SRC="$SRC_DIR/web/service/inbound.go"
}

install_git() {
    command -v git >/dev/null 2>&1 && return
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y git
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git
    fi
}

install_sqlite3() {
    command -v sqlite3 >/dev/null 2>&1 && return
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sqlite3
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y sqlite
    elif command -v yum >/dev/null 2>&1; then
        yum install -y sqlite
    fi
}

install_gcc() {
    command -v gcc >/dev/null 2>&1 && return
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y gcc
    elif command -v yum >/dev/null 2>&1; then
        yum install -y gcc
    fi
}

install_go() {
    local REQUIRED="$1" ARCH="$(uname -m)" GO_ARCH=""

    case "$ARCH" in
        x86_64) GO_ARCH="amd64" ;;
        aarch64|arm64) GO_ARCH="arm64" ;;
        armv6l|armv7l) GO_ARCH="armv6l" ;;
        *) error_exit "معماری $ARCH پشتیبانی نمی‌شود." ;;
    esac

    local TMP="/tmp/go${REQUIRED}.linux-${GO_ARCH}.tar.gz"
    local URL="https://go.dev/dl/go${REQUIRED}.linux-${GO_ARCH}.tar.gz"

    echo -e "${C_CYAN}در حال دانلود و نصب Go ${REQUIRED}...${C_RESET}"
    if curl -sL -o "$TMP" "$URL" || wget -q -O "$TMP" "$URL"; then
        rm -rf /usr/local/go
        tar -C /usr/local -xzf "$TMP"
        rm -f "$TMP"
        export PATH="/usr/local/go/bin:$PATH"
    else
        error_exit "دانلود Go با خطا مواجه شد."
    fi
}

check_go() {
    local REQUIRED_GO="1.20"
    if [ -f "$SRC_DIR/go.mod" ]; then
        REQUIRED_GO="$(awk '$1 == "go" { print $2; exit }' "$SRC_DIR/go.mod" || echo "1.20")"
    fi

    local GO=""
    if [ -x /usr/local/go/bin/go ]; then
        GO="/usr/local/go/bin/go"
    elif command -v go >/dev/null 2>&1; then
        GO="$(command -v go)"
    fi

    local INSTALLED_GO=""
    if [ -n "$GO" ]; then
        INSTALLED_GO="$("$GO" version | sed -nE 's/.*go([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')"
    fi

    if [ -z "$INSTALLED_GO" ] || [ "$(printf '%s\n' "$REQUIRED_GO" "$INSTALLED_GO" | sort -V | head -n1)" != "$REQUIRED_GO" ]; then
        install_go "$REQUIRED_GO"
    fi

    export PATH="/usr/local/go/bin:$PATH"
}

check_source() {
    if [ -f "$SRC" ]; then
        return 0
    fi

    install_git
    rm -rf "$SRC_DIR"

    git clone --depth 1 --branch "$VERSION" "$REPO" "$SRC_DIR" || error_exit "دانلود سورس با خطا مواجه شد."

    if [ -f "$SRC_DIR/web/service/inbound.go" ]; then
        SRC="$SRC_DIR/web/service/inbound.go"
    else
        error_exit "ساختار سورس کد در نسخه $VERSION پشتیبانی نمی‌شود."
    fi
}

find_database() {
    if [ -f "/etc/x-ui/x-ui.db" ]; then echo "/etc/x-ui/x-ui.db"; return 0; fi
    if [ -f "/usr/local/x-ui/x-ui.db" ]; then echo "/usr/local/x-ui/x-ui.db"; return 0; fi
    find /usr/local/x-ui /etc/x-ui "$SRC_DIR" -maxdepth 5 -type f \( -name "x-ui.db" -o -name "*.sqlite" \) 2>/dev/null | head -n1
}

restore_source_from_base() {
    if [ ! -f "$BASE_BACKUP_DIR/inbound.go" ]; then
        create_base_backup
    fi
    cp -a "$BASE_BACKUP_DIR/inbound.go" "$SRC"
}

remove_farid_blocks() {
    python3 - "$SRC" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
if not p.exists():
    sys.exit(0)

text = p.read_text()
START = "/* QFARID_T2F_START */"
END   = "/* QFARID_T2F_END */"

lines = text.splitlines(keepends=True)
clean = []
inside = False

for line in lines:
    if START in line:
        inside = True
        continue
    if END in line:
        inside = False
        continue
    if not inside:
        clean.append(line)

p.write_text("".join(clean))
PY
}

create_backup() {
    local STAMP="$(date +%Y%m%d-%H%M%S)"
    local DIR="$BACKUP_DIR/$STAMP"
    mkdir -p "$DIR"

    [ -f "$SRC" ] && cp -a "$SRC" "$DIR/inbound.go"
    [ -f "$BIN" ] && cp -a "$BIN" "$DIR/x-ui"

    local DB="$(find_database || true)"
    [ -n "$DB" ] && [ -f "$DB" ] && cp -a "$DB" "$DIR/x-ui.db"
    LAST_BACKUP_DIR="$DIR"
}

create_base_backup() {
    local BASE_VERSION=""
    [ -f "$BASE_BACKUP_DIR/version" ] && BASE_VERSION="$(cat "$BASE_BACKUP_DIR/version" 2>/dev/null || true)"

    if [ -n "$BASE_VERSION" ] && [ "$BASE_VERSION" != "$VERSION" ]; then
        rm -rf "$BASE_BACKUP_DIR"
        mkdir -p "$BASE_BACKUP_DIR"
    fi

    if [ -f "$BASE_BACKUP_DIR/x-ui" ] && [ -f "$BASE_BACKUP_DIR/inbound.go" ]; then
        return 0
    fi

    remove_farid_blocks

    local DB="$(find_database || true)"
    [ -z "$DB" ] && error_exit "دیتابیس x-ui.db یافت نشد."

    cp -a "$BIN" "$BASE_BACKUP_DIR/x-ui"
    cp -a "$SRC" "$BASE_BACKUP_DIR/inbound.go"
    cp -a "$DB" "$BASE_BACKUP_DIR/x-ui.db"

    echo "$VERSION" > "$BASE_BACKUP_DIR/version"
    [ ! -f "$FACTOR_FILE" ] && save_factor "1"
}

apply_factor() {
    local FACTOR="$1"
    create_backup
    restore_source_from_base

    python3 - "$SRC" "$FACTOR" "$INBOUND_FILTER" "$INBOUND_TAG" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
factor = int(sys.argv[2])
inbound_filter = sys.argv[3] if len(sys.argv) > 3 else ""
inbound_tag = sys.argv[4] if len(sys.argv) > 4 else ""

START = "/* QFARID_T2F_START */"
END   = "/* QFARID_T2F_END */"

lines = p.read_text().splitlines(keepends=True)

clean = []
inside = False
for line in lines:
    if START in line:
        inside = True
        continue
    if END in line:
        inside = False
        continue
    if not inside:
        clean.append(line)
lines = clean

email_index = None
for i, line in enumerate(lines):
    if "dbClientTraffics[dbTraffic_index].Email" in line and "traffics[traffic_index].Email" in line:
        email_index = i
        break

if email_index is None:
    print("ERROR: ساختار کد شناسایی نشد.")
    sys.exit(1)

anchor = None
for i in range(email_index + 1, min(email_index + 40, len(lines))):
    if "Up +=" in lines[i] or "onlineUsers" in lines[i]:
        anchor = i
        break

if anchor is None:
    anchor = email_index + 1

middle = []
for i in range(email_index + 1, anchor):
    s = lines[i]
    if any(k in s for k in ["Up +=", "Down +=", "AllTime +="]):
        continue
    middle.append(s)

indent = "                "
UP = "traffics[traffic_index].Up"
DOWN = "traffics[traffic_index].Down"
TOTAL = "(traffics[traffic_index].Up + traffics[traffic_index].Down)"

if inbound_filter:
    ids = [x.strip() for x in inbound_filter.split(',') if x.strip()]
    condition = " || ".join([f"dbClientTraffics[dbTraffic_index].InboundId == {x}" for x in ids])
else:
    condition = ""

mult = f" * {factor}" if factor > 1 else ""

new = [f"{indent}{START}\n"]
if condition:
    new.append(f"{indent}if {condition} {{\n")
    ind = indent + "    "
else:
    ind = indent

new.append(f"{ind}dbClientTraffics[dbTraffic_index].Up += {UP}{mult}\n")
new.append(f"{ind}dbClientTraffics[dbTraffic_index].Down += {DOWN}{mult}\n")
new.append(f"{ind}dbClientTraffics[dbTraffic_index].AllTime += {TOTAL}{mult}\n")

if condition:
    new.append(f"{indent}}}\n")

new.append(f"{indent}{END}\n")

lines = lines[:email_index + 1] + middle + new + lines[anchor:]
p.write_text("".join(lines))
PY

    echo -e "${C_GREEN}[+] ضریب $FACTOR اعمال شد.${C_RESET}"
}

rollback_source() {
    if [ -f "$BASE_BACKUP_DIR/inbound.go" ]; then
        cp -a "$BASE_BACKUP_DIR/inbound.go" "$SRC"
    fi
}

build_panel() {
    check_source
    check_go
    install_gcc
    ensure_temp_swap

    cd "$SRC_DIR"
    export CGO_ENABLED=1

    local NEW="/tmp/x-ui-FARID-$$"
    local LOG="/tmp/FARID-build-$$.log"

    echo -e "${C_YELLOW}در حال ساخت و آماده‌سازی پنل...${C_RESET}"
    echo -e "${C_YELLOW}(این مرحله ممکن است چند دقیقه طول بکشد، لطفاً صبور باشید)${C_RESET}"

    if ! go build -o "$NEW" . >"$LOG" 2>&1; then
        echo -e "${C_RED}[!] ساخت پنل با خطا مواجه شد.${C_RESET}"
        tail -n 25 "$LOG"
        rm -f "$NEW"
        rollback_source
        remove_temp_swap
        return 1
    fi

    systemctl stop x-ui || true

    if ! install -m 0755 "$NEW" "$BIN"; then
        rm -f "$NEW"
        rollback_source
        remove_temp_swap
        systemctl restart x-ui || true
        return 1
    fi

    systemctl daemon-reload
    systemctl restart x-ui || true
    sleep 3

    remove_temp_swap

    if systemctl is-active --quiet x-ui; then
        rm -f "$NEW"
        echo -e "${C_GREEN}[+] پنل بروزرسانی شد و فعال است.${C_RESET}"
        return 0
    else
        echo -e "${C_RED}[!] پنل پس از بروزرسانی روشن نشد.${C_RESET}"
        rollback_source
        systemctl restart x-ui || true
        rm -f "$NEW"
        return 1
    fi
}

restore_backup() {
    show_header
    echo -e "  ${C_CYAN}بازگشت به تنظیمات اولیه${C_RESET}"
    echo
    read -r -p "  آیا از حذف ضریب و بازگشت مطمین هستید؟ [y/N]: " CONFIRM

    case "$CONFIRM" in
        y|Y|yes|YES)
            systemctl stop x-ui || true
            [ -f "$BASE_BACKUP_DIR/x-ui" ] && cp -a "$BASE_BACKUP_DIR/x-ui" "$BIN"
            [ -f "$BASE_BACKUP_DIR/inbound.go" ] && cp -a "$BASE_BACKUP_DIR/inbound.go" "$SRC"

            rm -f "$INBOUND_FILTER_FILE" "$APPLIED_INBOUND_FILTER_FILE"
            INBOUND_FILTER=""
            INBOUND_TAG=""
            save_factor "1"

            systemctl daemon-reload
            systemctl restart x-ui || true
            echo -e "${C_GREEN}[+] تمامی ضرایب حذف شدند.${C_RESET}"
            ;;
        *)
            echo "  لغو شد."
            ;;
    esac
    pause
}

factor_menu() {
    select_inbound_if_needed || return

    while true; do
        show_header
        CURRENT="$(get_current_factor)"
        echo -e "  ضریب فعلی: ${C_YELLOW}$CURRENT${C_RESET}"
        [ -n "$INBOUND_FILTER" ] && echo -e "  اینباندها : ${C_MAGENTA}$INBOUND_TAG${C_RESET}"
        echo
        line
        echo -e "  [1] ضریب 1 (عادی)"
        echo -e "  [2] ضریب 2 (مصرف 2 برابر)"
        echo -e "  [3] ضریب 3 (مصرف 3 برابر)"
        echo -e "  [4] ضریب 4 (مصرف 4 برابر)"
        echo -e "  [0] بازگشت"
        line
        read -r -p "  انتخاب کنید [0-4]: " CHOICE

        case "$CHOICE" in
            1|2|3|4) NEW_FACTOR="$CHOICE" ;;
            0) return ;;
            *) continue ;;
        esac

        if apply_factor "$NEW_FACTOR"; then
            if build_panel; then
                save_factor "$NEW_FACTOR"
                save_applied_inbound_filter
                pause
                return
            fi
        fi
        pause
    done
}

show_status() {
    show_header
    echo -e "  وضعیت پنل : $(systemctl is-active --quiet x-ui && echo -e "${C_GREEN}فعال${C_RESET}" || echo -e "${C_RED}غیرفعال${C_RESET}")"
    echo -e "  ضریب فعلی  : ${C_YELLOW}$(get_current_factor)${C_RESET}"
    if [ -n "$INBOUND_FILTER" ]; then
        echo -e "  اینباندها   : ${C_MAGENTA}$INBOUND_TAG${C_RESET}"
    else
        echo -e "  اینباندها   : ${C_GREEN}همه اینباندها${C_RESET}"
    fi
    pause
}

main_menu() {
    while true; do
        show_header
        CURRENT="$(get_current_factor)"
        
        echo -e "  ضریب فعلی : ${C_YELLOW}${C_BOLD}$CURRENT${C_RESET}"
        if [ -n "$INBOUND_FILTER" ]; then
            echo -e "  اینباندها : ${C_MAGENTA}$INBOUND_TAG${C_RESET}"
        fi
        
        line
        echo -e "  [1] انتخاب یا تغییر ضریب"
        echo -e "  [2] حذف ضریب و بازگشت به حالت اولیه"
        echo -e "  [3] بررسی وضعیت پنل"
        echo
        echo -e "  [0] خروج"
        line
        read -r -p "  انتخاب شما [0-3]: " MENU

        case "$MENU" in
            1) factor_menu ;;
            2) restore_backup ;;
            3) show_status ;;
            0) clear; exit 0 ;;
            *) continue ;;
        esac
    done
}

check_panel || error_exit "پنل 3x-ui یافت نشد."
detect_installed_version
check_source || error_exit "سورس کد یافت نشد."
create_base_backup
main_menu

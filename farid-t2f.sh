#!/bin/bash
set -euo pipefail

# اگر همین ارتباط SSH از مسیر خودِ پنل/تونل رد بشه، وقتی سرویس
# برای Build موقتاً stop می‌شه ممکنه ترمینال قطع بشه. با نادیده
# گرفتن SIGHUP، اسکریپت با قطع ترمینال کشته نمی‌شه و کارش
# (نصب باینری جدید + استارت دوباره‌ی سرویس) رو تا آخر ادامه می‌ده.
trap '' HUP

# ضامن ایمنی: با هر جور خروج از اسکریپت، اگه سرویس x-ui به هر
# دلیلی متوقف مونده باشه، خودکار دوباره استارت می‌شه.
ensure_service_up_on_exit() {
    if ! systemctl is-active --quiet x-ui; then
        systemctl start x-ui >/dev/null 2>&1 || true
    fi
}
trap ensure_service_up_on_exit EXIT

# ============================================================
#                       X-UI T2F
#      ضریب فقط روی ترافیک جدید اعمال می‌شود
#      ضرایب مجاز: 1 / 2 / 3 / 4
# ============================================================

clear

BIN="/usr/local/x-ui/x-ui"
REPO="https://github.com/MHSanaei/3x-ui.git"

BASE_DIR="/root/FARID-T2F"
BACKUP_DIR="$BASE_DIR/backups"
BASE_BACKUP_DIR="$BASE_DIR/base"
FACTOR_FILE="$BASE_DIR/current_factor"

mkdir -p "$BASE_DIR" "$BACKUP_DIR" "$BASE_BACKUP_DIR"

LAST_BACKUP_DIR=""
VERSION=""
SRC_DIR=""
SRC=""

# ============================================================
# COLORS
# ============================================================

if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_GREEN="\033[1;32m"
    C_YELLOW="\033[1;33m"
    C_RED="\033[1;31m"
    C_CYAN="\033[1;36m"
    C_BLUE="\033[1;34m"
    C_WHITE="\033[1;97m"
    C_GRAY="\033[0;37m"
else
    C_RESET=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_CYAN=""
    C_BLUE=""
    C_WHITE=""
    C_GRAY=""
fi

# ============================================================
# FUNCTIONS
# ============================================================

line() {
    printf '%s\n' "════════════════════════════════════════════════"
}

pause() {
    echo
    read -r -p "  برای ادامه Enter بزنید..." _
}

error_exit() {
    echo
    echo -e "${C_RED}  ✗ $1${C_RESET}"
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

show_header() {
    clear
    echo
    line
    printf "                         "
    echo -e "${C_CYAN}${C_WHITE}FARID${C_RESET}"
    printf "                   "
    echo -e "${C_WHITE}X-UI T2F${C_RESET}"
    line
    echo
}

# ============================================================
# ROOT
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    error_exit "اسکریپت باید با دسترسی root اجرا شود."
fi

# ============================================================
# CHECK PANEL
# ============================================================

check_panel() {
    [ -x "$BIN" ] || return 1
}

# ============================================================
# DETECT INSTALLED 3x-ui VERSION
# ============================================================
# اسکریپت دیگه به یک نسخه‌ی ثابت (مثل v2.8.11) قفل نیست.
# نسخه‌ی واقعاً نصب‌شده روی سرور رو تشخیص می‌ده و همون تگ رو
# از گیت‌هاب می‌گیره، تا سورس همیشه با باینری در حال اجرا هم‌خوان بمونه.

detect_installed_version() {

    local RAW=""
    local FLAG

    for FLAG in "-v" "--version" "version" "-version"; do
        RAW="$(timeout 3 "$BIN" "$FLAG" 2>/dev/null | head -n1 || true)"
        [ -n "$RAW" ] && break
    done

    VERSION="$(
        printf '%s' "$RAW" |
        grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' |
        head -n1
    )"

    if [ -n "$VERSION" ] && [[ "$VERSION" != v* ]]; then
        VERSION="v$VERSION"
    fi

    if [ -z "$VERSION" ]; then

        echo
        echo -e "${C_YELLOW}⚠ نسخه‌ی نصب‌شده‌ی 3x-ui به‌صورت خودکار تشخیص داده نشد.${C_RESET}"
        echo "  می‌توانید نسخه را از منوی مدیریتی پنل (دستور x-ui، گزینه‌ی وضعیت/Check Status)"
        echo "  یا از صفحه‌ی ریلیزهای گیت‌هاب پیدا کنید."
        echo

        read -r -p "  نسخه نصب‌شده را وارد کنید (مثال: v2.8.11): " VERSION

        [ -n "$VERSION" ] || error_exit "بدون مشخص‌شدن نسخه امکان ادامه نیست."

        [[ "$VERSION" == v* ]] || VERSION="v$VERSION"
    fi

    SRC_DIR="/root/3x-ui-$VERSION"
    SRC="$SRC_DIR/web/service/inbound.go"
}


# ============================================================
# INSTALL DEPENDENCIES
# ============================================================

install_git() {
    command -v git >/dev/null 2>&1 && return

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y git
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git
    else
        error_exit "package manager پیدا نشد."
    fi
}

install_gcc() {
    command -v gcc >/dev/null 2>&1 && return

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y gcc
    elif command -v yum >/dev/null 2>&1; then
        yum install -y gcc
    else
        error_exit "package manager پیدا نشد."
    fi
}

install_go() {
    local REQUIRED="$1"
    local ARCH
    local GO_ARCH
    local FILE
    local URL
    local TMP

    ARCH="$(uname -m)"

    case "$ARCH" in
        x86_64) GO_ARCH="amd64" ;;
        aarch64|arm64) GO_ARCH="arm64" ;;
        armv6l|armv7l) GO_ARCH="armv6l" ;;
        *) error_exit "معماری $ARCH پشتیبانی نمی‌شود." ;;
    esac

    FILE="go${REQUIRED}.linux-${GO_ARCH}.tar.gz"
    URL="https://go.dev/dl/${FILE}"
    TMP="/tmp/${FILE}"

    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$TMP"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TMP" "$URL"
    else
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl
            curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$TMP"
        else
            error_exit "curl یا wget پیدا نشد."
        fi
    fi

    [ -s "$TMP" ] || error_exit "دانلود Go ناموفق بود."

    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$TMP"
    rm -f "$TMP"

    export PATH="/usr/local/go/bin:$PATH"

    [ -x /usr/local/go/bin/go ] ||
        error_exit "نصب Go ناموفق بود."
}

check_go() {
    local REQUIRED_GO
    local INSTALLED_GO=""

    REQUIRED_GO="$(
        awk '$1 == "go" { print $2; exit }' "$SRC_DIR/go.mod"
    )"

    [ -n "$REQUIRED_GO" ] ||
        error_exit "نسخه Go از go.mod پیدا نشد."

    if [ -x /usr/local/go/bin/go ]; then
        GO="/usr/local/go/bin/go"
    elif command -v go >/dev/null 2>&1; then
        GO="$(command -v go)"
    else
        GO=""
    fi

    if [ -n "$GO" ]; then
        INSTALLED_GO="$(
            "$GO" version |
            sed -nE 's/.*go([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p'
        )"
    fi

    if [ -z "$INSTALLED_GO" ]; then
        install_go "$REQUIRED_GO"
        GO="/usr/local/go/bin/go"
    elif [ "$(printf '%s\n' "$REQUIRED_GO" "$INSTALLED_GO" | sort -V | head -n1)" != "$REQUIRED_GO" ]; then
        install_go "$REQUIRED_GO"
        GO="/usr/local/go/bin/go"
    fi

    export PATH="/usr/local/go/bin:$PATH"
}

# ============================================================
# SOURCE
# ============================================================

check_source() {
    if [ -f "$SRC" ]; then
        return 0
    fi

    install_git

    rm -rf "$SRC_DIR"

    git clone \
        --depth 1 \
        --branch "$VERSION" \
        "$REPO" \
        "$SRC_DIR" \
        || error_exit "دریافت سورس ناموفق بود."

    [ -f "$SRC" ]
}

# ============================================================
# DATABASE
# ============================================================

find_database() {
    if [ -f "/etc/x-ui/x-ui.db" ]; then
        echo "/etc/x-ui/x-ui.db"
        return 0
    fi

    if [ -f "/usr/local/x-ui/x-ui.db" ]; then
        echo "/usr/local/x-ui/x-ui.db"
        return 0
    fi

    find \
        /usr/local/x-ui \
        /etc/x-ui \
        "$SRC_DIR" \
        -maxdepth 5 \
        -type f \
        \( -name "x-ui.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
        2>/dev/null |
        head -n1
}

# ============================================================
# RESTORE SOURCE FROM BASE
# ============================================================

restore_source_from_base() {

    [ -f "$BASE_BACKUP_DIR/inbound.go" ] ||
        error_exit "نسخه پایه inbound.go پیدا نشد."

    cp -a "$BASE_BACKUP_DIR/inbound.go" "$SRC"

    echo
    echo -e "${C_GREEN}✓ inbound.go از نسخه پایه بازگردانی شد.${C_RESET}"
}

# ============================================================
# REMOVE FARID BLOCKS
# ============================================================

remove_farid_blocks() {
    python3 - "$SRC" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
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

# ============================================================
# BACKUP
# ============================================================

create_backup() {
    local STAMP
    local DIR
    local DB

    STAMP="$(date +%Y%m%d-%H%M%S-%N)"
    DIR="$BACKUP_DIR/$STAMP"

    mkdir -p "$DIR"

    [ -f "$SRC" ] && cp -a "$SRC" "$DIR/inbound.go"
    [ -f "$BIN" ] && cp -a "$BIN" "$DIR/x-ui"

    DB="$(find_database || true)"

    if [ -n "$DB" ] && [ -f "$DB" ]; then
        cp -a "$DB" "$DIR/x-ui.db"
    fi

    LAST_BACKUP_DIR="$DIR"
}

# ============================================================
# CREATE BASE AUTOMATICALLY
# ============================================================

create_base_backup() {

    local DB
    local BASE_VERSION=""

    if [ -f "$BASE_BACKUP_DIR/version" ]; then
        BASE_VERSION="$(cat "$BASE_BACKUP_DIR/version" 2>/dev/null || true)"
    fi

    if [ -n "$BASE_VERSION" ] && [ "$BASE_VERSION" != "$VERSION" ]; then

        echo
        echo -e "${C_YELLOW}⚠ نسخه‌ی نصب‌شده تغییر کرده است (نسخه‌ی پایه: $BASE_VERSION، الان: $VERSION).${C_RESET}"
        echo -e "${C_YELLOW}  نسخه‌ی پایه‌ی قدیمی دیگر قابل‌استفاده نیست و دوباره ساخته می‌شود.${C_RESET}"

        rm -rf "$BASE_BACKUP_DIR"
        mkdir -p "$BASE_BACKUP_DIR"
    fi

    if [ -f "$BASE_BACKUP_DIR/x-ui" ] &&
       [ -f "$BASE_BACKUP_DIR/inbound.go" ] &&
       [ -f "$BASE_BACKUP_DIR/x-ui.db" ]; then

        return 0
    fi

    echo
    echo "  ایجاد نسخه پایه..."
    echo

    # فقط FARID از سورس فعلی حذف می‌شود.
    # دیتابیس کاربر دست‌نخورده باقی می‌ماند.

    remove_farid_blocks

    DB="$(find_database || true)"

    if [ -z "$DB" ] || [ ! -f "$DB" ]; then
        error_exit "x-ui.db پیدا نشد."
    fi

    cp -a "$BIN" "$BASE_BACKUP_DIR/x-ui"
    cp -a "$SRC" "$BASE_BACKUP_DIR/inbound.go"
    cp -a "$DB" "$BASE_BACKUP_DIR/x-ui.db"

    echo "$VERSION" > "$BASE_BACKUP_DIR/version"
    date '+%Y-%m-%d %H:%M:%S' > "$BASE_BACKUP_DIR/created_at"

    if [ ! -f "$FACTOR_FILE" ]; then
        save_factor "1"
    fi

    echo -e "${C_GREEN}  ✓ نسخه پایه ذخیره شد.${C_RESET}"
}

# ============================================================
# APPLY FACTOR
# ============================================================

apply_factor() {

    local FACTOR="$1"

    case "$FACTOR" in
        1|2|3|4)
            NUM="$FACTOR"
            ;;
        *)
            error_exit "ضریب نامعتبر است. فقط 1 تا 4 مجاز است."
            ;;
    esac

    # --------------------------------------------------------
    # بکاپ وضعیت فعلی
    # --------------------------------------------------------

    create_backup

    # --------------------------------------------------------
    # مهم:
    # همیشه قبل از اعمال ضریب، سورس مستقیماً از BASE برمی‌گردد.
    # بنابراین هیچ ضریب قبلی روی ضریب جدید سوار نمی‌شود.
    # --------------------------------------------------------

    restore_source_from_base

    # --------------------------------------------------------
    # اعمال ضریب
    # --------------------------------------------------------

    python3 - "$SRC" "$NUM" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
factor = int(sys.argv[2])

START = "/* QFARID_T2F_START */"
END   = "/* QFARID_T2F_END */"

text = p.read_text()

lines = text.splitlines(keepends=True)

# ------------------------------------------------------------
# حذف هر FARID احتمالی
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# پیدا کردن addClientTraffic
# ------------------------------------------------------------

email_index = None

for i, line in enumerate(lines):

    if (
        "dbClientTraffics[dbTraffic_index].Email" in line
        and "traffics[traffic_index].Email" in line
    ):
        email_index = i
        break

if email_index is None:
    print("ERROR: addClientTraffic پیدا نشد.")
    sys.exit(1)

# ------------------------------------------------------------
# پیدا کردن anchor
# ------------------------------------------------------------

anchor = None

for i in range(email_index + 1, min(email_index + 40, len(lines))):

    if "// Add user in onlineUsers array on traffic" in lines[i]:
        anchor = i
        break

if anchor is None:
    print("ERROR: محل ثبت ترافیک پیدا نشد.")
    sys.exit(1)

# ------------------------------------------------------------
# حذف خطوط قبلی ثبت ترافیک
# ------------------------------------------------------------

middle = []

for i in range(email_index + 1, anchor):

    s = lines[i]

    if (
        "dbClientTraffics[dbTraffic_index].Up +=" in s
        or "dbClientTraffics[dbTraffic_index].Down +=" in s
        or "dbClientTraffics[dbTraffic_index].AllTime +=" in s
    ):
        continue

    middle.append(lines[i])

# ------------------------------------------------------------
# indentation
# ------------------------------------------------------------

indent = "                                "

for s in lines[email_index + 1:anchor]:

    if s.strip():
        indent = s[:len(s) - len(s.lstrip())]
        break

UP = "traffics[traffic_index].Up"
DOWN = "traffics[traffic_index].Down"
TOTAL = "(traffics[traffic_index].Up + traffics[traffic_index].Down)"

# ------------------------------------------------------------
# ضریب 1 = حالت اصلی
# ------------------------------------------------------------

if factor == 1:

    new = [
        f"{indent}{START}\n",
        f"{indent}dbClientTraffics[dbTraffic_index].Up += {UP}\n",
        f"{indent}dbClientTraffics[dbTraffic_index].Down += {DOWN}\n",
        f"{indent}dbClientTraffics[dbTraffic_index].AllTime += {TOTAL}\n",
        f"{indent}{END}\n",
    ]

else:

    new = [
        f"{indent}{START}\n",
        f"{indent}dbClientTraffics[dbTraffic_index].Up += {UP} * {factor}\n",
        f"{indent}dbClientTraffics[dbTraffic_index].Down += {DOWN} * {factor}\n",
        f"{indent}dbClientTraffics[dbTraffic_index].AllTime += {TOTAL} * {factor}\n",
        f"{indent}{END}\n",
    ]

lines = (
    lines[:email_index + 1]
    + middle
    + new
    + lines[anchor:]
)

p.write_text("".join(lines))

print(f"✓ ضریب {factor} روی فقط ترافیک جدید اعمال شد.")
PY

    # --------------------------------------------------------
    # کنترل نهایی
    # --------------------------------------------------------

    grep -q \
        "dbClientTraffics\[dbTraffic_index\]\.Up +=" \
        "$SRC" ||
        error_exit "کد Up پیدا نشد."

    grep -q \
        "dbClientTraffics\[dbTraffic_index\]\.Down +=" \
        "$SRC" ||
        error_exit "کد Down پیدا نشد."

    grep -q \
        "dbClientTraffics\[dbTraffic_index\]\.AllTime +=" \
        "$SRC" ||
        error_exit "کد AllTime پیدا نشد."

    # --------------------------------------------------------
    # تشخیص علت احتمالی نادقیق بودن ضریب:
    # ۱) اگر بیش از یک بلوک انباشت ترافیک در همین فایل باشد،
    #    اسکریپت فقط اولین مورد را پچ می‌کند و بقیه با ضریب ۱
    #    باقی می‌مانند -> نتیجه نهایی بین ۱ برابر و N برابر می‌شود.
    # ۲) اگر فایل دیگری در سورس هم روی همین فیلدها بنویسد
    #    (مثلاً sync چند-نود / global traffic)، آن مسیر اصلاً
    #    پچ نمی‌شود.
    # --------------------------------------------------------

    local DUP_COUNT
    DUP_COUNT="$(grep -c 'dbClientTraffics\[dbTraffic_index\]\.Email' "$SRC" || true)"

    if [ "${DUP_COUNT:-0}" -gt 1 ]; then
        echo
        echo -e "${C_YELLOW}⚠ هشدار: $DUP_COUNT مکان مشابه در inbound.go پیدا شد.${C_RESET}"
        echo -e "${C_YELLOW}  فقط اولین مورد پچ می‌شود؛ اگر ضریب نادقیق است این می‌تواند دلیلش باشد.${C_RESET}"
    fi

    local OTHER_WRITERS
    OTHER_WRITERS="$(
        grep -rl 'dbClientTraffics\[.*\]\.\(Up\|Down\|AllTime\) +=' "$SRC_DIR" \
            --include="*.go" 2>/dev/null | grep -v -F "$SRC" || true
    )"

    if [ -n "$OTHER_WRITERS" ]; then
        echo
        echo -e "${C_YELLOW}⚠ هشدار: فایل(های) دیگری هم به همین فیلدهای ترافیک می‌نویسند و پچ نشده‌اند:${C_RESET}"
        echo "$OTHER_WRITERS" | sed 's/^/    /'
        echo -e "${C_YELLOW}  اگر ضریب انتخابی دقیق اعمال نمی‌شود، احتمالاً یکی از این مسیرهاست.${C_RESET}"
    fi

    echo
    echo -e "${C_GREEN}✓ کد ضریب $FACTOR آماده Build است.${C_RESET}"
}

# ============================================================
# ROLLBACK SOURCE AFTER FAILED BUILD
# ============================================================

rollback_source() {

    # در صورت شکست، مستقیماً نسخه پایه برگردانده می‌شود.

    if [ -f "$BASE_BACKUP_DIR/inbound.go" ]; then

        cp -a "$BASE_BACKUP_DIR/inbound.go" "$SRC"

        echo
        echo -e "${C_YELLOW}✓ سورس به نسخه پایه بازگردانده شد.${C_RESET}"

    elif [ -n "$LAST_BACKUP_DIR" ] &&
         [ -f "$LAST_BACKUP_DIR/inbound.go" ]; then

        cp -a "$LAST_BACKUP_DIR/inbound.go" "$SRC"

        echo
        echo -e "${C_YELLOW}✓ سورس به وضعیت قبل از تغییر بازگردانده شد.${C_RESET}"
    fi
}

# ============================================================
# BUILD
# ============================================================

build_panel() {

    check_source
    check_go
    install_gcc

    cd "$SRC_DIR"

    export PATH="/usr/local/go/bin:$PATH"
    export CGO_ENABLED=1

    local NEW="/tmp/x-ui-FARID-$(date +%s)-$$"
    local LOG="/tmp/FARID-build-$(date +%s)-$$.log"

    echo
    echo -e "${C_YELLOW}  در حال Build پنل...${C_RESET}"
    echo -e "${C_CYAN}  این قسمت زمان‌بر هست. صبر کنید...${C_RESET}"
    echo

    if ! "$GO" build -o "$NEW" . >"$LOG" 2>&1; then

        echo
        echo -e "${C_RED}✗ Build ناموفق بود.${C_RESET}"
        echo

        tail -n 40 "$LOG"

        rm -f "$NEW"

        rollback_source

        return 1
    fi

    if [ ! -s "$NEW" ]; then

        echo
        echo -e "${C_RED}✗ باینری ساخته نشد.${C_RESET}"

        rm -f "$NEW"

        rollback_source

        return 1
    fi

    # --------------------------------------------------------
    # توقف پنل
    # --------------------------------------------------------

    if ! systemctl stop x-ui; then

        echo
        echo -e "${C_RED}✗ توقف x-ui ناموفق بود.${C_RESET}"

        rm -f "$NEW"

        rollback_source

        return 1
    fi

    # --------------------------------------------------------
    # نصب باینری جدید
    # --------------------------------------------------------

    if ! install -m 0755 "$NEW" "$BIN"; then

        echo
        echo -e "${C_RED}✗ نصب باینری جدید ناموفق بود.${C_RESET}"

        rm -f "$NEW"

        if [ -n "$LAST_BACKUP_DIR" ] &&
           [ -f "$LAST_BACKUP_DIR/x-ui" ]; then

            cp -a "$LAST_BACKUP_DIR/x-ui" "$BIN"
        fi

        systemctl restart x-ui || true

        rollback_source

        return 1
    fi

    systemctl daemon-reload

    # --------------------------------------------------------
    # Restart
    # --------------------------------------------------------

    if ! systemctl restart x-ui; then

        echo
        echo -e "${C_RED}✗ Restart x-ui ناموفق بود.${C_RESET}"

        if [ -n "$LAST_BACKUP_DIR" ] &&
           [ -f "$LAST_BACKUP_DIR/x-ui" ]; then

            cp -a "$LAST_BACKUP_DIR/x-ui" "$BIN"
        fi

        rollback_source

        systemctl daemon-reload
        systemctl restart x-ui || true

        rm -f "$NEW"

        return 1
    fi

    sleep 5

    # --------------------------------------------------------
    # بررسی سرویس
    # --------------------------------------------------------

    if systemctl is-active --quiet x-ui; then

        rm -f "$NEW"

        echo
        echo -e "${C_GREEN}✓ پنل با موفقیت Build و اجرا شد.${C_RESET}"
        echo

        return 0
    fi

    echo
    echo -e "${C_RED}✗ x-ui بعد از Build اجرا نشد.${C_RESET}"

    systemctl stop x-ui || true

    if [ -n "$LAST_BACKUP_DIR" ] &&
       [ -f "$LAST_BACKUP_DIR/x-ui" ]; then

        cp -a "$LAST_BACKUP_DIR/x-ui" "$BIN"
    fi

    rollback_source

    systemctl daemon-reload
    systemctl restart x-ui || true

    rm -f "$NEW"

    return 1
}

# ============================================================
# RESTORE BASE
# ============================================================

restore_backup() {

    show_header

    echo -e "${C_CYAN}  حذف ضریب و بازگشت به حالت اولیه${C_RESET}"
    echo
    line
    echo

    if [ ! -f "$BASE_BACKUP_DIR/x-ui" ] ||
       [ ! -f "$BASE_BACKUP_DIR/inbound.go" ]; then

        echo -e "${C_YELLOW}نسخه پایه وجود ندارد.${C_RESET}"

        pause

        return
    fi

    echo "  فقط باینری و سورس به نسخه پایه (ضریب ۱) بازگردانده می‌شوند:"
    echo
    echo "  x-ui"
    echo "  inbound.go"
    echo
    echo -e "  ${C_GREEN}دیتابیس (x-ui.db) به هیچ‌وجه دست زده نمی‌شود.${C_RESET}"
    echo -e "  ${C_GREEN}کاربران، اینباندها و ترافیک ثبت‌شده دقیقاً همین‌طور که هستند باقی می‌مانند.${C_RESET}"
    echo

    read -r -p "  مطمئن هستید؟ [y/N]: " CONFIRM

    case "$CONFIRM" in

        y|Y|yes|YES)

            create_backup

            systemctl stop x-ui

            cp -a "$BASE_BACKUP_DIR/x-ui" "$BIN"
            cp -a "$BASE_BACKUP_DIR/inbound.go" "$SRC"

            save_factor "1"

            systemctl daemon-reload
            systemctl restart x-ui

            sleep 5

            if systemctl is-active --quiet x-ui; then

                echo
                echo -e "${C_GREEN}✓ Restore انجام شد.${C_RESET}"
                echo "  ضریب فعلی: 1"

            else

                echo
                echo -e "${C_RED}✗ x-ui اجرا نشد.${C_RESET}"

            fi
            ;;

        *)

            echo
            echo "  عملیات لغو شد."

            ;;
    esac

    pause
}

# ============================================================
# FACTOR MENU
# ============================================================

factor_menu() {

    while true; do

        show_header

        CURRENT="$(get_current_factor)"

        echo -e "  ضریب فعلی: ${C_YELLOW}${C_WHITE}$CURRENT${C_RESET}"
        echo

        line

        echo

        echo -e "  ${C_CYAN}انتخاب ضریب جدید${C_RESET}"

        echo

        echo -e "  ${C_GREEN}[1]${C_RESET}  ضریب 1"
        echo -e "  ${C_GREEN}[2]${C_RESET}  ضریب 2"
        echo -e "  ${C_GREEN}[3]${C_RESET}  ضریب 3"
        echo -e "  ${C_GREEN}[4]${C_RESET}  ضریب 4"

        echo

        echo -e "  ${C_GRAY}[0]${C_RESET}  بازگشت"

        echo

        line

        echo

        read -r -p "  انتخاب شما [0-4]: " CHOICE

        case "$CHOICE" in

            1) NEW_FACTOR="1" ;;
            2) NEW_FACTOR="2" ;;
            3) NEW_FACTOR="3" ;;
            4) NEW_FACTOR="4" ;;
            0) return ;;

            *)

                echo
                echo -e "${C_RED}✗ انتخاب نامعتبر است.${C_RESET}"

                sleep 2

                continue
                ;;
        esac

        if [ "$NEW_FACTOR" = "$CURRENT" ]; then

            echo
            echo "  این ضریب در حال حاضر فعال است."

            pause

            continue
        fi

        echo
        echo "  ضریب جدید: $NEW_FACTOR"
        echo
        echo "  ترافیک قبلی کاربران دست‌نخورده باقی می‌ماند."
        echo "  فقط مصرف جدید از این لحظه با ضریب $NEW_FACTOR ثبت می‌شود."
        echo

        read -r -p "  ادامه می‌دهید؟ [y/N]: " CONFIRM

        case "$CONFIRM" in

            y|Y|yes|YES)

                if apply_factor "$NEW_FACTOR"; then

                    if build_panel; then

                        save_factor "$NEW_FACTOR"

                        echo
                        line

                        echo -e "${C_GREEN}${C_WHITE}✓ عملیات موفق بود${C_RESET}"

                        line

                        echo
                        echo "  ضریب فعال: $NEW_FACTOR"

                    else

                        echo
                        echo -e "${C_RED}✗ ضریب اعمال نشد و تغییرات برگشت داده شد.${C_RESET}"

                    fi

                else

                    echo
                    echo -e "${C_RED}✗ آماده‌سازی ضریب ناموفق بود.${C_RESET}"

                fi

                pause

                ;;

            *)

                echo
                echo "  عملیات لغو شد."

                sleep 1

                ;;
        esac
    done
}

# ============================================================
# STATUS
# ============================================================

show_status() {

    show_header

    echo -e "${C_CYAN}  وضعیت پنل${C_RESET}"

    echo

    line

    echo

    if systemctl is-active --quiet x-ui; then
        echo -e "  سرویس      : ${C_GREEN}فعال${C_RESET}"
    else
        echo -e "  سرویس      : ${C_RED}غیرفعال${C_RESET}"
    fi

    [ -f "$BIN" ] &&
        echo -e "  باینری     : ${C_GREEN}موجود${C_RESET}" ||
        echo -e "  باینری     : ${C_RED}پیدا نشد${C_RESET}"

    [ -f "$SRC" ] &&
        echo -e "  سورس       : ${C_GREEN}موجود${C_RESET}" ||
        echo -e "  سورس       : ${C_RED}پیدا نشد${C_RESET}"

    local DB

    DB="$(find_database || true)"

    if [ -n "$DB" ] && [ -f "$DB" ]; then
        echo -e "  دیتابیس    : ${C_GREEN}موجود${C_RESET}"
    else
        echo -e "  دیتابیس    : ${C_RED}پیدا نشد${C_RESET}"
    fi

    echo

    echo -e "  ضریب فعلی  : ${C_YELLOW}$(get_current_factor)${C_RESET}"

    echo

    line

    pause
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu() {

    while true; do

        show_header

        CURRENT="$(get_current_factor)"

        echo -e "  ضریب فعلی: ${C_YELLOW}${C_WHITE}$CURRENT${C_RESET}"

        echo

        line

        echo

        echo -e "  ${C_CYAN}منوی اصلی${C_RESET}"

        echo

        echo -e "  ${C_GREEN}[1]${C_RESET}  انتخاب / تغییر ضریب"
        echo -e "  ${C_BLUE}[2]${C_RESET}  حذف ضریب و بازگشت به حالت اولیه"
        echo -e "  ${C_CYAN}[3]${C_RESET}  بررسی وضعیت پنل"

        echo

        echo -e "  ${C_GRAY}[0]${C_RESET}  خروج"

        echo

        line

        echo

        read -r -p "  انتخاب شما [0-3]: " MENU

        case "$MENU" in

            1) factor_menu ;;
            2) restore_backup ;;
            3) show_status ;;

            0)

                clear

                echo
                echo "  X-UI T2F بسته شد."
                echo

                exit 0
                ;;

            *)

                echo
                echo -e "${C_RED}✗ انتخاب نامعتبر است.${C_RESET}"

                sleep 2

                ;;
        esac
    done
}

# ============================================================
# START
# ============================================================

show_header

echo -e "${C_CYAN}  X-UI T2F${C_RESET}"

echo

echo "  سیستم ضریب فقط روی ترافیک جدید کار می‌کند."
echo "  ترافیک قبلی کاربران هرگز دوباره ضرب نمی‌شود."

echo

echo "  ضرایب مجاز: 1 / 2 / 3 / 4"

echo

check_panel ||
    error_exit "3x-ui روی این سرور پیدا نشد."

detect_installed_version

echo -e "${C_GREEN}✓ نسخه‌ی نصب‌شده تشخیص داده شد: ${C_WHITE}$VERSION${C_RESET}"

check_source ||
    error_exit "سورس 3x-ui ($VERSION) پیدا نشد."

echo -e "${C_GREEN}✓ پنل و سورس آماده هستند.${C_RESET}"

# ============================================================
# CREATE BASE AUTOMATICALLY
# ============================================================

create_base_backup

main_menu

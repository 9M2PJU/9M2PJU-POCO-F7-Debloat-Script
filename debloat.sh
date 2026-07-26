#!/usr/bin/env bash
# ============================================================
# POCO F7 (onyx_global) - Debloat script
# ============================================================
# Removes known-safe bloat from a POCO F7 running HyperOS 2.
# Method: pm uninstall -k --user 0  (reversible, no root, no bootloader unlock)
#
# Usage:
#   bash debloat.sh             # interactive (explains + prompts per package)
#   bash debloat.sh --yes       # non-interactive, removes all batches
#   bash debloat.sh --list      # only list what would be removed, do nothing
#   bash debloat.sh --batch 2   # only run batch N (1-6)
#
# Each removed package is appended to removed_packages.txt in the same
# folder as this script. Pair with restore.sh to undo.
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backup"
LOG_FILE="${BACKUP_DIR}/removed_packages.txt"
INTERACTIVE=1
LIST_ONLY=0
BATCH_FILTER=""

# Colors
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""; C_DIM=""; C_RESET=""
fi

# ---------- Pre-flight checks ----------
check_device() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "${C_RED}ERROR: adb not found in PATH${C_RESET}" >&2
    exit 1
  fi
  if ! adb devices 2>/dev/null </dev/null | grep -q '\bdevice$'; then
    echo "${C_RED}ERROR: no adb device connected.${C_RESET}" >&2
    echo "Run 'adb devices' to check. Make sure USB debugging is on and the phone is authorized." >&2
    exit 1
  fi
  echo "${C_GREEN}Device connected:${C_RESET} $(adb shell getprop ro.product.model </dev/null) ($(adb shell getprop ro.product.name </dev/null))"
  echo "ROM: $(adb shell getprop ro.build.fingerprint </dev/null)"
  echo ""
}

# ---------- Get RAM usage of a package (if running) ----------
get_ram_usage() {
  local pkg="$1"
  local pid
  pid=$(adb shell "pidof $pkg 2>/dev/null" </dev/null | tr -d '\r' | head -1)
  if [ -z "$pid" ]; then
    echo ""
  else
    local pss
    pss=$(adb shell "dumpsys meminfo $pid 2>/dev/null | grep 'TOTAL PSS' | head -1" </dev/null | awk '{print $3}' | tr -d '\r')
    if [ -n "$pss" ]; then
      # Convert KB to MB
      local mb=$((pss / 1024))
      echo "${mb} MB RAM"
    else
      echo "running"
    fi
  fi
}

# ---------- Append a batch to the removal log ----------
log_batch() {
  local batch_name="$1"; shift
  {
    echo ""
    echo "# $(date +%F) - ${batch_name}"
    for p in "$@"; do echo "$p"; done
  } >> "$LOG_FILE"
}

# ---------- Remove one package ----------
# Returns: 0 = removed, 1 = failed, 2 = skipped (already removed/not installed)
remove_pkg() {
  local pkg="$1"
  if ! adb shell pm path "$pkg" 2>/dev/null </dev/null | grep -q apk; then
    echo "  ${C_YELLOW}SKIP${C_RESET}  $pkg (not installed)"
    return 2
  fi
  if ! adb shell pm list packages --user 0 2>/dev/null </dev/null | grep -q "^package:${pkg}$"; then
    echo "  ${C_YELLOW}SKIP${C_RESET}  $pkg (already removed for user 0)"
    return 2
  fi
  local out
  out=$(adb shell pm uninstall -k --user 0 "$pkg" 2>&1 </dev/null)
  if echo "$out" | grep -q 'Success'; then
    echo "  ${C_GREEN}OK${C_RESET}    $pkg"
    return 0
  else
    echo "  ${C_RED}FAIL${C_RESET}  $pkg -> $out"
    return 1
  fi
}

# ---------- Display a package card ----------
# Format: "pkg|description|why_remove"
show_pkg_card() {
  local entry="$1"
  local pkg desc why
  IFS='|' read -r pkg desc why <<< "$entry"
  local ram
  ram=$(get_ram_usage "$pkg")
  echo ""
  echo "  ${C_BOLD}Package:${C_RESET}  $pkg"
  echo "  ${C_BOLD}What:${C_RESET}     $desc"
  echo "  ${C_BOLD}Why:${C_RESET}      $why"
  if [ -n "$ram" ]; then
    echo "  ${C_BOLD}Now:${C_RESET}      ${C_YELLOW}${ram}${C_RESET}"
  fi
}

# ---------- Run a batch ----------
# Args: batch_num batch_name pkg1|desc1|why1 pkg2|desc2|why2 ...
run_batch() {
  local num="$1"; local name="$2"; shift 2
  local entries=("$@")
  echo ""
  echo "${C_CYAN}${C_BOLD}=== Batch $num: $name (${#entries[@]} packages) ===${C_RESET}"

  if [ "$LIST_ONLY" = "1" ]; then
    for e in "${entries[@]}"; do
      local pkg
      IFS='|' read -r pkg _ _ <<< "$e"
      echo "  would remove: $pkg"
    done
    echo ""
    return 0
  fi

  if [ "$INTERACTIVE" = "1" ]; then
    echo ""
    echo "${C_DIM}For each package, you'll see what it is and why it's being removed."
    echo "Answer y to remove, n to keep, s to skip the rest of this batch.${C_RESET}"
  fi

  local removed=()
  local skipped=0
  for e in "${entries[@]}"; do
    local pkg
    IFS='|' read -r pkg _ _ <<< "$e"

    if [ "$INTERACTIVE" = "1" ]; then
      show_pkg_card "$e"
      while true; do
        printf "  ${C_BOLD}Remove this package? [y/N/s]${C_RESET} "
        read -r ans
        case "$ans" in
          y|Y|yes|YES)
            remove_pkg "$pkg"
            rc=$?
            if [ "$rc" = "0" ]; then removed+=("$pkg"); fi
            break
            ;;
          s|S|skip|SKIP)
            echo "  ${C_DIM}Skipping rest of batch $num.${C_RESET}"
            skipped=1
            break 2
            ;;
          n|N|no|NO|"")
            echo "  ${C_DIM}Kept: $pkg${C_RESET}"
            break
            ;;
          *)
            echo "  ${C_DIM}Please answer y (yes), n (no), or s (skip rest of batch).${C_RESET}"
            ;;
        esac
      done
    else
      # Non-interactive (--yes) mode: show one-liner and remove
      remove_pkg "$pkg"
      if [ "$?" = "0" ]; then removed+=("$pkg"); fi
    fi
  done

  if [ "${#removed[@]}" -gt 0 ]; then
    log_batch "Batch $num: $name" "${removed[@]}"
  fi

  echo ""
  if [ "$skipped" = "1" ] && [ "$INTERACTIVE" = "1" ]; then
    echo "${C_YELLOW}Batch $num partially done.${C_RESET} Removed ${#removed[@]} package(s)."
  else
    echo "${C_GREEN}Batch $num done.${C_RESET} Removed ${#removed[@]} of ${#entries[@]} package(s)."
  fi
  if [ "${#removed[@]}" -gt 0 ]; then
    echo "${C_YELLOW}Test the phone now (unlock, Settings, launcher, reboot).${C_RESET}"
    echo "If broken: bash ${SCRIPT_DIR}/restore.sh ${removed[*]}"
  fi
  echo ""
}

# ---------- Batch definitions ----------
# Format: "package|description|why_remove"
BATCH1=(
  "com.miui.msa.global|Xiaomi Ad SDK (MSA)|Pushes ads in Notifications, GetApps, Settings. Single biggest privacy win."
  "com.xiaomi.joyose|Telemetry + Game Turbo backend|Stops Xiaomi usage analytics. Disables Game Turbo advanced features (acceptable if you don't game seriously)."
  "com.miui.analytics|Usage analytics|Stops usage pattern reporting to Xiaomi."
  "com.miui.bugreport|Bug report uploader|Stops automatic bug report telemetry."
)

BATCH2=(
  "com.mi.globalbrowser|Mi Browser|Replaced by Firefox/Chrome."
  "com.miui.player|Mi Music|Replaced by Spotify/YouTube Music."
  "com.miui.videoplayer|Mi Video|Replaced by VLC."
  "com.miui.yellowpage|Business directory spam|Useless in most regions."
  "com.miui.touchassistant|Floating ball assistant|Gimmick; uses RAM."
  "com.miui.thirdappassistant|Third-party app promo|Pushes app recommendations."
  "com.miui.securityadd|Security add-on module|Redundant with main Security Center."
  "com.xiaomi.mipicks|GetApps - Xiaomi's app store|Pushes junk app installs in background; major nuisance."
  "com.xiaomi.discover|GetApps companion|Same as above."
)

BATCH3=(
  "com.facebook.system|Meta background service|Tracking SDK; runs constantly even when you're not using Facebook."
  "com.facebook.services|Meta app support service|Background helper for Facebook apps."
  "com.facebook.appmanager|Meta app updater|Auto-updates FB apps; Play Store does this anyway."
)

BATCH4=(
  "com.microsoft.appmanager|Phone Link companion|Only useful if you use Phone Link on Windows."
  "com.microsoft.deviceintegrationservice|Cross-device integration service|Same as above."
  "com.microsoftsdk.crossdeviceservicebroker|SDK broker for Link to Windows|Same as above."
)

BATCH5=(
  "com.mi.appfinder|App drawer search bar|Spyware-ish; indexes app usage. Uses ~298 MB RAM."
  "com.mi.globalminusscreen|Leftmost 'minus screen' with news/ads|Ad surface; rarely used. Uses ~255 MB RAM."
)

BATCH6=(
  "com.google.android.apps.tachyon|Google Duo/Meet|Video calling app. Replaced by WhatsApp/Discord. Uses ~83 MB RAM when running."
  "com.google.android.apps.youtube.music|YouTube Music (system app)|Replaced by ReVanced YouTube Music."
  "com.google.android.apps.wellbeing|Digital Wellbeing|Screen time tracker. Uses ~37 MB RAM when running."
  "com.miui.misightservice|Xiaomi insights/telemetry|Same telemetry category as Joyose (Batch 1). Uses ~10 MB RAM when running."
  "com.xiaomi.barrage|Xiaomi bullet comments (danmaku overlay)|Chinese-market feature for floating comments on videos. Useless outside China."
)

# ---------- Parse args ----------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y) INTERACTIVE=0 ;;
    --list|-l) LIST_ONLY=1 ;;
    --batch) BATCH_FILTER="$2"; shift ;;
    --batch=*) BATCH_FILTER="${1#--batch=}" ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

# ---------- Main ----------
echo "${C_CYAN}${C_BOLD}POCO F7 Debloat${C_RESET}"
echo "Log file: $LOG_FILE"
echo ""

if [ "$LIST_ONLY" = "0" ]; then
  check_device
  # Initialize log file if missing
  mkdir -p "$BACKUP_DIR"
  if [ ! -f "$LOG_FILE" ]; then
    cat > "$LOG_FILE" <<EOF
# Packages removed from POCO F7 via debloat.sh
# Restore with: bash ${SCRIPT_DIR}/restore.sh
EOF
  fi
fi

if [ "$INTERACTIVE" = "1" ] && [ "$LIST_ONLY" = "0" ]; then
  echo "${C_DIM}This script will walk you through each package one by one."
  echo "For each package, you'll see:"
  echo "  - What it is"
  echo "  - Why it's being removed"
  echo "  - Current RAM usage (if running)"
  echo "Then you decide: y (remove), n (keep), or s (skip rest of batch)."
  echo ""
  echo "Everything is reversible - run restore.sh to undo any removal.${C_RESET}"
  echo ""
fi

run_one() {
  local n="$1" name="$2"; shift 2
  if [ -z "$BATCH_FILTER" ] || [ "$BATCH_FILTER" = "$n" ]; then
    run_batch "$n" "$name" "$@"
  fi
}

run_one 1 "Ad/telemetry"                          "${BATCH1[@]}"
run_one 2 "Xiaomi duplicate apps"                 "${BATCH2[@]}"
run_one 3 "Meta services"                         "${BATCH3[@]}"
run_one 4 "Microsoft Link to Windows"             "${BATCH4[@]}"
run_one 5 "Xiaomi app drawer search + minus screen" "${BATCH5[@]}"
run_one 6 "Google + Xiaomi extra bloat"           "${BATCH6[@]}"

if [ "$LIST_ONLY" = "1" ]; then
  echo "List-only mode - nothing was changed."
else
  echo "${C_GREEN}Done.${C_RESET} Removed packages are logged in: $LOG_FILE"
  echo "To undo everything:  bash ${SCRIPT_DIR}/restore.sh"
  echo "To undo one package: bash ${SCRIPT_DIR}/restore.sh <pkg>"
fi

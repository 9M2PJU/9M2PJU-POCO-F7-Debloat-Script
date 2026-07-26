#!/usr/bin/env bash
# ============================================================
# POCO F7 (onyx_global) — Debloat script
# ============================================================
# Removes known-safe bloat from a POCO F7 running HyperOS 2.
# Method: pm uninstall -k --user 0  (reversible, no root, no bootloader unlock)
#
# Usage:
#   bash debloat.sh             # interactive (prompts before each batch)
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
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_RESET=""
fi

# ---------- Pre-flight checks ----------
check_device() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "${C_RED}ERROR: adb not found in PATH${C_RESET}" >&2
    exit 1
  fi
  if ! adb devices 2>/dev/null | grep -q '\bdevice$'; then
    echo "${C_RED}ERROR: no adb device connected.${C_RESET}" >&2
    echo "Run 'adb devices' to check. Make sure USB debugging is on and the phone is authorized." >&2
    exit 1
  fi
  echo "${C_GREEN}Device connected:${C_RESET} $(adb shell getprop ro.product.model) ($(adb shell getprop ro.product.name))"
  echo "ROM: $(adb shell getprop ro.build.fingerprint)"
  echo ""
}

# ---------- Append a batch to the removal log ----------
log_batch() {
  local batch_name="$1"; shift
  {
    echo ""
    echo "# $(date +%F) — ${batch_name}"
    for p in "$@"; do echo "$p"; done
  } >> "$LOG_FILE"
}

# ---------- Remove one package ----------
remove_pkg() {
  local pkg="$1"
  if ! adb shell pm path "$pkg" 2>/dev/null | grep -q apk; then
    echo "  ${C_YELLOW}SKIP${C_RESET}  $pkg (not installed)"
    return 0
  fi
  if ! adb shell pm list packages --user 0 2>/dev/null | grep -q "^package:${pkg}$"; then
    echo "  ${C_YELLOW}SKIP${C_RESET}  $pkg (already removed for user 0)"
    return 0
  fi
  local out
  out=$(adb shell pm uninstall -k --user 0 "$pkg" 2>&1)
  if echo "$out" | grep -q 'Success'; then
    echo "  ${C_GREEN}OK${C_RESET}    $pkg"
    return 0
  else
    echo "  ${C_RED}FAIL${C_RESET}  $pkg -> $out"
    return 1
  fi
}

# ---------- Run a batch ----------
run_batch() {
  local num="$1"; local name="$2"; shift 2
  local pkgs=("$@")
  echo "${C_CYAN}=== Batch $num: $name (${#pkgs[@]} packages) ===${C_RESET}"
  if [ "$LIST_ONLY" = "1" ]; then
    for p in "${pkgs[@]}"; do echo "  would remove: $p"; done
    echo ""
    return 0
  fi
  if [ "$INTERACTIVE" = "1" ]; then
    printf "Proceed? [y/N] "
    read -r ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "Skipped."; echo ""; return 0 ;;
    esac
  fi
  local removed=()
  for p in "${pkgs[@]}"; do
    if remove_pkg "$p"; then removed+=("$p"); fi
  done
  if [ "${#removed[@]}" -gt 0 ]; then
    log_batch "Batch $num: $name" "${removed[@]}"
  fi
  echo ""
  echo "${C_YELLOW}Test the phone now (unlock, Settings, launcher, reboot).${C_RESET}"
  echo "If broken: bash ${SCRIPT_DIR}/restore.sh ${removed[*]}"
  echo ""
}

# ---------- Batch definitions ----------
BATCH1=(com.miui.msa.global com.xiaomi.joyose com.miui.analytics com.miui.bugreport)
BATCH2=(com.mi.globalbrowser com.miui.player com.miui.videoplayer com.miui.yellowpage
        com.miui.touchassistant com.miui.thirdappassistant com.miui.securityadd
        com.xiaomi.mipicks com.xiaomi.discover)
BATCH3=(com.facebook.system com.facebook.services com.facebook.appmanager)
BATCH4=(com.microsoft.appmanager com.microsoft.deviceintegrationservice
        com.microsoftsdk.crossdeviceservicebroker)
BATCH5=(com.mi.appfinder com.mi.globalminusscreen)
BATCH6=(com.google.android.apps.tachyon com.google.android.apps.youtube.music
        com.google.android.apps.wellbeing com.miui.misightservice com.xiaomi.barrage)

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
echo "${C_CYAN}POCO F7 Debloat${C_RESET}"
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

run_one() {
  local n="$1" name="$2"; shift 2
  if [ -z "$BATCH_FILTER" ] || [ "$BATCH_FILTER" = "$n" ]; then
    run_batch "$n" "$name" "$@"
  fi
}

run_one 1 "Ad/telemetry"          "${BATCH1[@]}"
run_one 2 "Xiaomi duplicate apps" "${BATCH2[@]}"
run_one 3 "Meta services"         "${BATCH3[@]}"
run_one 4 "Microsoft Link to Windows" "${BATCH4[@]}"
run_one 5 "Xiaomi app drawer search + minus screen" "${BATCH5[@]}"
run_one 6 "Google + Xiaomi extra bloat" "${BATCH6[@]}"

if [ "$LIST_ONLY" = "1" ]; then
  echo "List-only mode — nothing was changed."
else
  echo "${C_GREEN}Done.${C_RESET} Removed packages are logged in: $LOG_FILE"
  echo "To undo everything:  bash ${SCRIPT_DIR}/restore.sh"
  echo "To undo one package: bash ${SCRIPT_DIR}/restore.sh <pkg>"
fi

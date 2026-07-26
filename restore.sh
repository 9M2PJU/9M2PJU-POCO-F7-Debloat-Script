#!/usr/bin/env bash
# ============================================================
# POCO F7 (onyx_global) - Restore script
# ============================================================
# Restores packages removed by debloat.sh.
# Method: pm install-existing --user 0  (re-registers the app from the
# untouched /system APK - no internet needed, instant).
#
# Usage:
#   bash restore.sh                  # interactive: explain + prompt per package
#   bash restore.sh --yes            # non-interactive, restore everything
#   bash restore.sh com.miui.msa.global           # restore one package
#   bash restore.sh com.miui.msa.global com.xiaomi.joyose   # restore several
#   bash restore.sh --batch 2        # restore a specific batch (by number)
#   bash restore.sh --list           # show what would be restored, do nothing
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backup"
LOG_FILE="${BACKUP_DIR}/removed_packages.txt"
INTERACTIVE=1
LIST_ONLY=0
BATCH_FILTER=""
EXPLICIT_PKGS=()

# Colors
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""; C_DIM=""; C_RESET=""
fi

# ---------- Pre-flight ----------
if ! command -v adb >/dev/null 2>&1; then
  echo "${C_RED}ERROR: adb not found in PATH${C_RESET}" >&2
  exit 1
fi
if ! adb devices 2>/dev/null </dev/null | grep -q '\bdevice$'; then
  echo "${C_RED}ERROR: no adb device connected.${C_RESET}" >&2
  echo "Run 'adb devices' to check." >&2
  exit 1
fi

# ---------- Package metadata (mirrors debloat.sh) ----------
# Format: "package|description|why_was_removed"
PKG_META=(
  "com.miui.msa.global|Xiaomi Ad SDK (MSA)|Was removed: pushes ads in Notifications, GetApps, Settings."
  "com.xiaomi.joyose|Telemetry + Game Turbo backend|Was removed: Xiaomi usage analytics. Note: restoring re-enables Game Turbo advanced features."
  "com.miui.analytics|Usage analytics|Was removed: usage pattern reporting to Xiaomi."
  "com.miui.bugreport|Bug report uploader|Was removed: automatic bug report telemetry."
  "com.mi.globalbrowser|Mi Browser|Was removed: replaced by Firefox/Chrome."
  "com.miui.player|Mi Music|Was removed: replaced by Spotify/YouTube Music."
  "com.miui.videoplayer|Mi Video|Was removed: replaced by VLC."
  "com.miui.yellowpage|Business directory spam|Was removed: useless in most regions."
  "com.miui.touchassistant|Floating ball assistant|Was removed: gimmick; uses RAM."
  "com.miui.thirdappassistant|Third-party app promo|Was removed: pushes app recommendations."
  "com.miui.securityadd|Security add-on module|Was removed: redundant with main Security Center."
  "com.xiaomi.mipicks|GetApps - Xiaomi's app store|Was removed: pushes junk app installs in background."
  "com.xiaomi.discover|GetApps companion|Was removed: same as GetApps."
  "com.facebook.system|Meta background service|Was removed: tracking SDK; runs constantly."
  "com.facebook.services|Meta app support service|Was removed: background helper for Facebook apps."
  "com.facebook.appmanager|Meta app updater|Was removed: auto-updates FB apps."
  "com.microsoft.appmanager|Phone Link companion|Was removed: only useful with Phone Link on Windows."
  "com.microsoft.deviceintegrationservice|Cross-device integration service|Was removed: same as above."
  "com.microsoftsdk.crossdeviceservicebroker|SDK broker for Link to Windows|Was removed: same as above."
  "com.mi.appfinder|App drawer search bar|Was removed: indexes app usage. Used ~298 MB RAM."
  "com.mi.globalminusscreen|Leftmost 'minus screen' with news/ads|Was removed: ad surface. Used ~255 MB RAM."
  "com.google.android.apps.tachyon|Google Duo/Meet|Was removed: video calling. Used ~83 MB RAM."
  "com.google.android.apps.youtube.music|YouTube Music (system app)|Was removed: replaced by ReVanced."
  "com.google.android.apps.wellbeing|Digital Wellbeing|Was removed: screen time tracker. Used ~37 MB RAM."
  "com.miui.misightservice|Xiaomi insights/telemetry|Was removed: telemetry. Used ~10 MB RAM."
  "com.xiaomi.barrage|Xiaomi bullet comments (danmaku)|Was removed: Chinese-market feature, useless outside China."
  "com.tencent.soter.soterserver|Tencent SOTER biometric auth server|Was removed: Chinese biometric auth for WeChat/QQ. Useless outside China. Used ~6 MB RAM."
)

# ---------- Look up metadata for a package ----------
# Sets META_DESC and META_WHY globals, or empty if unknown
lookup_meta() {
  local pkg="$1"
  META_DESC=""
  META_WHY=""
  for entry in "${PKG_META[@]}"; do
    local p d w
    IFS='|' read -r p d w <<< "$entry"
    if [ "$p" = "$pkg" ]; then
      META_DESC="$d"
      META_WHY="$w"
      return 0
    fi
  done
}

# ---------- Check if a package is currently installed ----------
is_installed() {
  local pkg="$1"
  adb shell pm list packages --user 0 2>/dev/null </dev/null | grep -q "^package:${pkg}$"
}

# ---------- Restore one package ----------
# Returns: 0 = restored, 1 = failed, 2 = skipped (already installed)
restore_one() {
  local pkg="$1"
  pkg="${pkg#package:}"   # strip "package:" prefix if present
  [ -z "$pkg" ] && return 2
  case "$pkg" in '#'*) return 2 ;; esac

  if is_installed "$pkg"; then
    echo "  ${C_YELLOW}SKIP${C_RESET}  $pkg (already installed for user 0)"
    return 2
  fi

  local out
  out=$(adb shell pm install-existing --user 0 "$pkg" 2>&1 </dev/null)
  if echo "$out" | grep -q 'Success'; then
    echo "  ${C_GREEN}OK${C_RESET}    $pkg"
    return 0
  else
    # Some packages may only have been disabled, not uninstalled - try enable as fallback
    if adb shell pm enable --user 0 "$pkg" >/dev/null 2>&1 </dev/null; then
      echo "  ${C_GREEN}OK${C_RESET}    $pkg (was disabled, re-enabled)"
      return 0
    else
      echo "  ${C_RED}FAIL${C_RESET}  $pkg -> $out"
      return 1
    fi
  fi
}

# ---------- Display a package card ----------
# Sets CARD_INSTALLED global (1=installed, 0=removed) for option labels
show_pkg_card() {
  local pkg="$1"
  lookup_meta "$pkg"
  local status
  if is_installed "$pkg"; then
    CARD_INSTALLED=1
    status="${C_GREEN}currently installed${C_RESET}"
  else
    CARD_INSTALLED=0
    status="${C_YELLOW}currently removed${C_RESET}"
  fi
  echo ""
  echo "  ${C_BOLD}Package:${C_RESET}  $pkg"
  if [ -n "$META_DESC" ]; then
    echo "  ${C_BOLD}What:${C_RESET}     $META_DESC"
  else
    echo "  ${C_BOLD}What:${C_RESET}     (no description available)"
  fi
  if [ -n "$META_WHY" ]; then
    echo "  ${C_BOLD}History:${C_RESET}  $META_WHY"
  fi
  echo "  ${C_BOLD}Status:${C_RESET}    $status"
}

# ---------- Parse args ----------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y) INTERACTIVE=0 ;;
    --list|-l) LIST_ONLY=1 ;;
    --batch) BATCH_FILTER="$2"; shift ;;
    --batch=*) BATCH_FILTER="${1#--batch=}" ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) EXPLICIT_PKGS+=("$1") ;;
  esac
  shift
done

# ---------- Collect target packages ----------
TARGETS=()
if [ "${#EXPLICIT_PKGS[@]}" -gt 0 ]; then
  TARGETS=("${EXPLICIT_PKGS[@]}")
elif [ -n "$BATCH_FILTER" ]; then
  if [ ! -f "$LOG_FILE" ]; then
    echo "${C_RED}ERROR: $LOG_FILE not found.${C_RESET}" >&2
    exit 1
  fi
  # Extract packages under the "# Batch N ..." comment block
  mapfile -t TARGETS < <(awk -v b="$BATCH_FILTER" '
    /^# .*Batch [0-9]+/ {
      n = $0
      sub(/^.*Batch /, "", n)
      sub(/[^0-9].*$/, "", n)
      in_block = (n == b)
      next
    }
    /^#/  { next }
    /^$/  { next }
    in_block { print }
  ' "$LOG_FILE")
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    echo "${C_RED}No packages found for batch $BATCH_FILTER in $LOG_FILE${C_RESET}" >&2
    exit 1
  fi
else
  if [ ! -f "$LOG_FILE" ]; then
    echo "${C_RED}ERROR: $LOG_FILE not found - nothing to restore.${C_RESET}" >&2
    exit 1
  fi
  # All non-comment, non-empty lines
  mapfile -t TARGETS < <(grep -vE '^#|^$' "$LOG_FILE")
fi

# ---------- Run ----------
echo "${C_CYAN}${C_BOLD}POCO F7 Restore${C_RESET}"
echo "Device: $(adb shell getprop ro.product.model </dev/null) ($(adb shell getprop ro.product.name </dev/null))"
echo "Packages to restore: ${#TARGETS[@]}"
echo ""

if [ "$LIST_ONLY" = "1" ]; then
  for p in "${TARGETS[@]}"; do
    lookup_meta "$p"
    if [ -n "$META_DESC" ]; then
      echo "  would restore: $p  ${C_DIM}($META_DESC)${C_RESET}"
    else
      echo "  would restore: $p"
    fi
  done
  echo ""
  echo "List-only mode - nothing was changed."
  exit 0
fi

if [ "$INTERACTIVE" = "1" ]; then
  echo "${C_DIM}This script will walk you through each package one by one."
  echo "For each package, you'll see what it is, why it was removed, and"
  echo "its current status (installed or removed)."
  echo "Then you choose: 1 (restore), 2 (keep removed), or 3 (skip rest).${C_RESET}"
  echo ""
fi

ok=0; fail=0; skip=0; kept=0
for p in "${TARGETS[@]}"; do
  # Skip comment/empty lines
  case "$p" in '#'*|'') continue ;; esac

  if [ "$INTERACTIVE" = "1" ]; then
    show_pkg_card "$p"
    # Build option labels with context (like a guided question)
    opt1_label="Restore"
    if [ "${CARD_INSTALLED:-0}" = "1" ]; then
      opt1_label="Restore (already installed - will skip)"
    fi
    echo ""
    echo "  ${C_BOLD}1)${C_RESET} ${opt1_label}"
    echo "  ${C_BOLD}2)${C_RESET} Keep removed"
    echo "  ${C_BOLD}3)${C_RESET} Skip rest of the restore list"
    while true; do
      printf "  ${C_BOLD}Choose [1-3] (default 2):${C_RESET} "
      read -r ans
      case "$ans" in
        1|restore|Restore|RESTORE|y|Y|yes|YES)
          restore_one "$p"
          rc=$?
          case "$rc" in
            0) ok=$((ok+1)) ;;
            1) fail=$((fail+1)) ;;
            2) skip=$((skip+1)) ;;
          esac
          break
          ;;
        3|skip|Skip|SKIP|s|S)
          echo "  ${C_DIM}Skipping rest of the restore list.${C_RESET}"
          break 2
          ;;
        2|keep|Keep|KEEP|n|N|no|NO|"")
          echo "  ${C_DIM}Kept removed: $p${C_RESET}"
          kept=$((kept+1))
          break
          ;;
        *)
          echo "  ${C_DIM}Please choose 1 (restore), 2 (keep removed), or 3 (skip rest).${C_RESET}"
          ;;
      esac
    done
  else
    # Non-interactive (--yes) mode
    restore_one "$p"
    rc=$?
    case "$rc" in
      0) ok=$((ok+1)) ;;
      1) fail=$((fail+1)) ;;
      2) skip=$((skip+1)) ;;
    esac
  fi
done

echo ""
echo "${C_GREEN}Done.${C_RESET} Restored=$ok  Skipped=$skip  Kept=$kept  Failed=$fail"
if [ "$kept" -gt 0 ]; then
  echo "${C_DIM}Kept=$kept packages were not restored (you chose to skip them).${C_RESET}"
fi
[ "$fail" -gt 0 ] && echo "${C_YELLOW}Some packages failed - they may have been removed by an OTA update. A factory reset will restore everything.${C_RESET}"

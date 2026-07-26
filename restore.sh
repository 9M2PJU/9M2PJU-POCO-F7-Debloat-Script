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
# Format: "package|what|details|why_was_removed|caveats"
PKG_META=(
  "com.miui.msa.global|Xiaomi Ad SDK (MSA)|Xiaomi Mobile Ad SDK. Injects ads into Notification shade, Settings, GetApps, Security Center. Persistent background service. Biggest source of in-OS ads.|Was removed: pushes ads across the OS and collects ad-targeting data.|Restoring re-enables ads in Notification shade, Settings, and other Xiaomi apps."
  "com.xiaomi.joyose|Xiaomi Joyose (telemetry + Game Turbo)|Background service: usage analytics, device health reporting, Game Turbo backend. Phones home with usage patterns and performance metrics.|Was removed: Xiaomi usage analytics and telemetry.|Restoring re-enables Game Turbo advanced features (per-game GPU/CPU tuning, brightness lock, calls blocking during games)."
  "com.miui.analytics|Xiaomi Analytics|Collects and uploads app usage patterns, feature usage, crash stats, device telemetry to Xiaomi.|Was removed: usage pattern reporting to Xiaomi.|Restoring re-enables telemetry collection. No user-facing feature added."
  "com.miui.bugreport|Xiaomi Bug Report|Automatic bug report capture and uploader. Sends device state, logs, stack traces to Xiaomi on crashes.|Was removed: automatic bug report telemetry.|Restoring re-enables automatic bug report uploads."
  "com.mi.globalbrowser|Mi Browser|Xiaomi's default browser. Custom Chromium fork with Xiaomi tracking, news feed, push notifications. Sends browsing data to Xiaomi.|Was removed: replaced by Firefox/Chrome; tracking surface.|Restoring brings back Xiaomi's browser with tracking. Set it as default again if you want to use it."
  "com.miui.player|Mi Music|Xiaomi's default music player. Includes Xiaomi music streaming (mostly Chinese catalog), ads in free tier.|Was removed: replaced by Spotify/YouTube Music/other.|Restoring brings back Mi Music with ads. Audio playback in other apps unaffected."
  "com.miui.videoplayer|Mi Video|Xiaomi's default video player. Includes Xiaomi video streaming (mostly Chinese/Indian content), ads.|Was removed: replaced by VLC/MX Player/other.|Restoring brings back Mi Video with ads."
  "com.miui.yellowpage|YellowPage|Xiaomi business directory with paid placements. Mostly useless outside China/India. Pushes promotional notifications.|Was removed: useless in most regions; notification spam.|Restoring may re-enable promotional notifications."
  "com.miui.touchassistant|TouchAssistant (floating ball)|Floating ball on screen edge with shortcuts (screenshot, lock, recents, back). Gimmick; uses RAM.|Was removed: gimmick; uses RAM.|Restoring brings back the floating ball. You can disable it in Settings if unwanted."
  "com.miui.thirdappassistant|ThirdAppAssistant|Pushes third-party app recommendations and promotions in system UI.|Was removed: ad/recommendation surface.|Restoring re-enables app recommendation pushes."
  "com.miui.securityadd|Security add-on module|Add-on for Security Center with redundant 'optimization' features (deep clean, junk scan). Upsells Xiaomi services, shows ads.|Was removed: redundant; ad surface.|Restoring brings back the add-on with ads. Main Security Center works without it."
  "com.xiaomi.mipicks|GetApps (Xiaomi app store)|Xiaomi's alternative app store. Pushes 'recommended' app installs in background, shows deal notifications, installs apps you didn't ask for. Major nuisance.|Was removed: pushes junk app installs in background; major nuisance.|Restoring re-enables background app installs and recommendation notifications. This is why you'd find random games on your phone."
  "com.xiaomi.discover|GetApps Discover|Companion to GetApps. Provides 'Discover' feed with app recommendations and promotions.|Was removed: same as GetApps - recommendation/ad surface.|Restoring re-enables the Discover feed. Works with mipicks."
  "com.facebook.system|Meta background service (Facebook)|Meta's tracking SDK as a system service. Tracks location, app usage, device info even when NOT using Facebook. Can receive push data from Meta servers.|Was removed: tracking SDK running constantly; privacy concern.|Restoring re-enables background tracking. Facebook/Instagram apps work without it - this is an optional helper."
  "com.facebook.services|Meta app support service|Background helper for Facebook/Instagram. Cross-app communication and account syncing.|Was removed: background helper not needed.|Restoring re-enables the helper. Facebook apps work without it."
  "com.facebook.appmanager|Meta app updater|Background updater for Facebook/Instagram/Messenger. Bypasses Play Store update cycle, can update without consent.|Was removed: auto-updates FB apps without consent.|Restoring re-enables bypass of Play Store update control for Meta apps."
  "com.microsoft.appmanager|Phone Link companion|Microsoft Phone Link companion. Text, call, see notifications, mirror photos on Windows PC. Runs in background.|Was removed: only useful with Phone Link on Windows.|Restoring re-enables Phone Link integration. Install Phone Link on your PC to use it."
  "com.microsoft.deviceintegrationservice|Cross-device integration service|Backend for Phone Link. Handles cross-device communication (notifications sync, file transfer, call relay).|Was removed: only useful with Phone Link on Windows.|Restoring re-enables the Phone Link backend."
  "com.microsoftsdk.crossdeviceservicebroker|SDK broker for Link to Windows|SDK broker mediating between Phone Link apps and system.|Was removed: part of Phone Link stack.|Restoring completes the Phone Link stack. Microsoft Word is NOT affected."
  "com.mi.appfinder|App drawer search bar|Search bar in app drawer. Indexes apps AND app usage patterns. Sends usage data to Xiaomi. Uses ~298 MB RAM.|Was removed: indexes app usage and sends to Xiaomi; ~298 MB RAM.|Restoring brings back the search bar and usage indexing. App drawer works without it."
  "com.mi.globalminusscreen|Minus screen (leftmost home screen)|Leftmost home screen page with news, ads, 'recommended' apps, widgets. Xiaomi sells as ad inventory. Uses ~255 MB RAM.|Was removed: ad surface; ~255 MB RAM.|Restoring brings back the minus screen with ads and news."
  "com.google.android.apps.tachyon|Google Duo/Meet|Google's video calling app (rebranded to Meet). System app. Uses ~83 MB RAM when active.|Was removed: replaced by WhatsApp/Discord/other; ~83 MB RAM.|Restoring brings back Duo/Meet. You can also install Google Meet from Play Store instead."
  "com.google.android.apps.youtube.music|YouTube Music (system app)|System version of YouTube Music.|Was removed: replaced by ReVanced YouTube Music/other.|Restoring brings back the system YT Music app. You can also install from Play Store."
  "com.google.android.apps.wellbeing|Digital Wellbeing|Google's screen time tracker. App usage time, app timers, wind-down, focus mode. Uses ~37 MB RAM.|Was removed: screen time tracker not used; ~37 MB RAM.|Restoring brings back Digital Wellbeing. You can also install from Play Store."
  "com.miui.misightservice|Xiaomi MiSight (insights/telemetry)|Xiaomi's insights and telemetry service. Collects device health, feature usage, system metrics. Phones home. Uses ~10 MB RAM.|Was removed: telemetry; ~10 MB RAM.|Restoring re-enables another telemetry channel to Xiaomi."
  "com.xiaomi.barrage|Xiaomi Barrage (bullet comments)|Danmaku-style floating bullet comments overlay for videos. Chinese market feature. Useless outside China.|Was removed: Chinese-market feature, useless outside China.|Restoring brings back the bullet comments feature. Only useful if you watch Chinese video platforms."
  "com.tencent.soter.soterserver|Tencent SOTER (biometric auth server)|Tencent's SOTER biometric authentication server. Chinese standard for fingerprint/face login in WeChat, QQ, Tencent games, some banking apps. Uses ~6 MB RAM.|Was removed: Chinese biometric auth for WeChat/QQ; useless outside China; ~6 MB RAM.|Restoring re-enables biometric auth for Chinese apps. Only needed if you use WeChat/QQ/Chinese banking apps with fingerprint login."
)

# ---------- Look up metadata for a package ----------
# Sets META_WHAT, META_DETAILS, META_WHY, META_CAVEATS globals (or empty)
lookup_meta() {
  local pkg="$1"
  META_WHAT=""
  META_DETAILS=""
  META_WHY=""
  META_CAVEATS=""
  for entry in "${PKG_META[@]}"; do
    local p what details why caveats
    IFS='|' read -r p what details why caveats <<< "$entry"
    if [ "$p" = "$pkg" ]; then
      META_WHAT="$what"
      META_DETAILS="$details"
      META_WHY="$why"
      META_CAVEATS="$caveats"
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
  if [ -n "$META_WHAT" ]; then
    echo "  ${C_BOLD}What:${C_RESET}     $META_WHAT"
  else
    echo "  ${C_BOLD}What:${C_RESET}     (no description available)"
  fi
  if [ -n "$META_DETAILS" ]; then
    echo "  ${C_BOLD}Details:${C_RESET} $META_DETAILS"
  fi
  if [ -n "$META_WHY" ]; then
    echo "  ${C_BOLD}History:${C_RESET}  $META_WHY"
  fi
  if [ -n "$META_CAVEATS" ]; then
    echo "  ${C_BOLD}Restoring:${C_RESET} $META_CAVEATS"
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
    if [ -n "$META_WHAT" ]; then
      echo "  would restore: $p  ${C_DIM}($META_WHAT)${C_RESET}"
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

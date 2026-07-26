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
#   bash debloat.sh --batch 2   # only run batch N (1-7)
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
# Format: "pkg|what|details|why|caveats"
# Sets CARD_RAM global with RAM usage string (or empty) for option labels
show_pkg_card() {
  local entry="$1"
  local pkg what details why caveats
  IFS='|' read -r pkg what details why caveats <<< "$entry"
  CARD_RAM=$(get_ram_usage "$pkg")
  echo ""
  echo "  ${C_BOLD}Package:${C_RESET}  $pkg"
  echo "  ${C_BOLD}What:${C_RESET}     $what"
  if [ -n "$details" ]; then
    echo "  ${C_BOLD}Details:${C_RESET} $details"
  fi
  echo "  ${C_BOLD}Why:${C_RESET}      $why"
  if [ -n "$caveats" ]; then
    echo "  ${C_BOLD}Caveats:${C_RESET}  $caveats"
  fi
  if [ -n "$CARD_RAM" ]; then
    echo "  ${C_BOLD}Now:${C_RESET}      ${C_YELLOW}${CARD_RAM}${C_RESET}"
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
      local pkg what
      IFS='|' read -r pkg what _ _ _ <<< "$e"
      echo "  would remove: $pkg  ${C_DIM}($what)${C_RESET}"
    done
    echo ""
    return 0
  fi

  if [ "$INTERACTIVE" = "1" ]; then
    echo ""
    echo "${C_DIM}For each package, you'll see what it is, why it's being removed, and"
    echo "current RAM usage. Then choose: 1 (remove), 2 (keep), or 3 (skip batch).${C_RESET}"
  fi

  local removed=()
  local skipped=0
  for e in "${entries[@]}"; do
    local pkg
    IFS='|' read -r pkg _ _ _ _ <<< "$e"

    if [ "$INTERACTIVE" = "1" ]; then
      show_pkg_card "$e"
      # Build option labels with context (like a guided question)
      local opt1_label="Remove"
      if [ -n "${CARD_RAM:-}" ]; then
        opt1_label="Remove (frees ${CARD_RAM})"
      fi
      echo ""
      echo "  ${C_BOLD}1)${C_RESET} ${opt1_label}"
      echo "  ${C_BOLD}2)${C_RESET} Keep"
      echo "  ${C_BOLD}3)${C_RESET} Skip rest of this batch"
      while true; do
        printf "  ${C_BOLD}Choose [1-3] (default 2):${C_RESET} "
        read -r ans
        case "$ans" in
          1|remove|Remove|REMOVE)
            remove_pkg "$pkg"
            rc=$?
            if [ "$rc" = "0" ]; then removed+=("$pkg"); fi
            break
            ;;
          3|skip|Skip|SKIP|s|S)
            echo "  ${C_DIM}Skipping rest of batch $num.${C_RESET}"
            skipped=1
            break 2
            ;;
          2|keep|Keep|KEEP|n|N|no|NO|"")
            echo "  ${C_DIM}Kept: $pkg${C_RESET}"
            break
            ;;
          *)
            echo "  ${C_DIM}Please choose 1 (remove), 2 (keep), or 3 (skip rest of batch).${C_RESET}"
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
# Format: "package|what|details|why|caveats"
# - what:     short name/description
# - details:  what it actually does (the full picture)
# - why:      why it's being removed
# - caveats:  what may break or change if removed (empty = safe)
BATCH1=(
  "com.miui.msa.global|Xiaomi Ad SDK (MSA)|Xiaomi Mobile Ad SDK. Injects ads into Notification shade, Settings app, GetApps, Security Center, and other Xiaomi apps. Runs as a persistent background service. The single biggest source of in-OS ads on HyperOS.|Biggest privacy and UX win. Removes ads from the entire OS. Stops ad-targeting data collection.|Safe to remove. No system functionality breaks. Ads simply stop appearing."
  "com.xiaomi.joyose|Xiaomi Joyose (telemetry + Game Turbo)|Background service handling usage analytics, device health reporting, and Game Turbo backend. Phones home with usage patterns, app launch data, and performance metrics. Also powers Game Turbo's per-game performance profiles.|Stops Xiaomi usage analytics and telemetry reporting. Reclaim background CPU and RAM.|Removing disables Game Turbo advanced features (per-game GPU/CPU tuning, brightness lock, calls blocking during games). Basic gaming still works fine. Games just won't get the optimized performance profile."
  "com.miui.analytics|Xiaomi Analytics|Collects and uploads app usage patterns, feature usage, crash stats, and device telemetry to Xiaomi servers. Runs in background.|Stops usage pattern reporting to Xiaomi. Privacy win.|Safe to remove. No user-facing functionality breaks."
  "com.miui.bugreport|Xiaomi Bug Report|Automatic bug report capture and uploader. Triggers on crashes/anomalies and uploads detailed device state, logs, and stack traces to Xiaomi.|Stops automatic bug report telemetry. Your crash data and logs no longer get sent to Xiaomi without consent.|Safe to remove. Manual bug reports via Settings still work if you ever need them."
)

BATCH2=(
  "com.mi.globalbrowser|Mi Browser|Xiaomi's default web browser. Based on a custom Chromium fork with Xiaomi tracking, news feed, and push notifications built in. Sends browsing data to Xiaomi.|Replaced by Firefox, Chrome, Brave, or any other browser. Removes a tracking surface.|Safe to remove. Set another browser as default in Settings > Apps > Default apps. Links will open in your chosen browser."
  "com.miui.player|Mi Music|Xiaomi's default music player. Includes Xiaomi's music streaming service (mostly Chinese catalog), ads in the free tier, and a custom audio engine wrapper.|Replaced by Spotify, YouTube Music, Poweramp, or any other music app you prefer.|Safe to remove. Audio playback still works in other apps. No system audio features break."
  "com.miui.videoplayer|Mi Video|Xiaomi's default video player. Includes Xiaomi's video streaming service (mostly Chinese/Indian content), ads, and a custom video engine.|Replaced by VLC, MX Player, or any other video player.|Safe to remove. Video playback in other apps unaffected."
  "com.miui.yellowpage|YellowPage|Xiaomi's business directory. Shows nearby businesses with paid placements. Mostly useless outside China/India. Pushes promotional notifications.|Useless in most regions. Removes a notification spam source.|Safe to remove. No contacts or dialer functionality breaks."
  "com.miui.touchassistant|TouchAssistant (floating ball)|A floating ball on the screen edge with shortcuts (screenshot, lock, recent apps, back). Gimmick feature that uses RAM and screen space.|Gimmick; uses RAM. Most people disable it within a day of getting the phone.|Safe to remove. All functions it offers are available elsewhere (screenshot, recents, etc.)."
  "com.miui.thirdappassistant|ThirdAppAssistant|Pushes third-party app recommendations and promotions in the system. Surfaces 'recommended apps' in various Xiaomi UI surfaces.|Removes an ad/recommendation surface. Stops Xiaomi pushing junk app installs via this channel.|Safe to remove. No functionality breaks."
  "com.miui.securityadd|Security add-on module|An add-on for Xiaomi Security Center that adds redundant 'optimization' features (deep clean, junk scan). Mostly upsells Xiaomi services and shows ads.|Redundant with the main Security Center. Removes an ad surface.|Safe to remove. Main Security Center (com.miui.securitycenter) still works. Core security features (antivirus, permissions, privacy) unaffected."
  "com.xiaomi.mipicks|GetApps (Xiaomi app store)|Xiaomi's alternative app store. Pushes 'recommended' app installs in the background, shows notifications about deals/promotions, and installs apps you didn't ask for. Major nuisance - this is why you find random games on your phone.|Major nuisance removal. Stops background junk app installs. Removes a persistent ad/recommendation engine.|Safe to remove. Play Store handles all app installs. No functionality breaks."
  "com.xiaomi.discover|GetApps Discover|Companion to GetApps (mipicks). Provides the 'Discover' feed with app recommendations and promotions. Same background behavior as GetApps.|Same as GetApps - removes a recommendation/ad surface.|Safe to remove. Works together with mipicks removal."
)

BATCH3=(
  "com.facebook.system|Meta background service (Facebook)|Meta's tracking SDK that runs as a system service. Tracks location, app usage, and device info even when you're NOT using Facebook or Instagram. Can receive push data from Meta servers.|Tracking SDK running constantly. Privacy concern - tracks you even without Facebook open.|Safe to remove. The Facebook app (com.facebook.katana) and Instagram still work - these are optional helper services, not required dependencies."
  "com.facebook.services|Meta app support service|Background helper for Facebook/Instagram apps. Handles some cross-app communication and account syncing. Runs constantly.|Background helper that's not needed. Play Services handles account sync.|Safe to remove. Facebook and Instagram apps still work normally."
  "com.facebook.appmanager|Meta app updater|Handles background updates for Facebook/Instagram/Messenger apps, bypassing Play Store update cycle. Can install/update Meta apps without your explicit consent.|Auto-updates FB apps without consent. Play Store does this anyway with your control.|Safe to remove. Facebook apps update via Play Store like everything else."
)

BATCH4=(
  "com.microsoft.appmanager|Phone Link companion|Microsoft Phone Link (formerly Your Phone) companion app. Lets you text, call, see notifications, and mirror photos from your phone on a Windows PC. Runs in background looking for a paired PC.|Only useful if you use Phone Link on Windows. If you don't, it's wasted RAM and background activity.|Safe to remove. If you later want Phone Link, install it from Play Store. No system functionality breaks."
  "com.microsoft.deviceintegrationservice|Cross-device integration service|Backend service for Phone Link. Handles the actual cross-device communication (notifications sync, file transfer, call relay). Runs in background.|Same as above - only useful with Phone Link on Windows.|Safe to remove. Same as appmanager - reinstall from Play Store if needed later."
  "com.microsoftsdk.crossdeviceservicebroker|SDK broker for Link to Windows|SDK broker that mediates between Phone Link apps and the system. Background service.|Same as above - part of the Phone Link stack.|Safe to remove. Microsoft Word (com.microsoft.office.word) is NOT removed and still works."
)

BATCH5=(
  "com.mi.appfinder|App drawer search bar|The search bar at the top of the app drawer. Indexes your apps AND your app usage patterns. Sends usage data to Xiaomi for 'personalization'. Uses ~298 MB RAM when running.|Spyware-ish; indexes app usage and sends to Xiaomi. Big RAM user (~298 MB).|Safe to remove. App drawer still works, you just lose the search bar at the top. You can still search apps via the global search (swipe down on home screen)."
  "com.mi.globalminusscreen|Minus screen (leftmost home screen page)|The leftmost page on the home screen that shows news, ads, 'recommended' apps, and widgets. Xiaomi sells this as ad inventory. Uses ~255 MB RAM.|Ad surface; rarely used. Big RAM user (~255 MB).|Safe to remove. The leftmost page just disappears. Home screen still works. You can add widgets to other pages."
)

BATCH6=(
  "com.google.android.apps.tachyon|Google Duo/Meet|Google's video calling app (rebranded to Meet). System app that can't be uninstalled normally. Runs in background and uses ~83 MB RAM when active.|Replaced by WhatsApp, Discord, Zoom, or other video calling apps you prefer. Frees ~83 MB RAM.|Safe to remove. If you want it back, install Google Meet from Play Store. No system functionality breaks."
  "com.google.android.apps.youtube.music|YouTube Music (system app)|System version of YouTube Music. Redundant if you use ReVanced YouTube Music, Spotify, or any other music app.|Replaced by ReVanced YouTube Music or other music app.|Safe to remove. If you want it back, install from Play Store. No system functionality breaks."
  "com.google.android.apps.wellbeing|Digital Wellbeing|Google's screen time tracker. Shows app usage time, sets app timers, wind-down mode, focus mode. Uses ~37 MB RAM when running.|Screen time tracker not used. Frees ~37 MB RAM.|Safe to remove. If you want it back, install from Play Store. No system functionality breaks."
  "com.miui.misightservice|Xiaomi MiSight (insights/telemetry)|Xiaomi's insights and telemetry service. Collects device health, feature usage, and system metrics. Phones home to Xiaomi. Uses ~10 MB RAM when running.|Same telemetry category as Joyose (Batch 1). Stops another telemetry channel.|Safe to remove. No user-facing functionality breaks."
  "com.xiaomi.barrage|Xiaomi Barrage (bullet comments)|Danmaku-style floating bullet comments overlay for videos. A Chinese market feature where viewers' comments float across the video. Useless outside China.|Chinese-market feature, useless outside China. Saves a small amount of RAM.|Safe to remove. No video playback functionality breaks. The feature was never useful outside China anyway."
)

BATCH7=(
  "com.tencent.soter.soterserver|Tencent SOTER (biometric auth server)|Tencent's SOTER (Secure Open Standard for Trusted Environment Recognition) biometric authentication server. Chinese industry standard for fingerprint/face login in apps like WeChat, QQ, Tencent games, and some banking apps. Uses ~6 MB RAM when running.|Chinese biometric auth standard for WeChat/QQ. Useless outside China unless you use Chinese apps with biometric login. Frees ~6 MB.|If you use WeChat, QQ, or Chinese banking apps with fingerprint login, do NOT remove this - those apps need it for biometric auth. Outside China and without those apps, it's safe to remove."
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
  echo "Then you choose: 1 (remove), 2 (keep), or 3 (skip rest of batch)."
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
run_one 7 "Chinese biometric auth (Tencent SOTER)" "${BATCH7[@]}"

if [ "$LIST_ONLY" = "1" ]; then
  echo "List-only mode - nothing was changed."
else
  echo "${C_GREEN}Done.${C_RESET} Removed packages are logged in: $LOG_FILE"
  echo "To undo everything:  bash ${SCRIPT_DIR}/restore.sh"
  echo "To undo one package: bash ${SCRIPT_DIR}/restore.sh <pkg>"
fi

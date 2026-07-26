#!/usr/bin/env bash
# ============================================================
# POCO F7 (onyx_global) — Restore script
# ============================================================
# Restores packages removed by debloat.sh.
# Method: pm install-existing --user 0  (re-registers the app from the
# untouched /system APK — no internet needed, instant).
#
# Usage:
#   bash restore.sh                  # restore everything in removed_packages.txt
#   bash restore.sh com.miui.msa.global           # restore one package
#   bash restore.sh com.miui.msa.global com.xiaomi.joyose   # restore several
#   bash restore.sh --batch 2        # restore a specific batch (by number)
#   bash restore.sh --list           # show what would be restored, do nothing
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backup"
LOG_FILE="${BACKUP_DIR}/removed_packages.txt"
LIST_ONLY=0
BATCH_FILTER=""
EXPLICIT_PKGS=()

# Colors
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_RESET=""
fi

# ---------- Pre-flight ----------
if ! command -v adb >/dev/null 2>&1; then
  echo "${C_RED}ERROR: adb not found in PATH${C_RESET}" >&2
  exit 1
fi
if ! adb devices 2>/dev/null | grep -q '\bdevice$'; then
  echo "${C_RED}ERROR: no adb device connected.${C_RESET}" >&2
  echo "Run 'adb devices' to check." >&2
  exit 1
fi

# ---------- Parse args ----------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list|-l) LIST_ONLY=1 ;;
    --batch) BATCH_FILTER="$2"; shift ;;
    --batch=*) BATCH_FILTER="${1#--batch=}" ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) EXPLICIT_PKGS+=("$1") ;;
  esac
  shift
done

# ---------- Restore one package ----------
restore_one() {
  local pkg="$1"
  pkg="${pkg#package:}"   # strip "package:" prefix if present
  [ -z "$pkg" ] && return 0
  case "$pkg" in '#'*) return 0 ;; esac

  # Already installed?
  if adb shell pm list packages --user 0 2>/dev/null | grep -q "^package:${pkg}$"; then
    echo "  ${C_YELLOW}SKIP${C_RESET}  $pkg (already installed for user 0)"
    return 0
  fi

  local out
  out=$(adb shell pm install-existing --user 0 "$pkg" 2>&1)
  if echo "$out" | grep -q 'Success'; then
    echo "  ${C_GREEN}OK${C_RESET}    $pkg"
  else
    # Some packages may only have been disabled, not uninstalled — try enable as fallback
    if adb shell pm enable --user 0 "$pkg" >/dev/null 2>&1; then
      echo "  ${C_GREEN}OK${C_RESET}    $pkg (was disabled, re-enabled)"
    else
      echo "  ${C_RED}FAIL${C_RESET}  $pkg -> $out"
    fi
  fi
}

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
  TARGETS+=($(awk -v b="$BATCH_FILTER" '
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
  ' "$LOG_FILE"))
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    echo "${C_RED}No packages found for batch $BATCH_FILTER in $LOG_FILE${C_RESET}" >&2
    exit 1
  fi
else
  if [ ! -f "$LOG_FILE" ]; then
    echo "${C_RED}ERROR: $LOG_FILE not found — nothing to restore.${C_RESET}" >&2
    exit 1
  fi
  # All non-comment, non-empty lines
  TARGETS+=($(grep -vE '^#|^$' "$LOG_FILE"))
fi

# ---------- Run ----------
echo "${C_CYAN}POCO F7 Restore${C_RESET}"
echo "Device: $(adb shell getprop ro.product.model) ($(adb shell getprop ro.product.name))"
echo "Packages to restore: ${#TARGETS[@]}"
echo ""

if [ "$LIST_ONLY" = "1" ]; then
  for p in "${TARGETS[@]}"; do echo "  would restore: $p"; done
  echo ""
  echo "List-only mode — nothing was changed."
  exit 0
fi

ok=0; fail=0; skip=0
for p in "${TARGETS[@]}"; do
  out=$(adb shell pm install-existing --user 0 "$p" 2>&1)
  if echo "$out" | grep -q 'Success'; then
    echo "  ${C_GREEN}OK${C_RESET}    $p"; ok=$((ok+1))
  elif adb shell pm list packages --user 0 2>/dev/null | grep -q "^package:${p}$"; then
    echo "  ${C_YELLOW}SKIP${C_RESET}  $p (already installed)"; skip=$((skip+1))
  elif adb shell pm enable --user 0 "$p" >/dev/null 2>&1; then
    echo "  ${C_GREEN}OK${C_RESET}    $p (was disabled, re-enabled)"; ok=$((ok+1))
  else
    echo "  ${C_RED}FAIL${C_RESET}  $p -> $out"; fail=$((fail+1))
  fi
done

echo ""
echo "${C_GREEN}Done.${C_RESET} OK=$ok  Skipped=$skip  Failed=$fail"
[ "$fail" -gt 0 ] && echo "${C_YELLOW}Some packages failed — they may have been removed by an OTA update. A factory reset will restore everything.${C_RESET}"

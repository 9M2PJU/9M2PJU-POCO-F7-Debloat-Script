#!/usr/bin/env bash
# Restore all packages removed by the debloat process.
# Reads removed_packages.txt (one package per line, "package:com.foo.bar" or "com.foo.bar")
# and runs `pm install-existing` for each — no internet needed, APKs come from /system.
#
# Usage:
#   bash /home/x/pocof7/backup/restore_all.sh            # restore everything
#   bash /home/x/pocof7/backup/restore_all.sh <pkg> ...   # restore specific packages

set -u

PKG_FILE="/home/x/pocof7/backup/removed_packages.txt"
DEVICE_USER="0"

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: adb not found in PATH" >&2
  exit 1
fi

if ! adb devices | grep -q 'device$'; then
  echo "ERROR: no adb device connected (run 'adb devices' to check)" >&2
  exit 1
fi

restore_one() {
  local pkg="$1"
  pkg="${pkg#package:}"   # strip "package:" prefix if present
  if [ -z "$pkg" ]; then return 0; fi
  printf "  -> %-45s " "$pkg"
  if adb shell pm install-existing --user "$DEVICE_USER" "$pkg" 2>&1 | grep -q 'Success'; then
    echo "OK"
  else
    # Some packages may already be installed or only disable-able; try enable as fallback.
    if adb shell pm enable --user "$DEVICE_USER" "$pkg" >/dev/null 2>&1; then
      echo "OK (was disabled, re-enabled)"
    else
      echo "FAILED (check manually)"
    fi
  fi
}

if [ "$#" -gt 0 ]; then
  echo "Restoring $# specific package(s):"
  for p in "$@"; do restore_one "$p"; done
else
  if [ ! -f "$PKG_FILE" ]; then
    echo "ERROR: $PKG_FILE not found — nothing to restore." >&2
    exit 1
  fi
  total=$(grep -c . "$PKG_FILE" 2>/dev/null || echo 0)
  echo "Restoring $total package(s) from $PKG_FILE ..."
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    case "$pkg" in '#'*) continue ;; esac
    restore_one "$pkg"
  done < "$PKG_FILE"
fi

echo "Done."

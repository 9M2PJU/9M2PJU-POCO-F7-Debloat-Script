#!/usr/bin/env bash
# ============================================================
# POCO F7 Debloat — One-liner installer
# ============================================================
# Downloads debloat.sh and restore.sh from the GitHub repo and
# runs debloat.sh interactively. Safe to re-run; existing files
# are overwritten with the latest version.
#
# One-liner usage:
#   curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash
#
# Or, to just download without running:
#   curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash -s -- --no-run
#
# Or, to download to a specific directory:
#   curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash -s -- --dir ~/poco-f7
# ============================================================

set -u

REPO_RAW="https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main"
TARGET_DIR="$(pwd)"
RUN_AFTER=1
LIST_ONLY=0
PASS_ARGS=()

# Colors
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_RESET=""
fi

# ---------- Parse args ----------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-run) RUN_AFTER=0 ;;
    --list|-l) LIST_ONLY=1; RUN_AFTER=0 ;;
    --dir) TARGET_DIR="$2"; shift ;;
    --dir=*) TARGET_DIR="${1#--dir=}" ;;
    --yes|-y) PASS_ARGS+=("--yes") ;;
    --batch) PASS_ARGS+=("--batch" "$2"); shift ;;
    -h|--help)
      sed -n '2,20p' "$0" 2>/dev/null || true
      exit 0 ;;
    *) PASS_ARGS+=("$1") ;;
  esac
  shift
done

# ---------- Pre-flight ----------
if ! command -v curl >/dev/null 2>&1; then
  echo "${C_RED}ERROR: curl not found in PATH${C_RESET}" >&2
  exit 1
fi
if ! command -v adb >/dev/null 2>&1; then
  echo "${C_RED}ERROR: adb not found in PATH${C_RESET}" >&2
  echo "Install Android Platform Tools first:" >&2
  echo "  Debian/Ubuntu:  sudo apt install adb" >&2
  echo "  Arch:           sudo pacman -S android-tools" >&2
  echo "  macOS:          brew install android-platform-tools" >&2
  echo "  Or download:    https://developer.android.com/tools/releases/platform-tools" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR" || { echo "${C_RED}ERROR: cannot cd to $TARGET_DIR${C_RESET}" >&2; exit 1; }

# ---------- Download ----------
echo "${C_CYAN}POCO F7 Debloat — installer${C_RESET}"
echo "Target dir: $(pwd)"
echo ""

for f in debloat.sh restore.sh; do
  printf "  Downloading %-15s ... " "$f"
  if curl -fsSL "${REPO_RAW}/${f}" -o "${f}.new" 2>/dev/null; then
    mv "${f}.new" "$f"
    chmod +x "$f"
    echo "${C_GREEN}OK${C_RESET}"
  else
    rm -f "${f}.new"
    echo "${C_RED}FAILED${C_RESET}"
    exit 1
  fi
done

echo ""
echo "${C_GREEN}Downloaded:${C_RESET}"
echo "  $(pwd)/debloat.sh   ($(wc -l < debloat.sh) lines)"
echo "  $(pwd)/restore.sh   ($(wc -l < restore.sh) lines)"
echo ""

if [ "$RUN_AFTER" = "1" ]; then
  if [ "${#PASS_ARGS[@]}" -gt 0 ]; then
    echo "${C_CYAN}Running: bash debloat.sh ${PASS_ARGS[*]}${C_RESET}"
    bash debloat.sh "${PASS_ARGS[@]}"
  else
    echo "${C_CYAN}Running: bash debloat.sh${C_RESET}"
    bash debloat.sh
  fi
elif [ "$LIST_ONLY" = "1" ]; then
  echo "${C_CYAN}Running: bash debloat.sh --list${C_RESET}"
  bash debloat.sh --list
else
  echo "${C_GREEN}Done.${C_RESET} Run with:  bash $(pwd)/debloat.sh"
  echo "Restore with: bash $(pwd)/restore.sh"
fi

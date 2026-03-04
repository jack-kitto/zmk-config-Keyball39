#!/usr/bin/env bash
#
# install.sh - Interactive ZMK flasher for Nice!Nano
#

set -euo pipefail

# ================= CONFIG =================

REPO="jack-kitto/zmk-config-Keyball39"
NICE_VOLUME_PREFIX="NICENANO 1"
MOUNT_ROOT="/Volumes"

TMP_DIR=""

# ================= COLORS =================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ================= CLEANUP =================

cleanup() {
  if [[ -n "$TMP_DIR" ]] && [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT

# ================= UTIL =================

die() {
  echo -e "${RED}❌ $*${NC}" >&2
  exit 1
}

info() {
  echo -e "${BLUE}ℹ️  $*${NC}"
}

success() {
  echo -e "${GREEN}✅ $*${NC}"
}

warn() {
  echo -e "${YELLOW}⚠️  $*${NC}"
}

header() {
  clear
  echo -e "${BOLD}${CYAN}"
  echo "╔═══════════════════════════════════════════╗"
  echo "║   ZMK Firmware Interactive Installer      ║"
  echo "╚═══════════════════════════════════════════╝"
  echo -e "${NC}"
}

press_any_key() {
  echo
  read -n 1 -s -r -p "Press any key to continue..."
  echo
}

find_nicenano_volume() {
  for vol in "$MOUNT_ROOT"/*; do
    if [[ -d "$vol" ]] &&
      [[ "$(basename "$vol")" == $NICE_VOLUME_PREFIX* ]]; then
      echo "$vol"
      return 0
    fi
  done
  return 1
}

wait_for_board() {
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  local vol=""

  while true; do
    if vol=$(find_nicenano_volume); then
      printf "\r\033[K" >&2
      echo "$vol"
      return 0
    fi

    printf "\r%s  Waiting for Nice!Nano in bootloader mode..." \
      "${spinner[$i]}" >&2

    i=$(((i + 1) % ${#spinner[@]}))
    sleep 0.1
  done
}

wait_for_disconnect() {
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  local timeout=50 # 5 seconds (0.1 * 50)

  while find_nicenano_volume >/dev/null 2>&1; do
    printf "\r%s  Waiting for flash to complete..." \
      "${spinner[$i]}" >&2
    i=$(((i + 1) % ${#spinner[@]}))
    sleep 0.1
    timeout=$((timeout - 1))

    if [[ $timeout -le 0 ]]; then
      printf "\r\033[K" >&2
      warn "Device did not auto-disconnect. Flash may have failed."
      return 1
    fi
  done

  printf "\r\033[K" >&2
  return 0
}

# ================= DOWNLOAD =================

check_dependencies() {
  if ! command -v gh >/dev/null 2>&1; then
    die "GitHub CLI (gh) is required.
Install with: brew install gh
Then run: gh auth login"
  fi

  # Check authentication by calling GitHub API
  if ! gh api user >/dev/null 2>&1; then
    die "GitHub CLI is not authenticated.
Run: gh auth login"
  fi
}

download_latest_artifact() {
  info "Fetching latest successful build from build.yml..."

  # Get latest successful run from specific workflow file
  RUN_ID=$(gh run list \
    --repo "$REPO" \
    --workflow build.yml \
    --status success \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId' 2>/dev/null) || true

  if [[ -z "$RUN_ID" ]] || [[ "$RUN_ID" == "null" ]]; then
    die "No successful runs found for workflow build.yml"
  fi

  # Get run info for display
  RUN_INFO=$(gh run view "$RUN_ID" \
    --repo "$REPO" \
    --json headBranch,createdAt,displayTitle \
    --jq '"\(.displayTitle) (\(.headBranch)) - \(.createdAt)"' \
    2>/dev/null) || true

  success "Found build run: $RUN_ID"
  if [[ -n "$RUN_INFO" ]]; then
    info "Build: $RUN_INFO"
  fi

  echo
  info "Downloading artifacts..."

  TMP_DIR="$(mktemp -d)"

  if ! gh run download "$RUN_ID" \
    --repo "$REPO" \
    --dir "$TMP_DIR" 2>/dev/null; then
    die "Failed to download artifacts from run $RUN_ID"
  fi

  success "Artifacts downloaded."

  # macOS Bash 3 compatible UF2 detection
  UF2_FILES=$(find "$TMP_DIR" -type f -name "*.uf2" 2>/dev/null)

  if [[ -z "$UF2_FILES" ]]; then
    die "No .uf2 files found in downloaded artifacts.
Contents of download:
$(find "$TMP_DIR" -type f)"
  fi

  echo
  info "Available firmware files:"
  echo "$UF2_FILES" | while read -r f; do
    echo "   - $(basename "$f")"
  done
}

# ================= FLASHING =================

find_firmware() {
  local pattern="$1"
  local result=""

  result=$(find "$TMP_DIR" -type f -name "*.uf2" 2>/dev/null | grep -i "$pattern" | head -n 1) || true

  if [[ -z "$result" ]]; then
    return 1
  fi

  echo "$result"
}

flash_half() {
  local label="$1"
  local pattern="$2"

  header
  echo -e "${BOLD}Flashing: $label${NC}"
  echo
  echo "┌─────────────────────────────────────────┐"
  echo "│  1) Plug in the $label half"
  echo "│  2) Double-tap RESET to enter bootloader"
  echo "└─────────────────────────────────────────┘"
  echo

  # Find firmware first
  firmware=$(find_firmware "$pattern") ||
    die "Could not find firmware matching: $pattern\n   Available files:\n$(find "$TMP_DIR" -type f -name "*.uf2")"

  info "Will flash: $(basename "$firmware")"
  echo

  vol=$(wait_for_board)

  echo
  info "Copying firmware to device..."

  TARGET="$vol/$(basename "$firmware")"

  if cp -X "$firmware" "$TARGET" 2>/dev/null; then
    :
  else
    warn "Permission denied. Retrying with sudo..."
    sudo cp -X "$firmware" "$TARGET"
  fi

  sync 2>/dev/null || true

  echo
  wait_for_disconnect
  if wait_for_disconnect; then
    success "$label half flashed successfully!"
  else
    die "Flashing did not complete properly."
  fi

  echo
  success "$label half flashed successfully!"
  echo
  echo -e "${CYAN}You may now unplug the $label half.${NC}"

  sleep 1
}

# ================= MENU =================

show_menu() {
  echo
  echo -e "${BOLD}What would you like to flash?${NC}"
  echo
  echo "  1) Both halves (Left + Right)"
  echo "  2) Left half only"
  echo "  3) Right half only"
  echo "  4) Reset both halves (clear settings)"
  echo "  5) Reset left half only"
  echo "  6) Reset right half only"
  echo
  echo "  q) Quit"
  echo
}

# ================= MAIN =================

main() {
  header
  echo -e "Repository: ${CYAN}$REPO${NC}"
  echo

  check_dependencies
  download_latest_artifact

  show_menu
  read -r -p "Select option: " choice
  echo

  case "$choice" in
  1)
    flash_half "LEFT" "left"
    press_any_key
    flash_half "RIGHT" "right"
    ;;
  2)
    flash_half "LEFT" "left"
    ;;
  3)
    flash_half "RIGHT" "right"
    ;;
  4)
    flash_half "LEFT (RESET)" "reset"
    press_any_key
    flash_half "RIGHT (RESET)" "reset"
    ;;
  5)
    flash_half "LEFT (RESET)" "reset"
    ;;
  6)
    flash_half "RIGHT (RESET)" "reset"
    ;;
  q | Q)
    info "Exiting."
    exit 0
    ;;
  *)
    die "Invalid selection: $choice"
    ;;
  esac

  header
  echo
  echo -e "${GREEN}${BOLD}🎉 All done!${NC}"
  echo
  echo "Firmware has been flashed successfully."
  echo "Temporary files have been cleaned up."
  echo
}

main "$@"

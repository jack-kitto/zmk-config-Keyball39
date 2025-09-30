#!/usr/bin/env bash
#
# flash_zmk.sh - A robust script to flash ZMK firmware (.uf2) files
# onto Nice!Nano boards on macOS.
#
# Usage:
#   ./install.sh left
#   ./install.sh right
#   ./install.sh reset
#

set -euo pipefail

# === CONFIG ===
NICE_VOLUME_PREFIX="NICENANO"
MOUNT_ROOT="/Volumes"

# Default firmware paths (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="$SCRIPT_DIR/firmware"

LEFT_FIRMWARE="$FIRMWARE_DIR/keyball39_left.uf2"
RIGHT_FIRMWARE="$FIRMWARE_DIR/keyball39_right.uf2"
RESET_FIRMWARE="$FIRMWARE_DIR/settings_reset.uf2"

# === FUNCTIONS ===

die() {
  echo "❌ Error: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $0 left
  $0 right

It will look for:
  Left firmware:  $LEFT_FIRMWARE
  Right firmware: $RIGHT_FIRMWARE
  Reset firmware: $RESET_FIRMWARE
EOF
  exit 1
}

find_nicenano_volume() {
  local -r vols=("$MOUNT_ROOT"/*)
  for vol in "${vols[@]}"; do
    if [[ -d "$vol" ]] && [[ "$(basename "$vol")" == $NICE_VOLUME_PREFIX* ]]; then
      echo "$vol"
      return 0
    fi
  done
  return 1
}

flash_firmware() {
  local input="$1"
  local firmware="$2"

  [[ -f "$firmware" ]] || die "Firmware file not found: $firmware"

  echo "🔎 Searching for mounted Nice!Nano..."
  if ! vol=$(find_nicenano_volume); then
    die "No Nice!Nano detected. Put the board in bootloader mode (double-tap reset), then try again."
  fi

  echo "✅ Detected Nice!Nano at: $vol"
  echo "➡️  Flashing $input firmware: $firmware"

  cp "$firmware" "$vol/"
  sync
  echo "✅ Successfully flashed $input firmware!"
}

# === MAIN ===
[[ $# -eq 1 ]] || usage

INPUT="$1"

case "$INPUT" in
left) flash_firmware "left" "$LEFT_FIRMWARE" ;;
right) flash_firmware "right" "$RIGHT_FIRMWARE" ;;
reset) flash_firmware "reset" "$RESET_FIRMWARE" ;;
*) die "Invalid input: $INPUT (must be 'left', 'right' or 'reset')" ;;
esac

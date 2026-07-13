#!/usr/bin/env bash
set -euo pipefail

# === SETTINGS ===
BOARD="nice_nano"
DOCKER_IMAGE="zmkfirmware/zmk-build-arm:3.5-branch"

# Shields to build
SHIELDS=("keyball39_left" "keyball39_right" "settings_reset")

# Output folder
OUTPUT_DIR="$(pwd)/firmware"
mkdir -p "$OUTPUT_DIR"

echo "[*] Building ZMK locally with Docker"
echo "[*] Shields: ${SHIELDS[*]}"

docker run --rm \
  --security-opt label=disable \
  -v "$(pwd)":/workspace \
  -w /workspace \
  "$DOCKER_IMAGE" \
  bash -c "
	set -euo pipefail

	BASE=/workspace/.zmk-build-tmp
	rm -rf \"\$BASE/config\"
	mkdir -p \"\$BASE/config\"
	cp -R /workspace/config/. \"\$BASE/config/\"

	cd \"\$BASE\"

	if [ ! -f .west/config ]; then
	  echo '[*] Fresh west init'
	  west init -l config
	  west update
	else
	  echo '[*] Existing west workspace found, skipping init'
	  west update
	fi

	west zephyr-export

	echo '[*] Building shields'
	for shield in ${SHIELDS[*]}; do
	  echo
	  echo \"=== Building \$shield ===\"

	  # Only wipe the shield’s build dir, not the whole workspace
	  rm -rf /workspace/build/\$shield

	  snippet_args=''
	  if [ \"\$shield\" = keyball39_right ]; then
	    snippet_args='-S studio-rpc-usb-uart'
	  fi

	  west build -d /workspace/build/\$shield \
	    -b '$BOARD' \
	    -s \"\$BASE/zmk/app\" \
	    \$snippet_args \
	    -- -DSHIELD=\$shield -DZMK_CONFIG=\"\$BASE/config\"

	  if [ -f /workspace/build/\$shield/zephyr/zmk.uf2 ]; then
        cp /workspace/build/\$shield/zephyr/zmk.uf2 /workspace/firmware/\${shield}.uf2
        echo \"[✓] Successfully built \$shield\"
      else
        echo \"[!] Failed to build \$shield\"
      fi
    done

    echo '[*] Final firmware directory:'
    ls -lh /workspace/firmware
  "

echo
echo "[*] Build complete. Firmware files:"
ls -lh "$OUTPUT_DIR" || echo "(No firmware files found)"

#!/usr/bin/env bash
# Runs tests/coop_test.gd as a host and a guest against a rooms server that is already up
# (node tools/dev_relay.mjs <scareathon-v3/server> 3111). Prints both copies' checks.
#
#     tools/coop_test.sh [server url]
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
SERVER="${1:-http://127.0.0.1:3111}"
OUT="${TEMP:-/tmp}"
CODE_FILE="$OUT/ov_room_$RANDOM.txt"

timeout 170 "$GODOT" --headless --path . -s res://tests/coop_test.gd -- host "$CODE_FILE" "--server=$SERVER" > "$OUT/ov_host.log" 2>&1 &
sleep 1
timeout 170 "$GODOT" --headless --path . -s res://tests/coop_test.gd -- guest "$CODE_FILE" "--server=$SERVER" > "$OUT/ov_guest.log" 2>&1
wait
grep -hE "PASS|FAIL|COOP|ERROR|at:" "$OUT/ov_host.log" "$OUT/ov_guest.log"
! grep -qE "FAIL|ERROR" "$OUT/ov_host.log" "$OUT/ov_guest.log"

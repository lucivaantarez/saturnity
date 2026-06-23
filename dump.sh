#!/usr/bin/env bash
# dump.sh — fetch the confirmed-live user-settings endpoints and print full JSON.
# GET-only, read-only. Fixes the /tmp issue (uses mktemp). Run: ./dump.sh
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/config.sh" ] && . "$SCRIPT_DIR/config.sh"
: "${UA:=Mozilla/5.0 (Linux; Android 13) Mobile}"

RAW="$(curl -fsSL -H "User-Agent: $UA" "$ACCOUNTS_URL" 2>/dev/null)"
LINE="$(printf '%s\n' "$RAW" | grep -vE '^\s*($|#)' | head -1 | tr -d '\r')"
rest="${LINE#*:}"; COOKIE="${rest#*:}"

pretty() { # pretty-print JSON if python available, else raw
  if command -v python3 >/dev/null 2>&1; then python3 -m json.tool 2>/dev/null || cat
  elif command -v jq >/dev/null 2>&1; then jq . 2>/dev/null || cat
  else cat; fi
}

dump() {
  local name="$1" url="$2" out
  out="$(mktemp)"
  local code
  code=$(curl -sS -o "$out" -w '%{http_code}' \
    -H "Cookie: .ROBLOSECURITY=$COOKIE" -H "User-Agent: $UA" "$url" 2>/dev/null)
  echo "============================================================"
  echo "[$code] $name"
  echo "    $url"
  echo "------------------------------------------------------------"
  pretty < "$out"
  echo
  cp "$out" "$SCRIPT_DIR/dump_${name}.json"
  rm -f "$out"
}

# the 200 hit — full settings + valid options for each
dump "settings_and_options" "https://apis.roblox.com/user-settings-api/v1/user-settings/settings-and-options"

# the 400 hit — print its body too; the error usually states what it expects
dump "user_settings" "https://apis.roblox.com/user-settings-api/v1/user-settings"

echo "============================================================"
echo "saved: dump_settings_and_options.json , dump_user_settings.json"
echo "Paste the settings_and_options output back — that has the field names + values."

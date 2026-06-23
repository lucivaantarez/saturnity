#!/usr/bin/env bash
# probe2.sh — confirm the WRITE mechanism for user-settings.
# Grabs the RBXEventTrackerV2 cookie, reads /v1/user-settings properly, then does a
# NO-OP write (writes the value the account ALREADY has -> zero real change) to learn
# which method + body shape Roblox accepts. Safe. Run: ./probe2.sh
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/config.sh" ] && . "$SCRIPT_DIR/config.sh"
: "${UA:=Mozilla/5.0 (Linux; Android 13) Mobile}"

GREEN=$'\033[92m'; YELLOW=$'\033[93m'; RED=$'\033[91m'; CYAN=$'\033[96m'; BOLD=$'\033[1m'; DIM=$'\033[90m'; RESET=$'\033[0m'
[ -t 1 ] || { GREEN=; YELLOW=; RED=; CYAN=; BOLD=; DIM=; RESET=; }

RAW="$(curl -fsSL -H "User-Agent: $UA" "$ACCOUNTS_URL" 2>/dev/null)"
LINE="$(printf '%s\n' "$RAW" | grep -vE '^\s*($|#)' | head -1 | tr -d '\r')"
rest="${LINE#*:}"; COOKIE="${rest#*:}"
US="https://apis.roblox.com/user-settings-api/v1/user-settings"

# ---- 1) grab RBXEventTrackerV2 cookie (carries BrowserTrackerID) ----
printf "${BOLD}1) getting browser tracker cookie${RESET}\n"
HDRS="$(curl -sS -D - -o /dev/null -H "Cookie: .ROBLOSECURITY=$COOKIE" -H "User-Agent: $UA" "https://www.roblox.com/home" 2>/dev/null)"
TRK="$(printf '%s' "$HDRS" | grep -i 'set-cookie: *RBXEventTrackerV2=' | sed -E 's/.*RBXEventTrackerV2=([^;]*).*/\1/' | tail -1 | tr -d '\r')"
if [ -z "$TRK" ]; then
  TRK="CreateDate=$(date -u +%Y-%m-%dT%H:%M:%S).000Z&browserid=$(( $(date +%s)000 + RANDOM ))"
  printf "   ${YELLOW}no cookie returned — synthesized: %s${RESET}\n" "${TRK:0:60}"
else
  printf "   ${GREEN}got it:${RESET} %s\n" "${TRK:0:60}"
fi
CK=".ROBLOSECURITY=$COOKIE; RBXEventTrackerV2=$TRK"

req() { # method url data  -> sets R_CODE / R_BODY, captures CSRF into R_CSRF
  local m="$1" u="$2" d="$3" hdr body
  hdr="$(mktemp)"; body="$(mktemp)"
  if [ "$m" = "GET" ]; then
    R_CODE=$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}' -H "Cookie: $CK" -H "User-Agent: $UA" "$u" 2>/dev/null)
  else
    R_CODE=$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}' -X "$m" -H "Cookie: $CK" -H "User-Agent: $UA" \
      -H "Content-Type: application/json" -H "X-CSRF-Token: $R_CSRF" --data "$d" "$u" 2>/dev/null)
  fi
  R_BODY="$(cat "$body")"
  local t; t=$(grep -i '^x-csrf-token:' "$hdr" | tr -d '\r' | awk '{print $2}' | head -1)
  [ -n "$t" ] && R_CSRF="$t"
  rm -f "$hdr" "$body"
}

# ---- 2) read /v1/user-settings with the tracker ----
printf "\n${BOLD}2) GET /v1/user-settings (with tracker)${RESET}\n"
req GET "$US"
printf "   [%s] %s\n" "$R_CODE" "${R_BODY:0:300}"

# ---- 3) get CSRF (tokenless POST -> 403 hands us the token) ----
printf "\n${BOLD}3) fetching CSRF${RESET}\n"
R_CSRF=""
req POST "$US" '{}'
printf "   token: ${CYAN}%s${RESET}  (probe POST returned %s)\n" "${R_CSRF:-<none>}" "$R_CODE"

# ---- 4) NO-OP write tests: write Friends (current value) to online status ----
printf "\n${BOLD}4) no-op write shape tests (writing the value it already has)${RESET}\n"
test_write() {
  local label="$1" method="$2" url="$3" data="$4"
  req "$method" "$url" "$data"
  [ "$R_CODE" = "403" ] && req "$method" "$url" "$data"   # retry once with fresh token
  local col="$DIM"; case "$R_CODE" in 2*) col="$GREEN";; 400|422) col="$YELLOW";; esac
  printf "   ${col}%-4s${RESET} %-7s ${DIM}%s${RESET}\n" "$R_CODE" "$method" "$label"
  printf "        ${DIM}body:${RESET} %s\n" "${R_BODY:0:200}"
}
test_write "flat POST {field:val}"            POST  "$US" '{"whoCanSeeMyOnlineStatus":"Friends"}'
test_write "flat PATCH {field:val}"           PATCH "$US" '{"whoCanSeeMyOnlineStatus":"Friends"}'
test_write "wrapped POST {settings:{...}}"    POST  "$US" '{"settings":{"whoCanSeeMyOnlineStatus":"Friends"}}'
test_write "per-setting POST .../{name}"      POST  "$US/whoCanSeeMyOnlineStatus" '{"value":"Friends"}'

echo
printf "${CYAN}Paste this back. The green 2xx line = the write shape we use. Then I finalize config.sh.${RESET}\n"

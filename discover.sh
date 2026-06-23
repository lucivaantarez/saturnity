#!/usr/bin/env bash
# discover.sh — read-only endpoint finder for the three privacy settings.
# GET-only. Never writes anything. Safe to run on a live account.
# Run once, paste the output back, and we lock the real endpoints into config.sh.
#
# Put next to config.sh and run:  ./discover.sh

set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/config.sh" ] && . "$SCRIPT_DIR/config.sh"
: "${UA:=Mozilla/5.0 (Linux; Android 13) Mobile}"

DIM=$'\033[90m'; GREEN=$'\033[92m'; YELLOW=$'\033[93m'; RED=$'\033[91m'; CYAN=$'\033[96m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
[ -t 1 ] || { DIM=; GREEN=; YELLOW=; RED=; CYAN=; BOLD=; RESET=; }

# ---- get a cookie: first account from ACCOUNTS_URL ----
if [ -z "$ACCOUNTS_URL" ]; then echo "no ACCOUNTS_URL (config.sh missing?)"; exit 1; fi
echo "fetching first account ..."
RAW="$(curl -fsSL -H "User-Agent: $UA" "$ACCOUNTS_URL" 2>/dev/null)"
LINE="$(printf '%s\n' "$RAW" | grep -vE '^\s*($|#)' | head -1 | tr -d '\r')"
[ -z "$LINE" ] && { echo "no account found"; exit 1; }
rest="${LINE#*:}"; COOKIE="${rest#*:}"

GET() { # GET url -> prints [code] snippet ; echoes code to stdout via global
  G_CODE=$(curl -sS -o /tmp/_d_body -w '%{http_code}' \
    -H "Cookie: .ROBLOSECURITY=$COOKIE" -H "User-Agent: $UA" "$1" 2>/dev/null)
  G_BODY="$(tr -d '\n' < /tmp/_d_body)"
}

hit() { # pretty print a swept endpoint
  local url="$1"; GET "$url"
  local col="$DIM"; case "$G_CODE" in 2*) col="$GREEN";; 401|403) col="$YELLOW";; esac
  printf "  ${col}%-4s${RESET} ${DIM}%s${RESET}\n" "$G_CODE" "$url"
  case "$G_CODE" in 2*) printf "       ${CYAN}%s${RESET}\n" "${G_BODY:0:240}";; esac
}

echo
printf "${BOLD}== validating cookie ==${RESET}\n"
GET "https://users.roblox.com/v1/users/authenticated"
if [ "$G_CODE" != "200" ]; then echo "cookie invalid ($G_CODE) — fix accounts.txt"; exit 1; fi
printf "  ${GREEN}ok${RESET} %s\n" "${G_BODY:0:120}"

# ============================================================
#  PASS 1 — pull Roblox's own API spec (lists real endpoints)
# ============================================================
echo
printf "${BOLD}== PASS 1: API spec discovery ==${RESET}\n"
SPECS=(
  "https://accountsettings.roblox.com/docs/json/v1"
  "https://accountsettings.roblox.com/swagger/v1/swagger.json"
  "https://apis.roblox.com/user-settings-api/docs/json/v1"
  "https://apis.roblox.com/user-settings-api/swagger/v1/swagger.json"
  "https://apis.roblox.com/privacy-settings-api/docs/json/v1"
)
FOUND_SPEC=""
for sp in "${SPECS[@]}"; do
  GET "$sp"
  printf "  ${DIM}%-4s %s${RESET}\n" "$G_CODE" "$sp"
  if [ "${G_CODE:0:1}" = "2" ] && printf '%s' "$G_BODY" | grep -q '"paths"\|"/v'; then
    FOUND_SPEC="$G_BODY"
    echo "$G_BODY" > "$SCRIPT_DIR/discover_spec.json"
    printf "  ${GREEN}↑ spec saved to discover_spec.json${RESET}\n"
    printf "  ${BOLD}relevant paths:${RESET}\n"
    printf '%s' "$G_BODY" | grep -oE '"/[a-zA-Z0-9/_{}.-]+"' \
      | grep -iE 'privacy|visib|online|status|experience|private-?server|presence|connection' \
      | sort -u | sed "s/^/    ${GREEN}/; s/\$/${RESET}/"
  fi
done
[ -z "$FOUND_SPEC" ] && printf "  ${YELLOW}no spec reachable — moving to path sweep${RESET}\n"

# ============================================================
#  PASS 2 — sweep likely current read endpoints (GET only)
# ============================================================
echo
printf "${BOLD}== PASS 2: endpoint sweep (read-only) ==${RESET}\n"
printf "${DIM}  green 2xx = live & readable · yellow = exists but auth/method · grey = nope${RESET}\n\n"

ENDPOINTS=(
  # legacy sanity checks (prove cookie+domain mechanics work)
  "https://accountsettings.roblox.com/v1/inventory-privacy"
  "https://accountsettings.roblox.com/v1/trade-privacy"
  "https://accountsettings.roblox.com/v1/app-chat-privacy"
  # combined blobs
  "https://accountsettings.roblox.com/v1/account/settings/json"
  "https://accountsettings.roblox.com/v2/account/settings/json"
  "https://accountsettings.roblox.com/v1/privacy"
  "https://accountsettings.roblox.com/v1/settings"
  "https://accountsettings.roblox.com/v1/user-settings"
  # online status / presence visibility candidates
  "https://accountsettings.roblox.com/v1/online-status"
  "https://accountsettings.roblox.com/v1/online-status-privacy"
  "https://accountsettings.roblox.com/v1/presence-privacy"
  "https://accountsettings.roblox.com/v1/visibility"
  "https://accountsettings.roblox.com/v1/visibility-settings"
  "https://accountsettings.roblox.com/v1/who-can-see-my-online-status"
  # current experience visibility
  "https://accountsettings.roblox.com/v1/experience-privacy"
  "https://accountsettings.roblox.com/v1/game-join-privacy"
  # private server invite
  "https://accountsettings.roblox.com/v1/private-server-privacy"
  "https://accountsettings.roblox.com/v1/private-server-invite-privacy"
  # newer apis.roblox.com gateway candidates
  "https://apis.roblox.com/user-settings-api/v1/user-settings"
  "https://apis.roblox.com/user-settings-api/v1/settings"
  "https://apis.roblox.com/user-settings-api/v1/privacy"
  "https://apis.roblox.com/user-settings-api/v1/user-settings/settings-and-options"
  "https://apis.roblox.com/privacy-settings-api/v1/settings"
  "https://apis.roblox.com/privacy-settings-api/v1/privacy-settings"
)
for e in "${ENDPOINTS[@]}"; do hit "$e"; done

rm -f /tmp/_d_body
echo
printf "${BOLD}== done ==${RESET}\n"
printf "${CYAN}Paste everything above back. Any green 2xx (esp. from PASS 1 paths or a\n"
printf "combined/settings blob) tells us the real field names + values to lock in.${RESET}\n"

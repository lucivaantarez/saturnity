#!/usr/bin/env bash
# privacytoggle.sh — v1.3.0  (engine)
# Sequential per-account Roblox privacy toggler (cookie auth).
# Toggles three settings together: Online status, Current experience, Private servers.
# Runs on Termux / MatePad. No logout endpoint is ever called — cookies stay valid.
# Settings live in config.sh (kept separate so --update never clobbers them).
#
# Run with no args for the interactive menu, or use a shortcut flag:
#   ./privacytoggle.sh            # interactive menu
#   ./privacytoggle.sh --on       # set all three to Friends only
#   ./privacytoggle.sh --off      # set all three to Everyone
#   ./privacytoggle.sh --status   # read-only status of every account
#   ./privacytoggle.sh --update   # pull latest engine from repo
#   add --debug to any for raw request/response dumps

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/config.sh" ]; then
  echo "config.sh not found next to the script ($SCRIPT_DIR)."; exit 1
fi
# shellcheck source=/dev/null
. "$SCRIPT_DIR/config.sh"
: "${DELAY:=3}"; : "${BACKOFF:=30}"; : "${UA:=Mozilla/5.0}"; : "${SELF_REPO_RAW:=}"

DIM=$'\033[90m'; WHITE=$'\033[97m'; BOLD=$'\033[1m'
GREEN=$'\033[92m'; YELLOW=$'\033[93m'; RED=$'\033[91m'; CYAN=$'\033[96m'
RESET=$'\033[0m'
if [ ! -t 1 ]; then DIM=; WHITE=; BOLD=; GREEN=; YELLOW=; RED=; CYAN=; RESET=; fi

FLAG=""; DEBUG=0
HTTP_CODE=""; HTTP_BODY=""; CSRF=""; COOKIE=""; TRK=""; CK=""
ACCS=(); TOTAL=0
R0=""; R1=""; R2=""

for a in "$@"; do
  case "$a" in
    --on)     FLAG="on" ;;
    --off)    FLAG="off" ;;
    --status) FLAG="status" ;;
    --update) FLAG="update" ;;
    --debug)  DEBUG=1 ;;
    --url=*)  ACCOUNTS_URL="${a#--url=}" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $a"; exit 1 ;;
  esac
done

# ---- helpers ----
hr()  { printf "  ${DIM}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}\n"; }
dbg() { [ "$DEBUG" -eq 1 ] && printf "  ${DIM}· %s${RESET}\n" "$1"; }
banner() {
  printf "${DIM}┌────────────────────────────────────────┐${RESET}\n"
  printf "${DIM}│${RESET} ${BOLD}PRIVACY TOGGLE${RESET}              ${DIM}v1.3.0      │${RESET}\n"
  printf "${DIM}│${RESET} ${DIM}accounts.txt · sequential · no logout   │${RESET}\n"
  printf "${DIM}└────────────────────────────────────────┘${RESET}\n"
}
json_val() {
  printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed 's/.*:[[:space:]]*"//; s/"$//'
}
in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
live()  { printf "          %-22s${DIM}...${RESET} ${CYAN}running${RESET}" "$1"; }
done_() { printf "\r\033[K          %-22s${DIM}...${RESET} %b%s${RESET}\n" "$1" "$2" "$3"; }
state_tok() {
  if   [ -z "$1" ];                     then printf "${RED}?${RESET}"
  elif in_list "$1" "$FRIENDS_TOKENS";  then printf "${GREEN}on${RESET}"
  elif in_list "$1" "$EVERYONE_TOKENS"; then printf "${YELLOW}off${RESET}"
  else printf "${YELLOW}%s${RESET}" "$1"; fi
}
trio() { printf '{%b/%b/%b}' "$(state_tok "$R0")" "$(state_tok "$R1")" "$(state_tok "$R2")"; }

get_tracker() {
  local h
  h="$(curl -sS -D - -o /dev/null -H "Cookie: .ROBLOSECURITY=$COOKIE" -H "User-Agent: $UA" "$TRACKER_URL" 2>/dev/null)"
  TRK="$(printf '%s' "$h" | grep -i 'set-cookie: *RBXEventTrackerV2=' | sed -E 's/.*RBXEventTrackerV2=([^;]*).*/\1/' | tail -1 | tr -d '\r')"
  [ -z "$TRK" ] && TRK="CreateDate=$(date -u +%Y-%m-%dT%H:%M:%S).000Z&browserid=$(( $(date +%s)000 + RANDOM ))"
  CK=".ROBLOSECURITY=$COOKIE; RBXEventTrackerV2=$TRK"
}
http() {
  local method="$1" url="$2" data="$3" hdr body code
  hdr="$(mktemp)"; body="$(mktemp)"
  if [ "$method" = "GET" ]; then
    code=$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}' -H "Cookie: $CK" -H "User-Agent: $UA" "$url" 2>/dev/null)
  else
    code=$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}' -X "$method" -H "Cookie: $CK" -H "User-Agent: $UA" \
      -H "Content-Type: application/json" -H "X-CSRF-Token: $CSRF" --data "$data" "$url" 2>/dev/null)
  fi
  HTTP_CODE="$code"; HTTP_BODY="$(cat "$body")"
  local t; t=$(grep -i '^x-csrf-token:' "$hdr" | tr -d '\r' | awk '{print $2}' | head -1)
  [ -n "$t" ] && CSRF="$t"
  rm -f "$hdr" "$body"
  [ "$DEBUG" -eq 1 ] && dbg "$method $url -> $HTTP_CODE  ${HTTP_BODY:0:160}"
}
post_settings() {
  local data="$1"
  http POST "$SETTINGS_URL" "$data"
  [ "$HTTP_CODE" = "403" ] && http POST "$SETTINGS_URL" "$data"
  [ "$HTTP_CODE" = "429" ] && return 42
  case "$HTTP_CODE" in 2*) return 0 ;; *) return 1 ;; esac
}
read_three() {
  http GET "$SETTINGS_URL"
  R0="$(json_val "$HTTP_BODY" "${READ_FIELDS[0]}")"
  R1="$(json_val "$HTTP_BODY" "${READ_FIELDS[1]}")"
  R2="$(json_val "$HTTP_BODY" "${READ_FIELDS[2]}")"
}

# ---- account list ----
fetch_accounts() {
  printf "  ${DIM}fetching accounts.txt ... ${RESET}"
  local raw
  raw="$(curl -fsSL -H "User-Agent: $UA" "$ACCOUNTS_URL" 2>/dev/null)"
  if [ $? -ne 0 ] || [ -z "$raw" ]; then
    printf "${RED}failed${RESET}\n  ${DIM}check ACCOUNTS_URL in config.sh${RESET}\n"; return 1
  fi
  ACCS=(); local line
  while IFS= read -r line; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    ACCS+=("$line")
  done <<< "$raw"
  TOTAL=${#ACCS[@]}
  printf "${GREEN}done (%d accs)${RESET}\n" "$TOTAL"
  return 0
}

# ---- per-account: returns to caller via OK/FAIL counters ----
process_apply() { # $1 body  $2..$4 expected values ; needs entry vars set
  local body="$1" e0="$2" e1="$3" e2="$4"
  CK=".ROBLOSECURITY=$COOKIE"
  live "validating cookie"; http GET "https://users.roblox.com/v1/users/authenticated"
  if [ "$HTTP_CODE" != "200" ]; then
    done_ "validating cookie" "$RED" "invalid cookie"
    printf "          ${RED}✗ skipped${RESET} ${DIM}— authenticated returned %s${RESET}\n\n" "$HTTP_CODE"
    return 1
  fi
  local rn; rn="$(json_val "$HTTP_BODY" "name")"; [ -n "$rn" ] && UNAME="$rn"
  done_ "validating cookie" "$GREEN" "ok"
  live "browser tracker"; get_tracker; done_ "browser tracker" "$GREEN" "ok"
  live "current state"; read_three; done_ "current state" "$RESET" "$(trio)"

  live "applying changes"; post_settings "$body"; local rc=$?
  if [ "$rc" -eq 42 ]; then
    done_ "applying changes" "$YELLOW" "429 — waiting ${BACKOFF}s"; sleep "$BACKOFF"
    live "retrying"; post_settings "$body"; rc=$?
    if [ "$rc" -eq 0 ]; then done_ "retrying" "$GREEN" "ok"; else done_ "retrying" "$RED" "failed (HTTP $HTTP_CODE)"; fi
  elif [ "$rc" -eq 0 ]; then done_ "applying changes" "$GREEN" "ok"
  else done_ "applying changes" "$RED" "failed (HTTP $HTTP_CODE)"; fi
  [ "$DEBUG" -eq 1 ] && dbg "cascade: ${HTTP_BODY:0:160}"
  if [ "$rc" -ne 0 ]; then
    printf "          ${RED}✗ error${RESET} ${DIM}— write rejected (try --debug)${RESET}\n\n"; return 1
  fi
  live "confirming state"; read_three; done_ "confirming state" "$GREEN" "$(trio)"
  if [ "$R0" = "$e0" ] && [ "$R1" = "$e1" ] && [ "$R2" = "$e2" ]; then
    printf "          ${GREEN}✓ done${RESET}\n\n"
  else
    printf "          ${YELLOW}⚠ applied — got %s / %s / %s${RESET} ${DIM}(expected %s / %s / %s)${RESET}\n\n" \
      "$R0" "$R1" "$R2" "$e0" "$e1" "$e2"
  fi
  return 0
}

process_status() {
  CK=".ROBLOSECURITY=$COOKIE"
  live "validating cookie"; http GET "https://users.roblox.com/v1/users/authenticated"
  if [ "$HTTP_CODE" != "200" ]; then
    done_ "validating cookie" "$RED" "invalid cookie"
    printf "          ${RED}✗ skipped${RESET}\n\n"; return 1
  fi
  local rn; rn="$(json_val "$HTTP_BODY" "name")"; [ -n "$rn" ] && UNAME="$rn"
  done_ "validating cookie" "$GREEN" "ok"
  live "browser tracker"; get_tracker; done_ "browser tracker" "$GREEN" "ok"
  live "reading state"; read_three; done_ "reading state" "$RESET" "$(trio)"
  printf "          ${DIM}%s · %s · %s${RESET}\n\n" "$R0" "$R1" "$R2"
  return 0
}

# ---- top-level actions ----
run_action() { # $1 = on|off|status
  local act="$1" body="" e0="" e1="" e2="" label=""
  if [ "$act" = "on" ]; then
    body="$ON_BODY"; e0="${EXPECT_ON[0]}"; e1="${EXPECT_ON[1]}"; e2="${EXPECT_ON[2]}"; label="Friends only"
  elif [ "$act" = "off" ]; then
    body="$OFF_BODY"; e0="${EXPECT_OFF[0]}"; e1="${EXPECT_OFF[1]}"; e2="${EXPECT_OFF[2]}"; label="Everyone"
  fi
  echo
  if [ "$act" = "status" ]; then
    printf "  ${DIM}action :${RESET} ${CYAN}check status${RESET} ${DIM}(read-only)${RESET}\n"
  else
    printf "  ${DIM}action :${RESET} ${YELLOW}${BOLD}set to %s${RESET}  ${DIM}across %d accounts${RESET}\n" "$label" "$TOTAL"
    hr; printf "  ${DIM}proceed? [y/N]${RESET} "; read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) printf "  ${DIM}cancelled${RESET}\n"; return ;; esac
  fi
  hr; echo
  local OK=0 FAIL=0 i=0 entry rest
  for entry in "${ACCS[@]}"; do
    i=$((i+1))
    UNAME="${entry%%:*}"; rest="${entry#*:}"; COOKIE="${rest#*:}"
    [ "$UNAME" = "$entry" ] && { UNAME="(bad-line)"; COOKIE=""; }
    printf "  ${DIM}[%02d/%02d]${RESET} ${BOLD}%s${RESET}\n" "$i" "$TOTAL" "$UNAME"
    CSRF=""
    if [ "$act" = "status" ]; then
      process_status && OK=$((OK+1)) || FAIL=$((FAIL+1))
      [ "$i" -lt "$TOTAL" ] && sleep 1
    else
      process_apply "$body" "$e0" "$e1" "$e2" && OK=$((OK+1)) || FAIL=$((FAIL+1))
      [ "$i" -lt "$TOTAL" ] && sleep "$DELAY"
    fi
  done
  hr
  printf "  ${DIM}progress :${RESET} ${WHITE}%d/%d${RESET}  ${GREEN}✓ %d ok${RESET}  ${RED}✗ %d failed${RESET}\n" "$TOTAL" "$TOTAL" "$OK" "$FAIL"
  hr
}

run_update() {
  [ -z "$SELF_REPO_RAW" ] && { echo "SELF_REPO_RAW not set in config.sh"; return; }
  echo; echo "updating engine from $SELF_REPO_RAW/privacytoggle.sh ..."
  local tmp; tmp="$(mktemp)"
  if curl -fsSL -H "User-Agent: $UA" "$SELF_REPO_RAW/privacytoggle.sh" -o "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$SCRIPT_DIR/privacytoggle.sh"; chmod +x "$SCRIPT_DIR/privacytoggle.sh"
    echo "done — restart the script to load the new version. config.sh untouched."
    exit 0
  else
    rm -f "$tmp"; echo "update failed — check SELF_REPO_RAW and branch name."
  fi
}

# ============================================================
#  ENTRY: flag shortcut, or interactive menu
# ============================================================
if [ -n "$FLAG" ]; then
  banner; echo
  case "$FLAG" in
    update) run_update; exit 0 ;;
  esac
  fetch_accounts || exit 1
  [ "$TOTAL" -eq 0 ] && { echo "  no accounts found"; exit 1; }
  run_action "$FLAG"
  exit 0
fi

# interactive menu loop
banner; echo
fetch_accounts || exit 1

while true; do
  echo
  printf "  ${BOLD}what do you want to do?${RESET}  ${DIM}(%d accounts loaded)${RESET}\n\n" "$TOTAL"
  printf "    ${BOLD}1${RESET}) Set to Friends only   ${DIM}→ starpets mode (locked down)${RESET}\n"
  printf "    ${BOLD}2${RESET}) Set to Everyone       ${DIM}→ restock mode (open)${RESET}\n"
  printf "    ${BOLD}3${RESET}) Check status          ${DIM}→ read-only, changes nothing${RESET}\n"
  printf "    ${BOLD}4${RESET}) Update engine         ${DIM}→ pull latest from repo${RESET}\n"
  printf "    ${BOLD}5${RESET}) Re-fetch cookies       ${DIM}→ reload accounts.txt from repo${RESET}\n"
  printf "    ${BOLD}0${RESET}) Exit\n\n"
  printf "  choose [0-5]: "
  read -r choice
  case "$choice" in
    1) run_action on ;;
    2) run_action off ;;
    3) run_action status ;;
    4) run_update ;;
    5) echo; fetch_accounts ;;
    0|q|Q) echo; printf "  ${DIM}bye${RESET}\n"; exit 0 ;;
    *) printf "  ${RED}pick 0-5${RESET}\n" ;;
  esac
  if [ "$choice" = "1" ] || [ "$choice" = "2" ] || [ "$choice" = "3" ]; then
    echo; printf "  ${DIM}press Enter to return to the menu${RESET} "; read -r _
  fi
done

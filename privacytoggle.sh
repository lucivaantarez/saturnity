#!/usr/bin/env bash
# privacytoggle.sh — v1.1.0  (engine)
# Sequential per-account Roblox privacy toggler (cookie auth).
# Toggles three settings together: Online status, Current experience, Private servers.
# Runs on Termux / MatePad. No logout endpoint is ever called — cookies stay valid.
# Settings live in config.sh (kept separate so --update never clobbers them).
#
# Usage:
#   ./privacytoggle.sh --probe          # read-only: dump current settings, reveal API shape
#   ./privacytoggle.sh --on             # restrict all three to Friends only
#   ./privacytoggle.sh --off            # open all three to Everyone
#   ./privacytoggle.sh --on --debug     # add raw request/response dumps
#   ./privacytoggle.sh --update         # pull latest engine from your repo (config.sh untouched)

set -o pipefail

# ---- resolve own dir + load config ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/config.sh" ]; then
  echo "config.sh not found next to the script ($SCRIPT_DIR). Put config.sh there and retry."
  exit 1
fi
# shellcheck source=/dev/null
. "$SCRIPT_DIR/config.sh"

# scalar fallbacks (so an older config.sh missing a newer key still runs)
: "${DELAY:=3}"; : "${BACKOFF:=30}"
: "${UA:=Mozilla/5.0}"; : "${SELF_REPO_RAW:=}"

# ---- colors: standard ANSI 16 only (Termux-safe) ----
DIM=$'\033[90m'; WHITE=$'\033[97m'; BOLD=$'\033[1m'
GREEN=$'\033[92m'; YELLOW=$'\033[93m'; RED=$'\033[91m'; CYAN=$'\033[96m'
RESET=$'\033[0m'
if [ ! -t 1 ]; then DIM=; WHITE=; BOLD=; GREEN=; YELLOW=; RED=; CYAN=; RESET=; fi

MODE=""; DEBUG=0
HTTP_CODE=""; HTTP_BODY=""; CSRF=""; COOKIE=""

# ---- arg parsing ----
for a in "$@"; do
  case "$a" in
    --on)     MODE="on" ;;
    --off)    MODE="off" ;;
    --probe)  MODE="probe" ;;
    --debug)  DEBUG=1 ;;
    --update) MODE="update" ;;
    --url=*)  ACCOUNTS_URL="${a#--url=}" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $a (use --on | --off | --probe | --update)"; exit 1 ;;
  esac
done

# ---- self-update: pull engine only, leave config.sh alone ----
if [ "$MODE" = "update" ]; then
  [ -z "$SELF_REPO_RAW" ] && { echo "SELF_REPO_RAW not set in config.sh"; exit 1; }
  echo "updating engine from $SELF_REPO_RAW/privacytoggle.sh ..."
  tmp="$(mktemp)"
  if curl -fsSL -H "User-Agent: $UA" "$SELF_REPO_RAW/privacytoggle.sh" -o "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$SCRIPT_DIR/privacytoggle.sh"
    chmod +x "$SCRIPT_DIR/privacytoggle.sh"
    echo "done — config.sh left untouched."
  else
    rm -f "$tmp"; echo "update failed — check SELF_REPO_RAW and branch name."; exit 1
  fi
  exit 0
fi

[ -z "$MODE" ] && { echo "missing mode: --on | --off | --probe | --update"; exit 1; }

# ---- tiny helpers ----
hr()  { printf "  ${DIM}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}\n"; }
dbg() { [ "$DEBUG" -eq 1 ] && printf "  ${DIM}· %s${RESET}\n" "$1"; }

json_val() {
  printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed 's/.*:[[:space:]]*"//; s/"$//'
}

live()  { printf "          %-22s${DIM}...${RESET} ${CYAN}running${RESET}" "$1"; }
done_() { printf "\r          %-22s${DIM}...${RESET} %b%s${RESET}\n" "$1" "$2" "$3"; }

state_tok() {
  case "$1" in
    "$FRIENDS_VALUE")  printf "${GREEN}on${RESET}" ;;
    "$EVERYONE_VALUE") printf "${YELLOW}off${RESET}" ;;
    "") printf "${RED}?${RESET}" ;;
    *)  printf "${YELLOW}%s${RESET}" "$1" ;;
  esac
}

# ---- HTTP core: sets HTTP_CODE / HTTP_BODY, captures CSRF token from headers ----
http() {
  local method="$1" url="$2" data="$3"
  local hdr body code
  hdr="$(mktemp)"; body="$(mktemp)"
  if [ "$method" = "GET" ]; then
    code=$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}' \
      -H "Cookie: .ROBLOSECURITY=$COOKIE" -H "User-Agent: $UA" "$url" 2>/dev/null)
  else
    code=$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}' -X "$method" \
      -H "Cookie: .ROBLOSECURITY=$COOKIE" -H "User-Agent: $UA" \
      -H "Content-Type: application/json" -H "X-CSRF-Token: $CSRF" \
      --data "$data" "$url" 2>/dev/null)
  fi
  HTTP_CODE="$code"; HTTP_BODY="$(cat "$body")"
  local tok; tok=$(grep -i '^x-csrf-token:' "$hdr" | tr -d '\r' | awk '{print $2}' | head -1)
  [ -n "$tok" ] && CSRF="$tok"
  rm -f "$hdr" "$body"
  [ "$DEBUG" -eq 1 ] && dbg "$method $url -> $HTTP_CODE  ${HTTP_BODY:0:160}"
}

# POST that auto-handles CSRF (403) refresh and 429 backoff. 0=ok, 1=fail, 42=ratelimited
post_setting() {
  local url="$1" data="$2"
  http POST "$url" "$data"
  [ "$HTTP_CODE" = "403" ] && http POST "$url" "$data"   # retry with fresh token
  [ "$HTTP_CODE" = "429" ] && return 42
  case "$HTTP_CODE" in 2*) return 0 ;; *) return 1 ;; esac
}

# ============================================================
#  START
# ============================================================
printf "${DIM}┌────────────────────────────────────────┐${RESET}\n"
printf "${DIM}│${RESET} ${BOLD}PRIVACY TOGGLE${RESET}              ${DIM}v1.1.0      │${RESET}\n"
printf "${DIM}│${RESET} ${DIM}accounts.txt · sequential · no logout   │${RESET}\n"
printf "${DIM}└────────────────────────────────────────┘${RESET}\n\n"

printf "  ${DIM}fetching accounts.txt ... ${RESET}"
RAW="$(curl -fsSL -H "User-Agent: $UA" "$ACCOUNTS_URL" 2>/dev/null)"
if [ $? -ne 0 ] || [ -z "$RAW" ]; then
  printf "${RED}failed${RESET}\n  ${DIM}check ACCOUNTS_URL in config.sh is reachable and raw${RESET}\n"; exit 1
fi
ACCS=(); while IFS= read -r line; do
  line="${line%$'\r'}"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  ACCS+=("$line")
done <<< "$RAW"
TOTAL=${#ACCS[@]}
printf "${GREEN}done (%d accs)${RESET}\n" "$TOTAL"
[ "$TOTAL" -eq 0 ] && { printf "  ${RED}no accounts found${RESET}\n"; exit 1; }

case "$MODE" in
  on)    printf "  ${DIM}mode   :${RESET} ${YELLOW}${BOLD}--on${RESET}  ${DIM}(restrict all three to Friends)${RESET}\n"
         printf "  ${DIM}target :${RESET} ${WHITE}Friends only → online · experience · private server${RESET}\n" ;;
  off)   printf "  ${DIM}mode   :${RESET} ${YELLOW}${BOLD}--off${RESET} ${DIM}(open all three to Everyone)${RESET}\n"
         printf "  ${DIM}target :${RESET} ${WHITE}Everyone → online · experience · private server${RESET}\n" ;;
  probe) printf "  ${DIM}mode   :${RESET} ${CYAN}${BOLD}--probe${RESET} ${DIM}(read-only, no changes written)${RESET}\n" ;;
esac
echo
hr
printf "  ${DIM}proceed? [y/N]${RESET} "
read -r ans
case "$ans" in y|Y|yes|YES) ;; *) printf "  ${DIM}aborted${RESET}\n"; exit 0 ;; esac
hr
echo

OK=0; FAIL=0; i=0
for entry in "${ACCS[@]}"; do
  i=$((i+1)); CSRF=""
  uname="${entry%%:*}"
  rest="${entry#*:}"
  COOKIE="${rest#*:}"
  [ "$uname" = "$entry" ] && { uname="(bad-line)"; COOKIE=""; }

  idx=$(printf "[%02d/%02d]" "$i" "$TOTAL")
  printf "  ${DIM}%s${RESET} ${BOLD}%s${RESET}\n" "$idx" "$uname"

  # 1) validate cookie
  live "validating cookie"
  http GET "https://users.roblox.com/v1/users/authenticated"
  if [ "$HTTP_CODE" != "200" ]; then
    done_ "validating cookie" "$RED" "invalid cookie"
    printf "          ${RED}✗ skipped${RESET} ${DIM}— /v1/users/authenticated returned %s${RESET}\n\n" "$HTTP_CODE"
    FAIL=$((FAIL+1)); continue
  fi
  realname="$(json_val "$HTTP_BODY" "name")"
  [ -n "$realname" ] && uname="$realname"
  done_ "validating cookie" "$GREEN" "ok"

  # ---- PROBE MODE ----
  if [ "$MODE" = "probe" ]; then
    printf "          ${DIM}legacy blob${RESET}\n"
    http GET "$LEGACY_READ"
    printf "            ${DIM}%s${RESET}\n" "[$HTTP_CODE] ${HTTP_BODY:0:400}"
    for s in 0 1 2; do
      printf "          ${DIM}%s${RESET}\n" "${SETTING_NAMES[$s]}"
      http GET "${SETTING_READ[$s]}"
      printf "            ${DIM}%s${RESET}\n" "[$HTTP_CODE] ${HTTP_BODY:0:200}"
    done
    printf "          ${CYAN}↑ paste this back so we lock the exact field names + values${RESET}\n\n"
    OK=$((OK+1)); [ "$i" -lt "$TOTAL" ] && sleep 1; continue
  fi

  # ---- ON/OFF MODE ----
  target_value="$FRIENDS_VALUE"; [ "$MODE" = "off" ] && target_value="$EVERYONE_VALUE"

  # 2) read current
  live "current state"
  cur=()
  for s in 0 1 2; do
    http GET "${SETTING_READ[$s]}"
    cur+=("$(json_val "$HTTP_BODY" "${SETTING_FIELD[$s]}")")
  done
  done_ "current state" "$RESET" "$(printf '{%b/%b/%b}' "$(state_tok "${cur[0]}")" "$(state_tok "${cur[1]}")" "$(state_tok "${cur[2]}")")"

  # 3) apply
  live "applying changes"
  applied_ok=1; ratelimited=0
  for s in 0 1 2; do
    data="{\"${SETTING_FIELD[$s]}\":\"$target_value\"}"
    post_setting "${SETTING_WRITE[$s]}" "$data"; rc=$?
    [ "$rc" -eq 42 ] && { ratelimited=1; break; }
    [ "$rc" -ne 0 ] && { applied_ok=0; break; }
  done

  if [ "$ratelimited" -eq 1 ]; then
    done_ "applying changes" "$YELLOW" "429 — rate limited, waiting ${BACKOFF}s"
    sleep "$BACKOFF"
    live "retrying"; applied_ok=1
    for s in 0 1 2; do
      data="{\"${SETTING_FIELD[$s]}\":\"$target_value\"}"
      post_setting "${SETTING_WRITE[$s]}" "$data"
      [ $? -ne 0 ] && { applied_ok=0; break; }
    done
    if [ "$applied_ok" -eq 1 ]; then done_ "retrying" "$GREEN" "ok"
    else done_ "retrying" "$RED" "failed (HTTP $HTTP_CODE)"; fi
  elif [ "$applied_ok" -eq 1 ]; then
    done_ "applying changes" "$GREEN" "ok"
  else
    done_ "applying changes" "$RED" "failed (HTTP $HTTP_CODE)"
  fi

  if [ "$applied_ok" -ne 1 ]; then
    printf "          ${RED}✗ error${RESET} ${DIM}— write rejected (run --debug to see why)${RESET}\n\n"
    FAIL=$((FAIL+1)); [ "$i" -lt "$TOTAL" ] && sleep "$DELAY"; continue
  fi

  # 4) confirm
  live "confirming state"
  conf=()
  for s in 0 1 2; do
    http GET "${SETTING_READ[$s]}"
    conf+=("$(json_val "$HTTP_BODY" "${SETTING_FIELD[$s]}")")
  done
  done_ "confirming state" "$GREEN" "$(printf '{%b/%b/%b}' "$(state_tok "${conf[0]}")" "$(state_tok "${conf[1]}")" "$(state_tok "${conf[2]}")")"

  if [ "${conf[0]}" = "$target_value" ] && [ "${conf[1]}" = "$target_value" ] && [ "${conf[2]}" = "$target_value" ]; then
    printf "          ${GREEN}✓ done${RESET}\n\n"; OK=$((OK+1))
  else
    printf "          ${YELLOW}⚠ applied but confirmation mismatch${RESET} ${DIM}— check values${RESET}\n\n"; FAIL=$((FAIL+1))
  fi

  [ "$i" -lt "$TOTAL" ] && sleep "$DELAY"
done

# ---- summary ----
hr
PEND=$((TOTAL - OK - FAIL))
printf "  ${DIM}progress :${RESET} ${WHITE}%d/%d${RESET}  ${GREEN}✓ %d ok${RESET}  ${RED}✗ %d failed${RESET}" "$((OK+FAIL))" "$TOTAL" "$OK" "$FAIL"
[ "$PEND" -gt 0 ] && printf "  ${DIM}%d pending${RESET}" "$PEND"
printf "\n"; hr

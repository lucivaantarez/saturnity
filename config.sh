#!/usr/bin/env bash
# config.sh — YOUR settings. Edit freely.
# This file is NEVER overwritten by `--update`, so your URLs/endpoints are safe.
#
# Layout expected:
#   ~/privacytoggle/
#     ├── privacytoggle.sh   (engine — updates from your repo)
#     └── config.sh          (this file — stays local/yours)

# ---- where accounts.txt lives (UPC: username:password:cookie, one per line) ----
# Cookies are sensitive — keep this in a PRIVATE gist/repo. If the repo is private,
# raw.githubusercontent.com needs a token in the URL; a secret gist raw link also works.
ACCOUNTS_URL="https://raw.githubusercontent.com/lucivaantarez/saturnity/main/accounts.txt"

# ---- self-update source (engine is pulled from here by --update) ----
# If your repo's default branch is "master", change main -> master.
SELF_REPO_RAW="https://raw.githubusercontent.com/lucivaantarez/saturnity/main"

# ---- pacing ----
DELAY=3            # seconds between accounts
BACKOFF=30         # seconds to wait on HTTP 429 before one retry

# ---- ENDPOINT CONFIG — VERIFY WITH --probe BEFORE USING --on/--off ----
# Best-guess defaults. Run `./privacytoggle.sh --probe`, send the output back,
# then correct anything here that doesn't match. A wrong endpoint errors out
# safely (no write happens), so probing first is harmless.
SETTING_NAMES=( "Online status" "Current experience" "Private servers" )
SETTING_READ=(
  "https://accountsettings.roblox.com/v1/visibility/online-status"
  "https://accountsettings.roblox.com/v1/visibility/experience"
  "https://accountsettings.roblox.com/v1/private-server-privacy"
)
SETTING_WRITE=(
  "https://accountsettings.roblox.com/v1/visibility/online-status"
  "https://accountsettings.roblox.com/v1/visibility/experience"
  "https://accountsettings.roblox.com/v1/private-server-privacy"
)
SETTING_FIELD=( "whoCanSeeMyOnlineStatus" "whoCanSeeMyExperience" "whoCanInviteToPrivateServer" )

FRIENDS_VALUE="Friends"     # value meaning "Friends only"  (the --on state)
EVERYONE_VALUE="AllUsers"   # value meaning "Everyone"      (the --off state)

# Legacy combined blob — often returns ALL privacy fields at once. Best single source
# to discover real field names/values during --probe.
LEGACY_READ="https://accountsettings.roblox.com/v1/account/settings/json"

UA="Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile"

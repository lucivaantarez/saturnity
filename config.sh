#!/usr/bin/env bash
# config.sh (v2) — YOUR settings. Edit freely. NEVER overwritten by --update.
# Endpoints below are CONFIRMED working (verified via probe on a live account).

# ---- where accounts.txt lives (UPC: username:password:cookie, one per line) ----
# Cookies are sensitive — keep this PRIVATE.
ACCOUNTS_URL="https://raw.githubusercontent.com/lucivaantarez/saturnity/main/accounts.txt"

# ---- self-update source (engine pulled from here by --update) ----
SELF_REPO_RAW="https://raw.githubusercontent.com/lucivaantarez/saturnity/main"

# ---- pacing ----
DELAY=3        # seconds between accounts
BACKOFF=30     # seconds to wait on HTTP 429 before one retry

# ============================================================
#  CONFIRMED ROBLOX ENDPOINTS  (apis.roblox.com/user-settings-api)
# ============================================================
SETTINGS_URL="https://apis.roblox.com/user-settings-api/v1/user-settings"
# page that hands back the RBXEventTrackerV2 cookie (carries BrowserTrackerID)
TRACKER_URL="https://www.roblox.com/home"

# the three settings we read/confirm (label is just for the TUI)
READ_FIELDS=( "whoCanSeeMyOnlineStatus" "whoCanJoinMeInExperiences" "privateServerPrivacy" )
READ_LABELS=( "Online" "Experience" "PrivServer" )

# request bodies per mode (single POST sets them; experience cascades from online status)
ON_BODY='{"whoCanSeeMyOnlineStatus":"Friends","whoCanJoinMeInExperiences":"Friends","privateServerPrivacy":"Friends"}'
OFF_BODY='{"whoCanSeeMyOnlineStatus":"AllUsers","privateServerPrivacy":"AllUsers"}'

# expected final values after each mode (used for the confirm check)
EXPECT_ON=(  "Friends"  "Friends" "Friends"  )
EXPECT_OFF=( "AllUsers" "All"     "AllUsers" )

# value -> on/off display buckets
FRIENDS_TOKENS="Friends"        # shown as ON  (restricted)
EVERYONE_TOKENS="AllUsers All"  # shown as OFF (open)

UA="Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile"

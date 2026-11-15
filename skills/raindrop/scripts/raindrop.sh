#!/usr/bin/env bash
# Call any Raindrop.io REST API endpoint without showing the access token.
# Why: an agent that runs this script never sees, prints or types the token.
# The script finds the token itself and sends it as a bearer token.
#
# Usage:
#   raindrop.sh METHOD PATH                      a call with no body
#   raindrop.sh METHOD PATH 'JSON_BODY'          a call with a JSON body
#   raindrop.sh METHOD PATH -                    JSON body read from standard input
#   raindrop.sh METHOD PATH --form KEY=VALUE ... a multipart upload (KEY=@FILE sends a file)
#   raindrop.sh oauth-url REDIRECT_URI           print the page where the user approves access
#   raindrop.sh oauth-token CODE REDIRECT_URI    trade an approval code for tokens and save them
#   raindrop.sh oauth-refresh                    get a new access token with the saved refresh token
#
# PATH is everything after https://api.raindrop.io/rest/v1, query string included.
#
# Where the script looks for RAINDROP_API_TOKEN (and the other settings), in order:
#   1. the environment
#   2. a .env file in the current directory
#   3. ~/.config/raindrop/credentials

set -euo pipefail

API_BASE="https://api.raindrop.io/rest/v1"
OAUTH_TOKEN_URL="https://raindrop.io/oauth/access_token"
CREDENTIALS_FILE="$HOME/.config/raindrop/credentials"

# Print the value of one NAME=value line from a file. Prints nothing if the
# file or the line is missing. Reads only that line, so nothing else in the
# file is loaded.
read_setting_from_file() {
  local name="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  local line
  # "|| true" stops "set -e" from ending the script when grep finds nothing.
  line="$(grep -E "^(export )?${name}=" "$file" | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 0
  fi
  # "#*=" removes everything up to and including the first "=".
  local value="${line#*=}"
  # Remove one pair of surrounding quotes, if present.
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

# Print a setting, taken from the first place that has it.
find_setting() {
  local name="$1"
  # "${!name:-}" reads the environment variable whose name is stored in $name.
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    value="$(read_setting_from_file "$name" "$PWD/.env")"
  fi
  if [[ -z "$value" ]]; then
    value="$(read_setting_from_file "$name" "$CREDENTIALS_FILE")"
  fi
  printf '%s' "$value"
}

# Stop with a clear message when a required setting is missing.
require_setting() {
  local name="$1"
  local value
  value="$(find_setting "$name")"
  if [[ -z "$value" ]]; then
    echo "$name is not set. Put it in the environment, in ./.env, or in $CREDENTIALS_FILE" >&2
    exit 1
  fi
  printf '%s' "$value"
}

# Save one NAME=value line in the credentials file, replacing an older line
# with the same name. The file is readable only by its owner.
save_setting() {
  local name="$1"
  local value="$2"
  mkdir -p "$(dirname "$CREDENTIALS_FILE")"
  touch "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"
  local kept_lines
  kept_lines="$(grep -vE "^(export )?${name}=" "$CREDENTIALS_FILE" || true)"
  {
    if [[ -n "$kept_lines" ]]; then
      printf '%s\n' "$kept_lines"
    fi
    printf '%s=%s\n' "$name" "$value"
  } > "$CREDENTIALS_FILE"
}

# Send a token request to Raindrop and save the tokens it returns.
# Prints only whether it worked, never the tokens.
request_and_save_tokens() {
  local request_body="$1"
  local response
  response="$(curl -sS -X POST -H "Content-Type: application/json" --data-binary "$request_body" "$OAUTH_TOKEN_URL")"
  local access_token
  local refresh_token
  access_token="$(printf '%s' "$response" | jq -r '.access_token // empty')"
  refresh_token="$(printf '%s' "$response" | jq -r '.refresh_token // empty')"
  if [[ -z "$access_token" ]]; then
    # Show the error name only. The response holds no token when it fails.
    echo "Raindrop did not return a token: $(printf '%s' "$response" | jq -c '{error, errorMessage}' 2>/dev/null || echo 'unreadable response')" >&2
    exit 1
  fi
  save_setting RAINDROP_API_TOKEN "$access_token"
  if [[ -n "$refresh_token" ]]; then
    save_setting RAINDROP_REFRESH_TOKEN "$refresh_token"
  fi
  echo "Saved a new access token to $CREDENTIALS_FILE. It expires in two weeks; run 'raindrop.sh oauth-refresh' to renew it."
}

if [[ $# -lt 1 ]]; then
  # Print the usage block at the top of this file (lines 2 to 18, without the "# ").
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 1
fi

command_name="$1"

# --- OAuth commands -------------------------------------------------------

if [[ "$command_name" == "oauth-url" ]]; then
  redirect_uri="${2:?Usage: raindrop.sh oauth-url REDIRECT_URI}"
  client_id="$(require_setting RAINDROP_CLIENT_ID)"
  # jq's @uri filter percent-encodes the redirect address for use in a URL.
  encoded_redirect="$(jq -rn --arg value "$redirect_uri" '$value | @uri')"
  echo "https://raindrop.io/oauth/authorize?response_type=code&client_id=${client_id}&redirect_uri=${encoded_redirect}"
  exit 0
fi

if [[ "$command_name" == "oauth-token" ]]; then
  code="${2:?Usage: raindrop.sh oauth-token CODE REDIRECT_URI}"
  redirect_uri="${3:?Usage: raindrop.sh oauth-token CODE REDIRECT_URI}"
  client_id="$(require_setting RAINDROP_CLIENT_ID)"
  client_secret="$(require_setting RAINDROP_CLIENT_SECRET)"
  request_body="$(jq -n --arg code "$code" --arg id "$client_id" --arg secret "$client_secret" --arg redirect "$redirect_uri" \
    '{grant_type: "authorization_code", code: $code, client_id: $id, client_secret: $secret, redirect_uri: $redirect}')"
  request_and_save_tokens "$request_body"
  exit 0
fi

if [[ "$command_name" == "oauth-refresh" ]]; then
  client_id="$(require_setting RAINDROP_CLIENT_ID)"
  client_secret="$(require_setting RAINDROP_CLIENT_SECRET)"
  refresh_token="$(require_setting RAINDROP_REFRESH_TOKEN)"
  request_body="$(jq -n --arg id "$client_id" --arg secret "$client_secret" --arg refresh "$refresh_token" \
    '{grant_type: "refresh_token", client_id: $id, client_secret: $secret, refresh_token: $refresh}')"
  request_and_save_tokens "$request_body"
  exit 0
fi

# --- API calls ------------------------------------------------------------

if [[ $# -lt 2 ]]; then
  echo "Usage: raindrop.sh METHOD PATH [JSON_BODY | - | --form KEY=VALUE ...]" >&2
  exit 1
fi

method="$1"
path="$2"
shift 2

token="$(require_setting RAINDROP_API_TOKEN)"
url="${API_BASE}${path}"

# Every call sends the token in the Authorization header.
curl_arguments=(-sS -X "$method" -H "Authorization: Bearer $token")

if [[ $# -eq 0 ]]; then
  # No body.
  :
elif [[ "$1" == "--form" ]]; then
  # Multipart upload: each "--form KEY=VALUE" pair becomes one form field.
  # curl sets the multipart Content-Type header itself.
  while [[ $# -gt 0 ]]; do
    if [[ "$1" != "--form" || $# -lt 2 ]]; then
      echo "Expected --form KEY=VALUE, got: $1" >&2
      exit 1
    fi
    curl_arguments+=(-F "$2")
    shift 2
  done
elif [[ "$1" == "-" ]]; then
  # "@-" tells curl to read the request body from standard input.
  curl_arguments+=(-H "Content-Type: application/json" --data-binary @-)
else
  curl_arguments+=(-H "Content-Type: application/json" --data-binary "$1")
fi

curl "${curl_arguments[@]}" "$url"

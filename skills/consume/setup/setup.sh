#!/usr/bin/env bash
# Consume setup: wires a Supabase project up as your Consume inbox.
#
#   ./setup.sh --project-ref <your-project-ref>
#
# What it does, in order (safe to re-run):
#   1. creates the consume_items table (setup/schema.sql, idempotent)
#   2. generates a capture token, or reuses the one already in your env file
#   3. stores the token as the CONSUME_CAPTURE_TOKEN function secret
#   4. deploys the consume-capture Edge Function with --no-verify-jwt
#   5. writes your env file (default ~/.env.consume, mode 600)
#   6. sends one test link through the live endpoint
#
# Needs: the Supabase CLI (logged in via `supabase login`), jq, openssl, curl.

set -euo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CONSUME_ENV_FILE:-$HOME/.env.consume}"
REF="${CONSUME_PROJECT_REF:-}"

die() { printf 'consume setup: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project-ref) REF="${2:-}"; shift 2 ;;
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

for bin in supabase jq openssl curl; do
  command -v "$bin" >/dev/null 2>&1 || die "missing '$bin'. Install it first (macOS: brew install supabase/tap/supabase jq)."
done
supabase db query --help >/dev/null 2>&1 \
  || die "your Supabase CLI is too old (no 'supabase db query'). Upgrade it: brew upgrade supabase"
supabase projects list -o json >/dev/null 2>&1 \
  || die "the Supabase CLI is not logged in. Run: supabase login"

if [ -z "$REF" ]; then
  echo "Your Supabase projects:"
  supabase projects list -o json | jq -r '.[] | "  \(.ref)  \(.name)"'
  printf '\nProject ref to use for Consume: '
  read -r REF
fi
[[ "$REF" =~ ^[a-z0-9]{20}$ ]] || die "'$REF' does not look like a Supabase project ref (20 lowercase letters and digits)."

PROJECT_URL="https://${REF}.supabase.co"
CAPTURE_URL="${PROJECT_URL}/functions/v1/consume-capture"

step "Creating the consume_items table"
supabase db query --project-ref "$REF" -f "$SETUP_DIR/schema.sql" >/dev/null

step "Capture token"
TOKEN=""
if [ -f "$ENV_FILE" ]; then
  # Reuse the existing token when the env file already points at this project,
  # so a re-run does not break a Shortcut you have already built.
  existing_url="$(sed -n 's/^CONSUME_SUPABASE_URL=//p' "$ENV_FILE" | head -n 1)"
  if [ "$existing_url" = "$PROJECT_URL" ]; then
    TOKEN="$(sed -n 's/^CONSUME_CAPTURE_TOKEN=//p' "$ENV_FILE" | head -n 1)"
  fi
fi
if [ -n "$TOKEN" ]; then
  echo "Reusing the token in $ENV_FILE"
else
  TOKEN="$(openssl rand -hex 32)"
  echo "Generated a new token"
fi

# Pass the secret through a private temp file, never on the command line.
secret_file="$(mktemp)"
trap 'rm -f "$secret_file"' EXIT
chmod 600 "$secret_file"
printf 'CONSUME_CAPTURE_TOKEN=%s\n' "$TOKEN" > "$secret_file"
supabase secrets set --project-ref "$REF" --env-file "$secret_file" >/dev/null

step "Deploying the consume-capture function (--no-verify-jwt)"
supabase functions deploy consume-capture \
  --project-ref "$REF" --workdir "$SETUP_DIR" --no-verify-jwt --use-api >/dev/null

step "Fetching the service-role key for the review skill"
keys_json="$(supabase projects api-keys --project-ref "$REF" --reveal -o json)"
SERVICE_KEY="$(printf '%s' "$keys_json" | jq -r '
  (map(select(.name == "service_role")) + map(select(.type == "secret")))
  | first | .api_key // empty')"
[ -n "$SERVICE_KEY" ] || die "could not find a service_role or secret key for $REF. Copy it from the dashboard (Project Settings, API Keys) into $ENV_FILE as CONSUME_SUPABASE_KEY."

step "Writing $ENV_FILE"
umask 077
cat > "$ENV_FILE" <<ENV
# Consume. Written by skills/consume/setup/setup.sh. Keep this file private:
# the service-role key bypasses row-level security.
CONSUME_SUPABASE_URL=$PROJECT_URL
CONSUME_SUPABASE_KEY=$SERVICE_KEY
CONSUME_CAPTURE_URL=$CAPTURE_URL
CONSUME_CAPTURE_TOKEN=$TOKEN
ENV
chmod 600 "$ENV_FILE"

step "Sending a test link through the live endpoint"
status=""
for _ in 1 2 3 4 5; do
  status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$CAPTURE_URL" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"url":"https://github.com/HourglassDigital/hgstack/tree/main/skills/consume","source":"manual"}' || true)"
  [ "$status" = "201" ] && break
  sleep 3
done
if [ "$status" = "201" ]; then
  echo "Test link saved. It will be the first item in your first /consume pass."
else
  die "the endpoint returned HTTP $status. A 401 means the function was deployed without --no-verify-jwt or the secret did not set; re-run this script."
fi

cat <<DONE

Consume is live. Build the Shortcut next (SHORTCUT.md) with these two values:

  URL:            $CAPTURE_URL
  Authorization:  Bearer <the CONSUME_CAPTURE_TOKEN value in $ENV_FILE>

Then save a few links and run /consume in Claude Code.
DONE

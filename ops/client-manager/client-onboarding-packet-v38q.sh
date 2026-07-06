#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
CLIENT_ID="${2:-}"

STAGING_KV="d4be478f609e4696aae597c6adf6c533"
PROD_KV="faac1bcc30ef4711a9377e60ef70636d"

if [[ "$ENVIRONMENT" == "staging" ]]; then
  KV="$STAGING_KV"
  BASE_URL="https://rally-staging.coachjohnpickleball.workers.dev"
elif [[ "$ENVIRONMENT" == "production" ]]; then
  KV="$PROD_KV"
  BASE_URL="https://rally.coachjohnpickleball.workers.dev"
else
  echo "Usage:"
  echo "  ./ops/client-manager/client-onboarding-packet-v38q.sh staging <clientId>"
  echo "  ./ops/client-manager/client-onboarding-packet-v38q.sh production <clientId>"
  exit 1
fi

if [[ -z "$CLIENT_ID" ]]; then
  read -r -p "Client ID: " CLIENT_ID
fi

if [[ -z "$CLIENT_ID" ]]; then
  echo "Cancelled: no client ID entered."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
LICENSE="$TMP_DIR/license.json"
STATE="$TMP_DIR/state.json"

REPORT_DIR="ops/client-manager/reports"
STAMP="$(date +%Y%m%d-%H%M%S)"
PACKET_DIR="$REPORT_DIR/${ENVIRONMENT}-onboarding-${CLIENT_ID}-${STAMP}"

mkdir -p "$PACKET_DIR"

echo "=============================================="
echo " PickleBall Pro Client Onboarding Packet V38Q"
echo "=============================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Client: $CLIENT_ID"
echo "Read-only. No KV changes are made."
echo ""

if ! npx wrangler kv key get "client-license:$CLIENT_ID" --namespace-id "$KV" --remote > "$LICENSE" 2>/dev/null; then
  echo "ERROR: license not found for client:"
  echo "$CLIENT_ID"
  exit 1
fi

npx wrangler kv key get "client-state::$CLIENT_ID::current" --namespace-id "$KV" --remote > "$STATE" 2>/dev/null || true

python3 - "$LICENSE" "$STATE" "$PACKET_DIR" "$CLIENT_ID" "$ENVIRONMENT" "$BASE_URL" <<'PY'
import json, sys
from pathlib import Path

license_file, state_file, packet_dir, client_id, environment, base_url = sys.argv[1:7]
packet = Path(packet_dir)

def load_json(path):
    try:
        return json.load(open(path))
    except Exception:
        return {}

license_data = load_json(license_file)
state_data = load_json(state_file)

state = state_data.get("state", state_data) if isinstance(state_data, dict) else {}
players = state.get("players", []) if isinstance(state, dict) else []

active_players = 0
if isinstance(players, list):
    for p in players:
        if not isinstance(p, dict):
            continue
        if p.get("active") is False:
            continue
        if p.get("waitlist") is True:
            continue
        active_players += 1

client_name = license_data.get("clientName") or license_data.get("name") or client_id
level = license_data.get("licenseLevel") or license_data.get("level") or license_data.get("plan") or "club"
status = license_data.get("licenseStatus") or license_data.get("status") or "active"
player_limit = license_data.get("playerLimit") or license_data.get("maxPlayers") or license_data.get("playersLimit") or ""
renewal = (
    license_data.get("renewalDate")
    or license_data.get("expiresAt")
    or license_data.get("subscriptionEndsAt")
    or license_data.get("trialEndsAt")
    or ""
)

billing_name = license_data.get("billingName") or ""
billing_email = license_data.get("billingEmail") or ""
billing_phone = license_data.get("billingPhone") or ""
billing_notes = license_data.get("billingNotes") or ""

private_link = f"{base_url}/?clientId={client_id}"

summary = f"""PickleBall Pro Client Summary
==============================

Environment: {environment}
Client ID: {client_id}
Client Name: {client_name}

License
-------
Status: {status}
Level: {level}
Player Limit: {player_limit}
Active Players: {active_players}
Renewal / Expiry: {renewal or "-"}

Billing Contact
---------------
Billing Name: {billing_name or "-"}
Billing Email: {billing_email or "-"}
Billing Phone: {billing_phone or "-"}
Billing Notes: {billing_notes or "-"}

Private Link
------------
{private_link}
"""

welcome = f"""To: {billing_email or "[add client email]"}
Subject: Welcome to PickleBall Pro - {client_name}

Hi {billing_name or client_name},

Welcome to PickleBall Pro.

Your private client link is:

{private_link}

Please bookmark this link. It is specific to your club/client setup.

Account details:
- Client: {client_name}
- License level: {level}
- Player limit: {player_limit}
- Current status: {status}

A few quick notes:
1. Use the private link above when opening the app.
2. Do not share the link publicly.
3. If access is controlled by Cloudflare Access, users may need to sign in before the app opens.
4. If you need changes to your license, player limit, or billing contact, contact John.

Thanks,
John
"""

private_link_text = f"""Private Client Link
===================

Client: {client_name}
Client ID: {client_id}
Environment: {environment}

{private_link}
"""

(packet / "client-summary.txt").write_text(summary)
(packet / "welcome-email.txt").write_text(welcome)
(packet / "private-link.txt").write_text(private_link_text)
(packet / "license.json").write_text(json.dumps(license_data, indent=2))

print("")
print("ONBOARDING PACKET")
print("-----------------")
print("Folder:", packet)
print("Client:", client_name)
print("Private link:", private_link)
print("")
print("Files:")
for item in ["client-summary.txt", "welcome-email.txt", "private-link.txt", "license.json"]:
    print("-", packet / item)
print("")
print("GREEN: onboarding packet created.")
PY

echo ""
echo "GREEN: $ENVIRONMENT onboarding packet complete."

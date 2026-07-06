#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Usage:"
  echo "  ./ops/client-manager/billing-followup-report-v38o.sh staging"
  echo "  ./ops/client-manager/billing-followup-report-v38o.sh production"
  exit 1
fi

REPORT_DIR="ops/client-manager/reports"
mkdir -p "$REPORT_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_TXT="$REPORT_DIR/${ENVIRONMENT}-billing-followup-${STAMP}.txt"
OUT_CSV="$REPORT_DIR/${ENVIRONMENT}-billing-followup-${STAMP}.csv"

TMP_DIR="$(mktemp -d)"
SUMMARY_OUT="$TMP_DIR/billing-summary.txt"

echo "=============================================="
echo " PickleBall Pro Billing Follow-Up Report V38O"
echo "=============================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Read-only. No KV changes are made."
echo ""

./ops/client-manager/billing-summary-export-v38l.sh "$ENVIRONMENT" | tee "$SUMMARY_OUT"

LATEST_CSV="$(ls -1t "$REPORT_DIR/${ENVIRONMENT}-billing-summary-"*.csv | head -1)"

python3 - "$LATEST_CSV" "$OUT_TXT" "$OUT_CSV" "$ENVIRONMENT" <<'PY'
import csv, sys
from pathlib import Path

source_csv, out_txt, out_csv, environment = sys.argv[1:5]

attention_health = {
    "EXPIRED",
    "EXPIRING_SOON",
    "SUSPENDED",
    "INACTIVE",
    "OVER_LIMIT",
    "NO_RENEWAL_DATE",
}

def action_for(row):
    health = row.get("billingHealth", "")
    status = row.get("status", "")
    level = row.get("level", "")
    days = row.get("daysLeft", "")

    if health == "EXPIRED":
        return "Contact client for renewal/payment. Consider suspending if unpaid."
    if health == "EXPIRING_SOON":
        return f"Send renewal reminder. Days left: {days or 'unknown'}."
    if health == "SUSPENDED":
        return "Confirm payment status before reactivation."
    if health == "OVER_LIMIT":
        return "Discuss upgrade or reduce active players."
    if health == "INACTIVE":
        return f"Review invalid/non-active status: {status}."
    if health == "NO_RENEWAL_DATE":
        return "Add renewalDate so billing follow-up can be tracked."
    if level == "trial":
        return "Follow up before trial conversion."
    return "No action."

with open(source_csv, newline="") as f:
    rows = list(csv.DictReader(f))

followups = []
for row in rows:
    health = row.get("billingHealth", "")
    if health in attention_health:
        row["suggestedAction"] = action_for(row)
        followups.append(row)

fieldnames = [
    "clientId",
    "clientName",
    "billingName",
    "billingEmail",
    "billingPhone",
    "status",
    "level",
    "activePlayers",
    "playerLimit",
    "renewalDate",
    "daysLeft",
    "billingHealth",
    "suggestedAction",
    "privateLink",
]

with open(out_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(followups)

lines = []
lines.append("PickleBall Pro Billing Follow-Up Report V38O")
lines.append("=" * 52)
lines.append(f"Environment: {environment}")
lines.append(f"Source CSV: {source_csv}")
lines.append("")
lines.append(f"Clients needing follow-up: {len(followups)}")
lines.append("")

if not followups:
    lines.append("GREEN: no billing follow-up items found.")
else:
    for i, row in enumerate(followups, 1):
        lines.append(f"{i}. {row.get('clientId')}")
        lines.append(f"   Name: {row.get('clientName')}")
        lines.append(f"   Health: {row.get('billingHealth')}")
        lines.append(f"   Status/Level: {row.get('status')} / {row.get('level')}")
        lines.append(f"   Players: {row.get('activePlayers')}/{row.get('playerLimit')}")
        lines.append(f"   Renewal: {row.get('renewalDate') or '-'}")
        lines.append(f"   Billing Contact: {row.get('billingName') or '-'} | {row.get('billingEmail') or '-'} | {row.get('billingPhone') or '-'}")
        lines.append(f"   Suggested Action: {row.get('suggestedAction')}")
        lines.append(f"   Private Link: {row.get('privateLink')}")
        lines.append("")

Path(out_txt).write_text("\n".join(lines) + "\n")

print("")
print("FOLLOW-UP SUMMARY")
print("-----------------")
print("Clients needing follow-up:", len(followups))

for row in followups:
    print(f"- {row.get('clientId')} | {row.get('billingHealth')} | {row.get('suggestedAction')}")

print("")
print("TXT report:", out_txt)
print("CSV report:", out_csv)

if followups:
    print("")
    print("ATTENTION: billing follow-up report has action items.")
else:
    print("")
    print("GREEN: no billing follow-up items found.")
PY

echo ""
echo "GREEN: $ENVIRONMENT billing follow-up report complete."

#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Usage:"
  echo "  ./ops/client-manager/billing-email-drafts-v38p.sh staging"
  echo "  ./ops/client-manager/billing-email-drafts-v38p.sh production"
  exit 1
fi

REPORT_DIR="ops/client-manager/reports"
mkdir -p "$REPORT_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
DRAFT_DIR="$REPORT_DIR/${ENVIRONMENT}-billing-email-drafts-${STAMP}"
mkdir -p "$DRAFT_DIR"

TMP_DIR="$(mktemp -d)"
FOLLOWUP_OUT="$TMP_DIR/followup.txt"

echo "=============================================="
echo " PickleBall Pro Billing Email Drafts V38P"
echo "=============================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Read-only. No emails are sent. No KV changes are made."
echo ""

./ops/client-manager/billing-followup-report-v38o.sh "$ENVIRONMENT" | tee "$FOLLOWUP_OUT"

LATEST_CSV="$(ls -1t "$REPORT_DIR/${ENVIRONMENT}-billing-followup-"*.csv | head -1)"

python3 - "$LATEST_CSV" "$DRAFT_DIR" "$ENVIRONMENT" <<'PY'
import csv, re, sys
from pathlib import Path

source_csv, draft_dir, environment = sys.argv[1:4]
draft_dir = Path(draft_dir)

def safe_filename(value):
    value = value or "client"
    value = re.sub(r"[^a-zA-Z0-9._-]+", "-", value).strip("-")
    return value[:120] or "client"

def subject_for(row):
    health = row.get("billingHealth", "")
    name = row.get("clientName") or row.get("clientId")

    if health == "EXPIRED":
        return f"PickleBall Pro renewal needed for {name}"
    if health == "EXPIRING_SOON":
        return f"PickleBall Pro renewal reminder for {name}"
    if health == "SUSPENDED":
        return f"PickleBall Pro account status for {name}"
    if health == "OVER_LIMIT":
        return f"PickleBall Pro player limit review for {name}"
    if health == "NO_RENEWAL_DATE":
        return f"PickleBall Pro account details for {name}"
    return f"PickleBall Pro follow-up for {name}"

def body_for(row):
    client_name = row.get("clientName") or row.get("clientId")
    billing_name = row.get("billingName") or ""
    contact_name = billing_name or client_name

    health = row.get("billingHealth", "")
    renewal = row.get("renewalDate") or ""
    days = row.get("daysLeft") or ""
    active = row.get("activePlayers") or "0"
    limit = row.get("playerLimit") or ""
    private_link = row.get("privateLink") or ""

    greeting = f"Hi {contact_name},"

    if health == "EXPIRED":
        main = (
            f"Our records show the PickleBall Pro renewal date for {client_name} has passed"
            + (f" ({renewal})." if renewal else ".")
            + " Please let me know if you would like me to renew the account and keep everything active."
        )
    elif health == "EXPIRING_SOON":
        main = (
            f"Just a friendly reminder that the PickleBall Pro renewal for {client_name}"
            + (f" is coming up on {renewal}" if renewal else " is coming up")
            + (f" — about {days} days remaining." if days else ".")
        )
    elif health == "SUSPENDED":
        main = (
            f"The PickleBall Pro account for {client_name} is currently marked as suspended. "
            "Once renewal/payment is confirmed, I can reactivate access."
        )
    elif health == "OVER_LIMIT":
        main = (
            f"The PickleBall Pro account for {client_name} is currently using {active} active players"
            + (f" against a limit of {limit}." if limit else ".")
            + " We may need to review the license level or reduce active players."
        )
    elif health == "NO_RENEWAL_DATE":
        main = (
            f"I’m updating the billing records for {client_name}. "
            "Can you confirm the renewal date or billing contact I should keep on file?"
        )
    else:
        main = f"Quick follow-up on the PickleBall Pro account for {client_name}."

    lines = [
        greeting,
        "",
        main,
        "",
        "Account snapshot:",
        f"- Client: {client_name}",
        f"- Status: {row.get('status')}",
        f"- License level: {row.get('level')}",
        f"- Players: {active}/{limit}",
        f"- Renewal date: {renewal or '-'}",
        "",
    ]

    if private_link:
        lines.extend([
            "Private client link:",
            private_link,
            "",
        ])

    lines.extend([
        "Thanks,",
        "John",
        "",
    ])

    return "\n".join(lines)

with open(source_csv, newline="") as f:
    rows = list(csv.DictReader(f))

created = []

for row in rows:
    client_id = row.get("clientId") or "client"
    health = row.get("billingHealth") or "FOLLOWUP"

    if not client_id:
        continue

    subject = subject_for(row)
    body = body_for(row)

    filename = draft_dir / f"{safe_filename(client_id)}-{safe_filename(health)}.txt"

    content = []
    content.append(f"To: {row.get('billingEmail') or '[add billing email]'}")
    content.append(f"Subject: {subject}")
    content.append("")
    content.append(body)

    filename.write_text("\n".join(content))
    created.append(filename)

print("")
print("EMAIL DRAFTS")
print("------------")
print("Draft folder:", draft_dir)
print("Drafts created:", len(created))

for item in created:
    print("-", item)

if created:
    print("")
    print("GREEN: billing email drafts created.")
else:
    print("")
    print("GREEN: no follow-up clients, so no email drafts were needed.")
PY

echo ""
echo "GREEN: $ENVIRONMENT billing email draft generation complete."

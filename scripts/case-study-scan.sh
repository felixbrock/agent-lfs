#!/bin/bash
# Leak gate for public case studies. A checklist is something you
# follow; this is something that stops you. Run it on a candidate case
# study BEFORE opening the publish PR (the /lfs-case-study skill
# requires a clean pass); the owner merging the PR is the human
# backstop behind it.
#
# Two tiers:
#   HARD  — machine-identifying strings => FAIL (exit 1). Concrete
#           values come from the private side ($LFS_CONFIG/machine.env
#           and $LFS_CONFIG/case-study-denylist.txt) so this scanner
#           itself carries no secrets and stays public. Plus generic
#           shapes that must never appear: MAC, LUKS/FS UUID, IPv4.
#   REVIEW— chip-level IDs (USB VID:PID, ACPI VEN_xxxx). NOT a failure:
#           chip-level identifiers are the reproducible teaching value.
#           Printed so a human consciously confirms "chip, not machine".
#
# Usage: case-study-scan.sh <file.md>
set -euo pipefail

FILE=${1:?usage: case-study-scan.sh <case-study.md>}
[ -r "$FILE" ] || { echo "FAIL: cannot read $FILE"; exit 1; }
LFS_CONFIG=${LFS_CONFIG:-$HOME/repos/lfs-config}

FAIL=0

# --- HARD: concrete instance strings from the private side -----------
DENY=$(mktemp)
trap 'rm -f "$DENY"' EXIT
# disk serials, LUKS UUIDs, by-id paths, username from machine.env
if [ -f "$LFS_CONFIG/machine.env" ]; then
  grep -oE 'UUID=[0-9a-fA-F-]{8,}|nvme-[A-Za-z0-9_.-]+|usb-[A-Za-z0-9_.-]+|[A-Z]+[0-9]{2,}[A-Z0-9_]+_[0-9]+[A-Z0-9]*' \
    "$LFS_CONFIG/machine.env" 2>/dev/null | sed 's/^UUID=//' | sort -u >> "$DENY" || true
  grep -oE 'LFS_USER=[A-Za-z0-9_]+' "$LFS_CONFIG/machine.env" 2>/dev/null | cut -d= -f2 >> "$DENY" || true
fi
# maintained free-form denylist (model names, peripheral names, MACs)
[ -f "$LFS_CONFIG/case-study-denylist.txt" ] && \
  grep -vE '^\s*(#|$)' "$LFS_CONFIG/case-study-denylist.txt" >> "$DENY"

while IFS= read -r term; do
  [ -n "$term" ] || continue
  if grep -Finq "$term" "$FILE"; then
    echo "HARD FAIL: instance string present: $term"
    FAIL=1
  fi
done < <(sort -u "$DENY")

# --- HARD: generic shapes that are never safe in public --------------
if grep -qiE '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b' "$FILE"; then
  echo "HARD FAIL: MAC address shape present"; FAIL=1
fi
if grep -qE '\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b' "$FILE"; then
  echo "HARD FAIL: UUID shape present"; FAIL=1
fi
if grep -qE '\b(10|172|192)\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' "$FILE"; then
  echo "HARD FAIL: private IPv4 shape present"; FAIL=1
fi

# --- REVIEW: chip-level IDs (conscious keep, not a failure) ----------
REVIEW=$(grep -oiE '\b[0-9a-f]{4}:[0-9a-f]{4}\b|VEN_[0-9A-F]{4}' "$FILE" | sort -u || true)
if [ -n "$REVIEW" ]; then
  echo "REVIEW (chip-level IDs — confirm each is chip, not machine):"
  echo "$REVIEW" | sed 's/^/  /'
fi

echo "---"
if [ "$FAIL" -ne 0 ]; then
  echo "RESULT: BLOCKED — resolve HARD FAILs before publishing."
  exit 1
fi
echo "RESULT: no machine-identifying strings found. REVIEW items (if any) need a human OK."
exit 0

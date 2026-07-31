#!/bin/bash
# Tier-1 security check: query the Arch Linux security tracker
# (security.archlinux.org, public JSON API) for every installed package.
# Piggybacks Arch's professional CVE triage for our inventory.
#
# Output: one line per package that has CVEs Arch still lists as
# "Vulnerable" (open upstream => almost certainly affects us too).
# Full per-package JSON is cached in $CACHE for deeper triage by the
# sweep session. Network + repo only — safe for scheduled/headless runs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${1:-/tmp/lfs-seccheck-$(date +%Y%m%d)}"
mkdir -p "$CACHE"

# our-name -> arch-name for known mismatches; default = lowercase
arch_name() {
  case "$1" in
    Python) echo python ;;
    icu4c) echo icu ;;
    XML-Parser) echo perl-xml-parser ;;
    File-ShareDir) echo perl-file-sharedir ;;
    File-ShareDir-Install) echo perl-file-sharedir-install ;;
    Class-Inspector) echo perl-class-inspector ;;
    Linux-PAM) echo pam ;;
    freetype) echo freetype2 ;;
    glib) echo glib2 ;;
    gdk-pixbuf) echo gdk-pixbuf2 ;;
    gtk) echo gtk3 ;;
    i3) echo i3-wm ;;
    ImageMagick*) echo imagemagick ;;
    lm-sensors*) echo lm_sensors ;;
    dejavu-fonts-ttf) echo ttf-dejavu ;;
    fuse) echo fuse2 ;;
    graphite2) echo graphite ;;
    jinja2) echo python-jinja ;;
    markupsafe) echo python-markupsafe ;;
    flit_core) echo python-flit-core ;;
    packaging) echo python-packaging ;;
    setuptools) echo python-setuptools ;;
    wheel) echo python-wheel ;;
    sqlite-autoconf) echo sqlite ;;
    xinit) echo xorg-xinit ;;
    font-util) echo xorg-font-util ;;
    util-macros) echo xorg-util-macros ;;
    # LFS-only, no Arch equivalent: skip silently
    blfs-systemd-units|make-ca) echo SKIP ;;
    # AUR-only upstream binary, no Arch official package; tier 1b
    # (binary-check, aur openai-codex-bin) is its monitoring feed
    codex) echo SKIP ;;
    *) echo "$1" | tr 'A-Z' 'a-z' ;;
  esac
}

bash "$REPO/scripts/lfs-inventory.sh" | while read -r name ver; do
  a=$(arch_name "$name")
  [ "$a" = SKIP ] && continue
  out="$CACHE/$a.json"
  if [ ! -s "$out" ]; then
    # 404 = name unknown to the tracker (curation); anything else after
    # retries = transient/network failure and the sweep is INCOMPLETE —
    # never conflate the two (2026-07-15: a rate-limit window mid-run
    # misfiled 11 packages as UNMAPPED).
    code=$(curl -sm20 --retry 3 --retry-delay 2 --retry-all-errors \
      -w '%{http_code}' -o "$out" \
      "https://security.archlinux.org/package/$a.json" 2>/dev/null) || code=000
    if [ "$code" = "404" ]; then
      rm -f "$out"
      echo "$name UNMAPPED ($a)" >> "$CACHE/unmapped.txt"
      continue
    fi
    if [ "$code" != "200" ]; then
      rm -f "$out"
      echo "$name FETCH-FAILED ($a http=$code)" >> "$CACHE/failed.txt"
      continue
    fi
    # be polite to the tracker — the 2026-07-15 failures were a
    # rate-limit cluster from ~200 back-to-back requests
    sleep 0.3
  fi
  python3 - "$out" "$name" "$ver" << 'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
name, ver = sys.argv[2], sys.argv[3]
open_cves = [i for i in data.get("issues", [])
             if i.get("status") in ("Vulnerable", "Testing")]
if open_cves:
    worst = max(open_cves, key=lambda i:
        ["Unknown","Low","Medium","High","Critical"].index(i.get("severity","Unknown")))
    cves = ",".join(i["name"] for i in open_cves[:6])
    print(f"{name} {ver} OPEN={len(open_cves)} worst={worst.get('severity')} {cves}")
EOF
done

if [ -f "$CACHE/unmapped.txt" ]; then
  echo "--- unmapped (curate arch_name map): $(sort -u "$CACHE/unmapped.txt" | wc -l)"
  sort -u "$CACHE/unmapped.txt"
fi
if [ -f "$CACHE/failed.txt" ]; then
  echo "--- FETCH FAILURES: $(sort -u "$CACHE/failed.txt" | wc -l) — sweep INCOMPLETE, treat as partially blind"
  sort -u "$CACHE/failed.txt"
fi
echo "--- cache: $CACHE"

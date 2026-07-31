#!/bin/bash
# Tier-1b security check: version lag for the /opt binary blobs + kernel.
# These are OUTSIDE the source inventory, so the Arch tracker never sees
# them (brave is not even in Arch's repos). For Chromium-shell apps
# (brave, vscode, slack, discord) staying current IS the security
# control — browser lag = priority 1 per /lfs-sweep.
# Pinned versions are parsed from the repo's install scripts (the repo
# IS the system).
# Latest versions come from Arch repos + AUR (NOT api.github.com: cloud
# routine sessions carry a repo-scoped GitHub token whose proxy 403s
# every other repo — see issue #8, 2026-07-16). Distro-tracked versions
# may lag upstream by a few days; acceptable for a daily lag check.
# Network: archlinux.org, aur.archlinux.org, www.kernel.org, api.osv.dev.
# NEVER aborts on fetch failure — every failure becomes FETCH-FAILED so
# the routine can report partial blindness instead of dying (issue #8:
# a kernel.org 403 + set -e/pipefail killed the whole script).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
POST="$REPO/build/blfs/scripts-post"

pin() {
  # pin <extended-regex with one capture group> -> captured version.
  # Superseded install scripts stay in the repo, so several pins can
  # match; the EFFECTIVE pin is the newest version, not the first file
  # in glob order.
  local re="$1"
  grep -rhoE "$re" "$POST"/*.sh "$REPO"/build/gated/*.sh 2>/dev/null | sed -E "s/$re/\\1/" | sort -V | tail -1 || true
}

arch_ver() {
  # arch_ver <arch-package> -> pkgver from Arch repos (empty on failure)
  curl -sm20 --retry 2 --retry-delay 2 --retry-all-errors \
    "https://archlinux.org/packages/search/json/?name=$1" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    r=json.load(sys.stdin)["results"]
    print(r[0]["pkgver"] if r else "")
except Exception: print("")' || true
}

aur_ver() {
  # aur_ver <aur-package> -> Version minus epoch/pkgrel (empty on failure)
  curl -sm20 --retry 2 --retry-delay 2 --retry-all-errors \
    "https://aur.archlinux.org/rpc/?v=5&type=info&arg=$1" 2>/dev/null \
    | python3 -c 'import json,sys,re
try:
    r=json.load(sys.stdin)["results"]
    v=r[0]["Version"] if r else ""
    print(re.sub(r"^[0-9]+:","",v).rsplit("-",1)[0])
except Exception: print("")' || true
}

report() {
  # report <name> <pinned> <latest>  (strip any non-digit tag prefix)
  local n="$1" p="$2" l
  l=$(echo "$3" | sed 's/^[^0-9]*//')
  if [ -z "$l" ]; then echo "$n pinned=${p:-UNKNOWN} latest=FETCH-FAILED"; return; fi
  if [ -z "$p" ]; then echo "$n pinned=UNKNOWN latest=$l (unversioned artifact — verify installed version in the VM)"; return; fi
  if [ "$p" = "$l" ]; then echo "$n pinned=$p latest=$l OK"
  elif [ "$(printf '%s\n' "$p" "$l" | sort -V | tail -1)" = "$p" ]; then
    echo "$n pinned=$p latest=$l AHEAD (distro source lags us — not actionable)"
  else echo "$n pinned=$p latest=$l LAG"; fi
}

report brave  "$(pin 'brave-browser-([0-9.]+)-linux-amd64')" "$(aur_ver brave-bin)"
report vscode "$(pin 'vscode-([0-9.]+)-linux-x64')"          "$(aur_ver visual-studio-code-bin)"
report slack  "$(pin 'slack-desktop-([0-9.]+)-amd64\.deb')"  "$(aur_ver slack-desktop)"
report gh     "$(pin 'gh_([0-9.]+)_linux_amd64')"            "$(arch_ver github-cli)"
report docker "$(pin 'docker-([0-9.]+)\.tgz')"               "$(arch_ver docker)"
report node   "$(pin 'node-v([0-9.]+)-linux-x64')"           "$(arch_ver nodejs)"
report tofu   "$(pin 'tofu_([0-9.]+)_linux_amd64')"          "$(arch_ver opentofu)"
report caddy  "$(pin 'caddy_([0-9.]+)_linux_amd64')"         "$(arch_ver caddy)"
report mise   "$(pin 'mise-v([0-9.]+)-linux-x64')"           "$(arch_ver mise)"
report fzf    "$(pin 'fzf-([0-9.]+)-linux_amd64')"           "$(arch_ver fzf)"
report ripgrep "$(pin 'ripgrep-([0-9.]+)-x86_64-unknown')"   "$(arch_ver ripgrep)"
report micro  "$(pin 'micro-([0-9.]+)-linux64')"             "$(arch_ver micro)"
report fd     "$(pin 'fd-v([0-9.]+)-x86_64-unknown')"        "$(arch_ver fd)"
# codex is AUR-only (no Arch official package), so this report line is
# its whole feed; tier 1 skips it via the arch_name SKIP entry
report codex  "$(pin 'codex-([0-9.]+)-x86_64-unknown')"      "$(aur_ver openai-codex-bin)"
# the four below surfaced UNMONITORED by the 2026-07-17 coverage check;
# unversioned artifacts report pinned=UNKNOWN until pinned at next update
report cloudflared "$(pin 'cloudflared-([0-9.]+)-linux')"    "$(arch_ver cloudflared)"
report discord "$(pin 'discord-([0-9.]+)\.tar\.gz')"         "$(arch_ver discord)"
report gcloud "$(pin 'google-cloud-[a-z]+-([0-9.]+)-linux')" "$(aur_ver google-cloud-cli)"
report chrome "$(pin 'google-chrome[a-z-]*[_-]([0-9.]+)')"   "$(aur_ver google-chrome)"
# go surfaced UNMONITORED by the first invariant-check I4 run (2026-07-23):
# a /usr/local toolchain installed via the gated flow — pin() now also
# reads build/gated so gated installs join the lag check
report go     "$(pin 'go([0-9.]+)[. ]linux-amd64')"          "$(arch_ver go)"

# tier 1b-py: user-level PyPI tools (uv) — outside the source inventory
# AND the distro trackers; OSV.dev is the deterministic feed. Pins live
# in ops/pypi-tools.txt (regenerate: scripts/coverage-check.sh --pypi).
PYPI="$REPO/ops/pypi-tools.txt"
if [ -f "$PYPI" ]; then
  grep -vE '^#|^$' "$PYPI" | while read -r name ver; do
    res=$(curl -sm20 --retry 2 --retry-delay 2 --retry-all-errors \
      -X POST https://api.osv.dev/v1/query \
      -d "{\"package\":{\"ecosystem\":\"PyPI\",\"name\":\"$name\"},\"version\":\"$ver\"}" 2>/dev/null \
      | python3 -c 'import json,sys
try:
    v=json.load(sys.stdin).get("vulns",[])
    print("VULN " + ",".join(x["id"] for x in v) if v else "CLEAN")
except Exception: print("FETCH-FAILED")') || res=FETCH-FAILED
    echo "pypi/$name $ver ${res:-FETCH-FAILED}"
  done
fi

# kernel: compare our point release against kernel.org's latest on the
# same stable branch (branch missing from releases.json => EOL alarm)
kver=$(bash "$REPO/scripts/lfs-inventory.sh" | awk '$1=="linux"{print $2}')
kbranch=$(echo "$kver" | cut -d. -f1-2)
klatest=$(curl -sm20 --retry 2 --retry-delay 2 --retry-all-errors \
  https://www.kernel.org/releases.json 2>/dev/null \
  | python3 -c "import json,sys
try:
    d=json.load(sys.stdin)
    print(next((r['version'] for r in d['releases'] if r['version'].startswith('$kbranch.')),'BRANCH-GONE'))
except Exception: print('')" || true)
if [ "$klatest" = "BRANCH-GONE" ]; then
  echo "linux pinned=$kver latest=BRANCH-GONE ($kbranch absent from kernel.org releases.json — branch EOL, plan a major bump)"
else
  report "linux($kbranch)" "$kver" "$klatest"
fi

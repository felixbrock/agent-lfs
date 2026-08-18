#!/bin/bash
# Coverage tripwire: everything runnable on the live system must be in a
# monitored feed (source inventory -> tiers 1/1c, binary-check reports ->
# tier 1b, ops/pypi-tools.txt -> OSV) or in ops/coverage-ignore.txt with a
# reason. Deterministic completeness check — catches installs that reached
# the system without joining the sweep (first run 2026-07-17: chrome,
# discord, mise, cloudflared, gcloud + 26 PyPI packages were invisible to
# every tier). LOCAL only (reads the live filesystem); the cloud tiers
# stay repo+network.
#   usage: coverage-check.sh          run the tripwire (exit 1 on findings)
#          coverage-check.sh --pypi   regenerate ops/pypi-tools.txt
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PYPI="$REPO/ops/pypi-tools.txt"
IGNORE="$REPO/ops/coverage-ignore.txt"

gen_pypi() {
  echo "# PyPI packages across uv tool envs and extra venvs registered in"
  echo "# ops/extra-pypi-venvs.txt (user-level installs), name version."
  echo "# Monitored daily via OSV.dev in binary-check.sh (tier 1b-py). Regenerate"
  echo "# after any uv or extra-venv install/upgrade via coverage-check.sh --pypi."
  { for t in "$HOME"/.local/share/uv/tools/*/; do
      ls "$t"lib/python*/site-packages/ 2>/dev/null
    done
    # extra user-level venvs (paths relative to $HOME), instance list
    # lives in the ops repo; absent file just contributes nothing
    while IFS= read -r v; do
      ls "$HOME/$v"/lib/python*/site-packages/ 2>/dev/null || true
    done < <(grep -hvE '^#|^$' "$REPO/ops/extra-pypi-venvs.txt" 2>/dev/null)
  } | grep -oE '^[A-Za-z0-9._-]+-[0-9][A-Za-z0-9.]*\.dist-info' \
       | sed -E 's/\.dist-info$//; s/^(.*)-([0-9][A-Za-z0-9.]*)$/\1 \2/' \
       | tr 'A-Z_' 'a-z-' | sort -u
}

if [ "${1:-}" = "--pypi" ]; then
  gen_pypi > "$PYPI"
  echo "wrote $PYPI — commit the diff"
  exit 0
fi

MON=$( { bash "$REPO/scripts/lfs-inventory.sh" | awk '{print tolower($1)}'
         grep -hoE '^report [a-z0-9-]+' "$REPO/scripts/binary-check.sh" | awk '{print $2}'
         grep -hvE '^#|^$' "$PYPI" 2>/dev/null | awk '{print $1}'
         grep -hvE '^#|^$' "$IGNORE" 2>/dev/null | awk '{print $1}'
       } | sort -u )

know() { echo "$MON" | grep -qxF "$1"; }

miss=0
for f in /usr/local/bin/* /opt/*; do
  { [ -e "$f" ] || [ -L "$f" ]; } || continue
  n=$(basename "$f" | tr 'A-Z' 'a-z')
  know "$n" && continue
  # uv tool stubs count as monitored when their tool is in the pypi list
  tool=$(readlink -f "$f" 2>/dev/null | sed -nE 's|.*/uv/tools/([^/]+)/.*|\1|p')
  if [ -n "$tool" ]; then
    know "$tool" && continue
  fi
  echo "UNMONITORED $f"
  miss=1
done

if ! diff -q <(gen_pypi | grep -vE '^#') <(grep -vE '^#' "$PYPI" 2>/dev/null) >/dev/null 2>&1; then
  echo "STALE-PYPI: uv envs differ from ops/pypi-tools.txt — rerun --pypi, commit"
  miss=1
fi

if [ $miss = 0 ]; then
  echo "coverage OK: everything found is monitored or ignored-with-reason"
fi
exit $miss

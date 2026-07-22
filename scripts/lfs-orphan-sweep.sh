#!/bin/bash
# Orphan sweep for the manifest-diff upgrade procedure. Runs INSIDE the chroot.
#
# Why this exists: a naive "in old manifest but not in new" diff flags LIVE
# files, because install tools skip content-identical files (ExtUtils prints
# "Skip ... (unchanged)"; openssl preserves /etc/ssl/*.cnf; make install
# leaves existing symlinks). Deleting those would break the system.
#
# Classification per orphan path:
#   1. dangling symlink                  -> delete
#   2. matches the package's stale regex -> delete (old-version paths)
#   3. no longer exists on disk          -> nothing to do
#   4. otherwise                         -> LIVE: re-adopt into new manifest
#
# Usage (inside chroot): lfs-orphan-sweep.sh PKGID:STALE_REGEX [PKGID:REGEX ...]
# Expects /var/lib/lfs-pkg/PKGID.list and PKGID.list.prev. Removes .prev on
# success. Empty directories left by deletions are pruned.
set -euo pipefail

PKGDB=/var/lib/lfs-pkg

for spec in "$@"; do
  pkg=${spec%%:*}
  regex=${spec#*:}
  new="$PKGDB/$pkg.list"
  prev="$PKGDB/$pkg.list.prev"
  [ -f "$new" ] || { echo "$pkg: no manifest"; exit 1; }
  [ -f "$prev" ] || { echo "$pkg: no .prev manifest"; exit 1; }

  deleted=0; adopted=0; gone=0
  while IFS= read -r f; do
    if [ -L "$f" ] && [ ! -e "$f" ]; then
      rm -f "$f"; deleted=$((deleted+1))
    elif echo "$f" | grep -qE -e "$regex"; then
      rm -rf "$f"; deleted=$((deleted+1))
    elif [ ! -e "$f" ] && [ ! -L "$f" ]; then
      gone=$((gone+1))
    else
      echo "$f" >> "$new"; adopted=$((adopted+1))
    fi
  done < <(comm -23 <(sort "$prev") <(sort "$new"))

  sort -u -o "$new" "$new"
  # prune now-empty dirs that the old manifest owned
  while IFS= read -r f; do
    d=$(dirname "$f")
    while [ "$d" != / ] && [ -d "$d" ] && [ -z "$(ls -A "$d")" ]; do
      rmdir "$d"; d=$(dirname "$d")
    done
  done < <(comm -23 <(sort "$prev") <(sort "$new"))
  rm -f "$prev"
  echo "$pkg: deleted=$deleted re-adopted=$adopted already-gone=$gone"
done

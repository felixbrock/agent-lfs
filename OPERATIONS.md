# Operating Model — running LFS as a daily driver

The owner delegates routine OS operations to the agent. This documents what replaces
each piece of Arch infrastructure and who does what.

Companion file: **AGENT-DESIGN.md** — deliberate divergences from LFS that
make the system operable by an agent (boot counting + auto-rollback,
rescue root, machine-readable state, on-system operational journal).
Procedures below assume those mechanisms once they land.

## What Arch provided vs our replacement

| Arch | Ours |
|---|---|
| pacman -Syu update feed | Weekly automated sweep: release-monitoring.org (Anitya) for upstream releases + LFS/BLFS security advisories, filtered to installed packages |
| Signed packages | TLS + book/recorded checksums, pinned in git (weaker; accepted) |
| pacman local DB | /var/lib/lfs-pkg manifests (file lists per package) |
| makepkg/PKGBUILDs | build/*/NNN-pkg.sh scripts in this repo (reproducible, verbatim-from-book where possible) |
| No rollback | Gate D: btrfs root + snapshot-before-upgrade + GRUB fallback kernel |
| Arch security team | High-risk watchlist gets priority: kernel, glibc, openssl, curl, openssh, xorg-server, browser binaries |

## Upgrade procedures

1. **Normal package**: bump version in its script → build in chroot →
   manifest diff (install new, remove orphans) → VM boot-test → apply.
   To be wrapped in a `lfs-pkg upgrade` helper (Gate C deliverable).
2. **Kernel**: build via ch9/020-kernel.sh with new version; keep previous
   kernel + GRUB entry until the new one has boot-tested.
   Venue policy (2026-07-17): kernel builds stay in the build-host
   chroot while the live system runs on removable media — the chroot
   sits on fast internal storage (I/O + flash wear), holds the whole
   config-versioning/stamp/mkimage pipeline, and keeps the VM twin
   coherent from the same script run. Building natively would not even
   save a reboot: the boot *test* needs metal regardless. After the
   migration to a permanent internal disk, stand up and PROVE the
   native on-LFS kernel pipeline BEFORE the old host is retired —
   native builds are the end state once the build host is gone.
   VM scope (2026-07-17): with the live system on metal, the VM is
   rehearsal for boot-critical changes ONLY (kernel, GRUB, initramfs,
   LUKS, systemd/glibc-class); routine userspace upgrades are built
   and verified natively on the live system. The VM is not carried
   past the old host — rehearsal is superseded by rollback machinery:
   it retires when boot counting + fallback kernel + rescue root
   (AGENT-DESIGN D1/D2/D3) are proven on the permanent disk.
3. **Toolchain (glibc/gcc majors)**: NEVER in place. Rebase onto the next
   LFS book edition: re-run the full pipeline (automated), migrate /etc
   deltas + /home, boot-test, switch. Cadence ~6 months.
4. **Upstream binaries** (browser, editors, electron apps): scheduled
   re-fetch of latest releases — the browser is the largest attack surface on the
   whole system and MUST stay current.

## Rules

- The live system never diverges from repo + sources: no hand-edits without
  a script/commit. /etc on the LFS system goes under git.
- Every upgrade batch: snapshot (or VM image copy) first, boot-test after;
  on hardware, boot-counting auto-rollback is the safety net (AGENT-DESIGN
  D1/D2), and the rescue root (D3) is never upgraded in the same batch.
- Every operational session: starts with `system-status`, ends by updating
  /var/lib/agent/STATE.md; all state changes append to
  /var/log/agent-actions.log (D6/D7).
- Security cadence (owner-endorsed): tier-1 check
  (scripts/security-check.sh against the Arch security tracker) via
  scheduled cloud run; full /lfs-sweep and the release sweep at lower
  frequencies (the concrete schedule lives in the private config repo).
  The owner gets a digest only when something is actionable, and gives
  go/no-go only for kernel/toolchain-class changes. Rationale: beats a
  realistic rolling-distro baseline (occasional manual -Syu) on patch
  latency.
- Non-security currency updates (version lags whose release notes carry
  no security content) are batched on one fixed day each month rather
  than re-triaged daily. Daily monitoring verifies an item once when it
  first appears, then parks it for the batch. Security-actionable items
  never wait for the batch day, and kernel/toolchain-class items keep
  their own go/no-go rules. The concrete batch day and procedure live
  in the private operations repo.
- Language-package-manager installs (npm and similar) get a standing
  supply-chain quarantine rather than per-incident vetting, because
  registry worms recur with the same shape. Three generic mechanisms.
  Install-time lifecycle scripts are disabled globally (the entry
  point of every npm worm wave to date). Version resolution is capped
  at a rolling N-day age via the resolver's before-date, wrappers that
  shadow the package-manager binaries on PATH inject it, so a poisoned
  release must survive N days of public scrutiny before it can even be
  picked, while ranges and latest-tags silently fall back to the
  newest old-enough version. A vetting helper resolves a candidate's
  full dependency tree without installing anything and reports
  lifecycle-script carriers and too-young versions. A named bypass
  variable exists for the rare legitimate exception, so the guard is
  never removed, only consciously stepped around. The concrete
  wrappers, quarantine window, and staging live in the private repos.

## Execution reliability (how the agent guarantees this actually happens)

Layered by what each mechanism actually guarantees:

1. **Repo CLAUDE.md** — the operator contract, auto-loaded into every
   session that touches this repo. Hard rules + session bootstrap live
   here. This is enforcement, not recollection.
2. **Skills** (.claude/skills/): /lfs-status (state handshake),
   /lfs-upgrade (manifest-diff upgrade), /lfs-sweep (security/release
   digest). Procedures are executed from these checklists, never
   re-derived from memory.
3. **On-system state** (AGENT-DESIGN D6/D7): STATE.md journal +
   agent-actions.log + system-status. The machine itself is the source
   of truth about the machine; sessions sync from it, not from chat
   history.
4. **Agent memory** (~/.claude/.../memory): orientation only — what the
   project is, where authority lives. Never procedure.
5. **Scheduling**: monitoring (/lfs-sweep steps 1-4 are network+repo
   only) can run as a scheduled routine producing a digest; build/apply
   requires a local session (owner-triggered or local cron running
   the agent headless — to be enabled when the cadence is proven manually).
6. **Resumability**: stamps + manifests + background tasks mean any
   interrupted operation resumes surgically; a session ending mid-work
   leaves uncommitted repo changes as the tripwire that /lfs-status
   detects at the next bootstrap.

## Division of labor

- The agent: monitoring sweeps, staged builds, VM boot-tests, manifest
  hygiene, binary refreshes, digests, book-edition rebases.
- The owner: go/no-go on kernel + toolchain upgrades on real hardware,
  occasional interactive smoke tests, hardware-touching steps.

## Open items feeding this (tracked in the private config repo)

- lfs-pkg upgrade helper + tested end-to-end upgrade of one real package
- /etc under git inside the LFS system
- btrfs decision at Gate D (recommended: yes)
- change temporary passwords (root/felix = "lfs") before Gate D
- microcode + firmware packages needed at Gate D (hardware, not VM)

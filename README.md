<p align="center">
  <img src="assets/banner.svg" width="840" alt="agent-lfs, a Linux From Scratch system built and operated by an AI agent">
</p>

A [Linux From Scratch](https://www.linuxfromscratch.org/) (LFS 13.0,
systemd) system built **and operated** by an AI agent.

## How it works

Linux From Scratch normally means compiling a whole Linux system
from source by hand, following the LFS book. This project changes
two things about that. Every step is a script in this repo. And an
AI agent, not a human, runs the scripts and then keeps operating the
finished system. Everything on the machine traces back to a script
committed here.

- **everything is scripted**, one reproducible build script per
  package, a recorded list of every file a package installed (its
  manifest), a checksum check for every download before it is used,
  and a written register entry for every place we differ from the
  book
- **an agent runs the system**, builds, upgrades, security
  monitoring, and boot testing, all under written rules, the
  contracts (CLAUDE.md, OPERATIONS.md, AGENT-DESIGN.md)
- **the human does two things**, says yes or no before any change to
  the kernel or the toolchain (the compiler and core libraries
  everything else is built with), and performs the steps that need a
  person at the machine, like typing a disk password or swapping
  hardware; nothing else
- **a real daily driver**, boots a real laptop with working GPU
  acceleration, Wi-Fi, and Bluetooth, and the agent works *on* that
  laptop, inside the system it operates
- **no package manager, on purpose**, a package manager proves you
  received the same bytes as everyone else, it does not prove that
  anyone read what those bytes do at install time; here every
  install is a script that was read, reviewed, and pinned
- **reading install scripts finds real bugs**, two of the reports on
  [the public reports page](https://felixbrock.github.io/upstream-reports/)
  came from reading one vendor's installer before running it (its
  checksum verification could silently switch itself off, and it
  fetched and ran a second, unverified script from the network);
  the packaged route would have caught neither, no official distro
  package exists and the community packages remove the vendor's
  checks instead of keeping them

The agent has five jobs,

- **builder**, compile the whole system from the book in the first
  place, and rebase onto each new book edition roughly twice a year
- **package manager**, build the new version, compare the old and
  new file lists, apply the difference onto a fresh disk snapshot (a
  saved copy of the filesystem the machine can fall back to),
  boot-test, then make it the running system
- **security monitor**, two layers, a scheduled cloud check (the
  sweep) that queries public vulnerability databases (the CVE
  trackers) and release feeds for every installed component (~290
  tracked), and a daily scan of the machine itself (open network
  ports, programs that run with elevated rights, autostart entries)
  diffed against committed baselines, including a check that the
  system's own guards are still armed
- **incident responder**, both checks deliver findings as GitHub
  issues; pick up the open ones at the start of every session and
  work each one to a fix that lands in the repo
- **contributor**, a periodic review flags work worth publishing as
  a [case study](#case-studies) or worth reporting to the people who
  maintain the affected software (upstream); the agent drafts, the
  human approves what goes out

> **Two audiences read this file.** A **human** deciding whether to
> run this reads [For the human](#for-the-human) and stops. An
> **agent** operating the system, or anyone wanting the full
> picture, starts at [For the agent](#for-the-agent).

## For the human

You don't build or run this yourself. You **supervise an agent that
does**, and stay available for the few decisions and physical steps
only you can make.

### Quickstart

1. **Get a coding agent on its strongest model.** This system was
   built and is operated with Claude Code on Claude's strongest
   model tier (currently Fable 5). A source build runs for days, and
   weaker models lose the thread over that many steps. Other agents
   work too (see [Operating](#operating)).
2. **Create two private repos of your own.** One *config* repo for
   facts about your machine (device paths, secrets policy) and one
   *ops* repo for what happens to that machine over time. Nothing
   about your specific machine ever goes into this public repo (the
   blueprint), and the agent walks you through the setup. Why the
   separation matters is
   [case study 005](case-studies/005-operating-in-public-without-leaking.md).
3. **Point the agent at this repo and say what you want.** "Build
   this system", or on a machine that already runs it, ask where
   things stand. The contracts and the skills (prewritten procedures
   the agent loads) contain every step.
4. **Stay in the loop.** The agent hands control back to you in
   exactly two cases, a yes-or-no decision on a kernel or toolchain
   change, and an action that needs root rights or a person at the
   machine.

### Requirements

Everything here is needed up front, because the new system runs
*next to* your real one for weeks before it can replace anything.

- a Linux machine you keep, it stays the build host and the safety
  net until the new system is proven (never your only machine)
- a separate place to install to, a spare disk, SD card, or
  partition
- enough hardware, a multi-core CPU and tens of GB of free disk
- a coding agent on a strongest-tier model, and an account whose
  usage limits survive a build that runs for days, mostly
  unattended
- your time and judgment for the yes-or-no moments and the hands-on
  steps

### Architecture

The whole operating model in one picture. You make the yes-or-no
calls (the diagram says go/no-go) and do the physical steps. The
agent does everything else, treating this repo as the single source
of truth. Scheduled security checks watch the result, and every
change carries an automatic way back.

What the boxes in the diagram mean,

- **fixes become scripts before they touch the machine**, the script
  changes first and is applied second, never the reverse, so nothing
  exists on the machine that the repo cannot explain
- **packages build in an isolated environment**, either a chroot on
  the build host (a directory tree the build is locked into, so it
  cannot touch the rest of the machine) or directly on the live
  system, with the same checksum check, done-markers, and manifests
  either way; changes that could break booting are tried first in a
  QEMU virtual machine that mirrors the real system (the VM twin)
- **each kind of software is watched the way it needs**, source
  packages against the Arch *and* Debian security trackers (two
  independent sources), vendor binaries by how far they trail the
  newest release, user-level Python tools via OSV.dev, and LFS/BLFS
  advisories as ready-made fix recipes; findings arrive as GitHub
  issues, and a broken check opens an issue about itself, so a quiet
  day means a clean day
- **nothing installed goes unwatched**, `scripts/coverage-check.sh`
  compares the list of installed software against the list of
  monitored software and keeps flagging the difference until every
  item is monitored or ignored with a written reason (its first run
  caught a Chrome install nobody was watching)
- **every upgrade can be undone automatically**, each batch of
  upgrades is applied onto a fresh btrfs snapshot, the boot loader
  counts failed boot attempts and switches back to the previous
  snapshot on its own (systemd-boot boot counting), and a separate
  rescue system (its own boot entry, never upgraded together with
  the main one) comes up reachable over SSH if even that fails
- **the system keeps its own written history**, a STATE.md journal,
  the per-package manifests, and an action log the kernel only
  allows appending to, never editing (`chattr +a`), so a new session
  can reconstruct where things stand without any chat history

```mermaid
flowchart TB
    OWNER(["Owner (human)<br/>go/no-go on kernel & toolchain,<br/>hardware hands, alert recipient"])

    subgraph FEEDS["External security & release feeds"]
        direction LR
        TRACK["Distro security trackers<br/>(Arch + Debian,<br/>independent lenses)"]
        OSV["OSV.dev<br/>(PyPI user tools)"]
        ADV["LFS/BLFS<br/>advisories"]
        UP["Upstream<br/>release data"]
    end

    subgraph CLOUD["Cloud (scheduled)"]
        SWEEP["Daily security sweep<br/>CVE + version-lag checks<br/>for every installed package"]
        REVIEW["Outward-contributions review<br/>(~every 5 days)<br/>anything worth publishing as a<br/>case study or reporting upstream?"]
    end

    subgraph GH["GitHub"]
        REPO["Public blueprint repo (this)<br/>build scripts, operator contracts,<br/>skills, sweep scripts, case studies"]
        PRIV["Private repos (config + ops)<br/>machine.env, instance scripts,<br/>live ledger, gate history"]
        ISSUES["Issues (on the private ops repo)<br/>findings channel + review nudges<br/>('security: N actionable',<br/>'sweep failing', 'contributions review')"]
    end

    OUT["Outward contributions<br/>public case studies +<br/>upstream bug reports / LFS dev list"]

    subgraph SYS["LFS system — the live machine (agent-operated daily driver)"]
        AGENT["Agent session<br/>(operator & package manager)"]
        SCHED["Local timers (systemd)<br/>daily morning session +<br/>daily host security scan +<br/>monthly non-security batch day"]
        CHROOT["On-system build chroot<br/>(package factory)"]
        SNAP["btrfs snapshot per change +<br/>systemd-boot boot counting<br/>(automatic rollback)"]
        STATE["Machine-readable state:<br/>package manifests,<br/>STATE.md journal, action log"]
        TRIP["Invariant check (I1–I5)<br/>(session post-condition: every file<br/>traces to a script, every source to<br/>a pin, everything is monitored,<br/>scripts keep the contract style)"]
        RESCUE["Rescue root<br/>(own boot entry, never upgraded<br/>with the main root)"]
    end

    VM["QEMU VM twin<br/>(boot-test bed, runnable from<br/>any machine with repo + image)"]

    FEEDS -->|CVE & version queries| SWEEP
    REPO -->|checked out per run| SWEEP
    SWEEP -->|opens / comments / auto-closes| ISSUES
    PRIV -->|recent work reviewed| REVIEW
    REVIEW -->|opens a nudge issue| ISSUES
    ISSUES -->|notification email| OWNER
    ISSUES -->|open findings picked up<br/>at session bootstrap| AGENT
    SCHED -->|fires the daily morning session,<br/>which applies security updates and<br/>runs the non-security batch when due| AGENT
    SCHED -->|host-scan drift<br/>opens an issue| ISSUES
    AGENT -->|drafts; owner approves & sends| OUT
    OWNER -->|publishes case study /<br/>files upstream report| OUT
    REPO -->|contracts + skills<br/>loaded every session| AGENT
    PRIV -->|machine.env +<br/>local contract + ops scripts| AGENT
    AGENT -->|every fix lands as a script<br/>change, committed back| REPO
    AGENT -->|upgrade: bump version,<br/>rebuild package| CHROOT
    CHROOT -->|manifest diff applied<br/>onto a fresh snapshot| SNAP
    SNAP -.->|if rollback also fails:<br/>comes up reachable for repair| RESCUE
    AGENT -->|risky batches:<br/>twin-first boot-test| VM
    AGENT -->|journals every session,<br/>logs every state change| STATE
    AGENT -->|post-condition of<br/>every session| TRIP
    OWNER -->|go/no-go,<br/>hardware steps| AGENT
```

### Upstream reports

The project reports the bugs it finds back to the maintainers of the
affected software. Each defect is traced to its exact cause and
checked against that project's bug tracker, so we never file a
duplicate. If someone already filed it, we add a confirmation with
our findings to the existing thread instead. Reports go out under
the owner's identity. The source of record lives in the private ops
repo, and every change republishes the public table at

**https://felixbrock.github.io/upstream-reports/**

## For the agent

Everything below is the operational detail, written for the operator
(an agent, or a deeply technical reader). Read
[How it works](#how-it-works) at the top first, then the human
section, its [Architecture](#architecture) diagram is written for
you too.

### Operating

```sh
git clone https://github.com/felixbrock/agent-lfs.git ~/repos/agent-lfs
cd ~/repos/agent-lfs
claude    # any coding agent works, the operator contract is CLAUDE.md / AGENTS.md
```

Telling the agent "build this system", or `/lfs-status` on a built
one, is enough. The contract, the book pages copied into `book/`,
the scripts, and the skills (`.claude/skills/`, `/lfs-status`
`/lfs-upgrade` `/lfs-sweep`) contain the full procedure. The
checksum ledger (the pinned list every download must match) and the
manifests catch any step that strays from it. Use a strongest-tier
model, and expect to stay in the loop for root commands and
yes-or-no calls.

Not a Claude Code user? The same contract is mirrored at
[AGENTS.md](AGENTS.md), the file name read by
[Codex CLI](https://github.com/openai/codex),
[Hermes Agent](https://github.com/NousResearch/hermes-agent), and
most other coding agents. Skills are plain markdown, point your
agent at `.claude/skills/*/SKILL.md`. The same model rule holds.

Everything specific to one machine comes from the private sibling
repos, see [Three-repo split](#three-repo-split). The blueprint
never needs editing for machine-specific values.

### Reading order

- [OPERATIONS.md](OPERATIONS.md), the operating model
- [CLAUDE.md](CLAUDE.md), the operator contract
- [AGENT-DESIGN.md](AGENT-DESIGN.md), the register of every place we
  differ from the book
- [PROVENANCE.md](PROVENANCE.md), the rules for where downloads may
  come from and how they are verified
- [INVARIANTS.md](INVARIANTS.md), the rules that must hold at all
  times, checked after every session
- [case-studies/](case-studies/), real diagnosis stories, the best
  sense of what this is like

### Invariants

An invariant is a rule about the system that must hold at all times.
The guarantees in [How it works](#how-it-works) are written down as
five explicit invariants in [INVARIANTS.md](INVARIANTS.md) and
checked as a whole. The shape is borrowed from the seL4 verification
project ([Klein et al., SOSP
2009](https://www.sigops.org/s/conferences/sosp/2009/papers/klein-sosp09.pdf)),
write every rule down explicitly and check each one mechanically.

- **I1**, every binary and library appears in a package manifest
- **I2**, every manifest traces back to a build script
- **I3**, every download is pinned in the checksum ledger
- **I4**, everything runnable is monitored, or ignored with a
  written reason
- **I5**, build scripts keep the style that makes failures visible
  (`set -euo pipefail`, one command per line)

`scripts/invariant-check.sh` checks all five, read-only, at the end
of every session. An upgrade isn't done when the package builds. It
is done when all five rules hold again. Gaps that existed before a
check are recorded in the private ops repo, never silently ignored.
The first full run found an unmonitored compiler toolchain and two
style violations, exactly the kind of small fault that testing tends
to miss and the seL4 bug data warns about.

### Building by hand

The same path the agent takes, the book turned into scripts. Expect
days of compile time, and a human for the root steps.

1. Set up the host per LFS 13.0 chapters 2–3 (the book pages are
   copied under `book/`), then run `sudo scripts/prep-ch4.sh`.
2. Download the sources into `/mnt/lfs/sources`. Every file must
   pass `scripts/verify-source.sh`, which compares it against the
   pinned checksum list (`ops/sources-sha256.txt`).
3. Run the chapters in order, `build/ch5` and `build/ch6` as the
   `lfs` user, `sudo scripts/prep-ch7.sh` (read its security note)
   for the `build/ch7`–`ch8` chroot, then chapter 9 and the BLFS
   tiers (`build/blfs/`). Every script records a done-marker and
   writes its manifest, so a rerun repeats only what is missing.
4. Boot-test in QEMU, `scripts/vm-up.sh` (`--display` for a
   window), `scripts/vm-down.sh` to shut down safely.

### Three-repo split

- **agent-lfs** (this repo, the blueprint), scripts, contracts,
  skills, the sweep machinery, case studies. Tied to no machine or
  person.
- **lfs-ops** (private, the operations log), the concrete machine's
  history, incidents, and current package state. A complete, current
  log of a personal machine that names its owner tells an attacker
  exactly what to attack, so episodes become public case studies
  only after time has passed and identifying detail is removed.
- **lfs-config** (private, the machine facts), what a session must
  read to operate this machine, `machine.env`, dotfiles,
  verification state, the credentials policy.

All three repos sit side by side. The blueprint's machinery finds
the config repo via `$LFS_CONFIG` and sources `machine.env`, which
points at the ops repo (`LFS_OPS`) and the live checksum ledger
(`LFS_LEDGER`). To run your own system, create your own private
pair. The blueprint never needs editing, and your operational
history never needs publishing.

### Provenance

Provenance means knowing where every downloaded file came from and
proving nobody tampered with it. Every file passes
`scripts/verify-source.sh` before it may enter the build. Known
files must match their sha256 checksum in the ledger byte for byte
(the blueprint ships an empty ledger, a running machine keeps its
real one private). A new file needs a checksum published somewhere
independent of the download itself, and is then pinned permanently.
A mismatch is treated as a possible attack on the download path, not
as an inconvenience, and work stops. Sources come only from each
project's canonical hosts, prebuilt binaries only from the vendor's
official endpoints (the full table is in PROVENANCE.md). Rebuilding
from the ledger gives you byte for byte the files this system was
built and boot-tested from.

### Case studies

Real failures, diagnosed to the actual cause, with the dead ends
left in. Published after the fact and in past tense, delayed when
security-relevant, and passed through a mechanical check for
information leaks (see
[case study 005](case-studies/005-operating-in-public-without-leaking.md)).

- [001, The touchpad that insisted it was a mouse](case-studies/001-touchpad-enumeration.md),
  four kernel revisions, two kernel-config traps, and the pattern of
  verifying a kernel config instead of trusting it
- [002, The GPU that was dark for days](case-studies/002-the-gpu-that-was-dark.md),
  a desktop that rendered on the CPU its whole life, and the rule
  that GPU firmware must be inside the initramfs
- [003, The invisible LUKS prompt](case-studies/003-the-invisible-luks-prompt.md),
  the disk-password prompt went to a console nobody could see, a gap
  that hid for ten kernel revisions
- [004, The build environment richer than the machine](case-studies/004-the-build-env-richer-than-the-machine.md),
  dependencies hiding in the chroot, and why "prove it builds on the
  real machine" became a required checkpoint (a gate)
- [005, Operating a personal machine in public without leaking it](case-studies/005-operating-in-public-without-leaking.md),
  how small harmless details add up to a dangerous public profile,
  and the three-repo split

### Known upstream issues & workarounds

Problems already known to their maintainers, already fixed in newer
book revisions, or not reportable by policy, kept here with their
workarounds. Genuinely new defects go to
[Upstream reports](#upstream-reports).

- **yajl 2.1.0**, does not build with CMake 4, worked around in
  `build/blfs/scripts/130-yajl.sh`. Upstream
  [#257](https://github.com/lloyd/yajl/issues/257) /
  [PR #256](https://github.com/lloyd/yajl/pull/256) unmerged, the
  project has been dormant since 2015.
- **unzip60**, does not build under GCC 15, which compiles as C23 by
  default, replaced with libarchive in
  `build/blfs/scripts-gatec/203-unzip.sh`. BLFS has since adopted
  the same path.
- **XML-Parser 2.54**, runtime dependencies missing from the LFS
  13.0 book (`build/ch8/425-427*.sh`, `430-xml-parser.sh`). Since
  addressed in the development books.
- **GCC 15.2 pass 1 under a GCC 16 host**, its libcody component
  fails to compile as C++20, pinned to gnu++17 for pass 1 only
  (`build/ch5/20-gcc-pass1.sh`). Not reportable to the book, hosts
  newer than tested are unsupported.

## License

Original work here (scripts, contracts, skills, documentation) is
MIT-licensed, see [LICENSE](LICENSE). The pages copied under
`build/` and `book/` are unmodified excerpts from the
[LFS](https://www.linuxfromscratch.org/lfs/) and
[BLFS](https://www.linuxfromscratch.org/blfs/) books, copyright ©
Gerard Beekmans and the LFS/BLFS development teams, under the books'
own licenses (CC BY-NC-SA for the text, MIT for the computer
instructions).

# AGENTS.md: ansible-runtime

Read `~/Code/AGENTS.md` first. This repo builds the shared Ansible container image
(`ghcr.io/git-cgallagher/ansible-runtime`) used locally and in the `git_cgallagher.*` collections' CI.
Public repo; the new-public-repo baseline applies.

## Layout

| Path | What |
|---|---|
| `Dockerfile` | `base` → `ci` (toolchain + third-party collections + the Molecule driver) and `runtime` (+ the other `git_cgallagher.*`) |
| `requirements/` | every pin: `python.in`/`python.txt`, `collections.yml`, `collections-runtime.yml`, `apt.txt` |
| `tests/smoke.sh` | runs in the image: versions equal the pins, no unpinned collections, tools present, playbooks parse |
| `tests/coverage.py` | consumer repos' declared collections are all pinned, inside their ranges |
| `tests/lock.sh` | regenerates `python.txt` inside the base image |
| `tests/playbooks/` | syntax-check playbooks touching each collection |
| `bin/ar` | local wrapper around `docker run` |
| `renovate.json` | Renovate config (the only dependency bot here; there is no `dependabot.yml`) |

## Pipeline (`.github/workflows/build.yml`)

- `image (target, arch)`: 4 jobs. Build (amd64 on `ubuntu-24.04`, arm64 natively on
  `ubuntu-24.04-arm`), `tests/smoke.sh`, grype scan (amd64; fails on fixable critical). Outside PRs,
  push by digest.
- `consumers`: builds `ci`, clones isc/windows/orchestration at `main`, runs `tests/coverage.py`,
  yamllint + ansible-lint on isc and windows, and one Molecule scenario (isc kea_dhcp, Debian 12)
  from inside the image against the runner's Docker.
- `manifest (target)`: not on PRs. Joins the two arches under the tags, refuses to overwrite an
  existing `X.Y.Z`, attests build provenance.
- Triggers: PR, push to `main`, tag `vX.Y.Z`, weekly (Mon 06:00 UTC, moves `:main` / `:main-ci` only;
  `sha-` tags are only made on push), manual.
- Required checks (ruleset): the four `image (…)` jobs and `consumers`. **Never `manifest`**: it
  doesn't run on PRs, so requiring it would block every merge.

## Releasing

1. Merge the change; `:main` / `:main-ci` publish.
2. Add a `## X.Y.Z` entry to `CHANGELOG.md` (in the change's PR).
3. `git tag vX.Y.Z && git push origin vX.Y.Z` → `:X.Y.Z`, `:X.Y`, `:latest` (+ `-ci`).

Semver for the image: patch = rebuild/doc-only; minor = any dependency bump; major = ansible-core
minor/major, Python minor, or a removed collection/package.

## Rules

- Every CI job sets `timeout-minutes` (2026-11-01): GitHub's default is 6 hours, and a stalled `apt-get`,
  pip or registry call would hold the runner that long. `image` and `consumers` get 30, `manifest` 15,
  several times their slowest green run. A new job needs one too.
- Every pin carries a comment saying why and who uses it. `DEPENDENCIES.md` "Current contents"
  changes in the same PR as a version change, Renovate's included.
- `python.txt` is generated. Edit `python.in`, run `tests/lock.sh`.
- Never re-point a released `X.Y.Z` tag. Fix forward with a new version.
- A consumer adding a collection: add the pin here first, then the consumer's change. Until then
  this repo's `consumers` job fails on `main` (it reads consumers at `main`), which is the alarm.

## ⚠️ Gotchas

- **Collections live in site-packages, not `~/.ansible`.** The consumers' Molecule configs set
  `ANSIBLE_COLLECTIONS_PATH=…:~/.ansible/collections`, and GitHub `container:` jobs set
  `HOME=/github/home`; either would hide collections installed in a home or in
  `/usr/share/ansible`. ansible-core always scans `sys.path` (`COLLECTIONS_SCAN_SYS_PATH`).
  `smoke.sh` checks this with both overridden.
- **Transitive collections must be pinned too.** `community.docker` pulls in
  `community.library_inventory_filtering_v1`; `smoke.sh` fails on any installed collection not in
  the pin files (`ansible._*` are ansible-core internals and exempt).
- **`molecule drivers | grep -q` under `set -o pipefail` fails at random** (grep exits early,
  molecule gets SIGPIPE). Capture the output first.
- **The image runs as root, deliberately.** GitHub `container:` jobs need it (the workspace and
  `/github/home` are root-owned) and so does the Docker socket. `bin/ar` runs it the same way.
- **Dependabot security updates are OFF here; Dependabot alerts stay ON** (a deliberate exception
  to the public-repo baseline). Renovate reads the alerts (`vulnerabilityAlerts`) and opens the fix
  PRs; Dependabot would open duplicates and can't regenerate the hashed `python.txt`.
- **The Molecule driver is in the `ci` target, pinned once by commit.** The consumers' scenarios
  say `driver: molecule-git-cgallagher` (shared `.config/molecule/config.yml`), so without it every
  Molecule run fails `Failed to find driver` (the first CI run on PR #1 did, after isc moved to
  the driver). `collections.yml` pins `ansible-collection-molecule` at a commit; the Dockerfile
  reads that commit to pip-install the driver, and `smoke.sh` checks both agree. Keep it at the
  SHA the consumers' `setup-molecule` action uses, and bump it by hand (Renovate can't).
  `ansible-collection-molecule`'s own CI must not use this image: it would test the baked copy.
- `ansible-lint` and `yamllint` versions here decide what passes in every consumer once they
  adopt the image; read a Renovate PR's `consumers` job before merging it.

## TODO

- Consumers migrated 2026-11-01: isc (lint, kea-render, Molecule; isc PR #22), windows (lint;
  windows PR #30), orchestration (Molecule; orchestration PR #16), each through its own
  `.github/ci/runtime.sh` (`docker run --network host`, checkout at the same path), not a `container:`
  job: isc's render test bind-mounts files into `docker run` and its Stork scenarios reach published
  ports on 127.0.0.1. Bump their `RUNTIME_IMAGE` (tag + digest) after each release.
- Windows KVM lab jobs: decide image-as-controller (`docker run --device /dev/kvm`) vs host.
- Install the Mend Renovate app on this repo (owner, UI only).

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
| `tests/collection_requirements.py` | `python.txt` satisfies every collection's `requirements.txt`, and in the `consumers` job their `tests/unit` + `tests/integration` requirements too (run in the `runtime` build, `smoke.sh` and `consumers`) |
| `build/derive_pins.py` | writes `/usr/share/ansible-runtime/{constraints.txt,collections.yml}` in the image (derived, for runner jobs) |
| `docs/SHARED-DEPENDENCIES.md` | the shared dependency model: every version chosen here; phases (tracking issue #8) |
| `tests/lock.sh` | regenerates `python.txt` inside the base image |
| `tests/playbooks/` | syntax-check playbooks touching each collection |
| `bin/ar` | local wrapper around `docker run` |
| `renovate.json` | Renovate config (the only dependency bot here; there is no `dependabot.yml`) |

## Pipeline (`.github/workflows/build.yml`)

- `image (target, arch)`: 4 jobs. Build (amd64 on `ubuntu-24.04`, arm64 natively on
  `ubuntu-24.04-arm`), `tests/smoke.sh`, grype scan (amd64; fails on fixable critical). Outside PRs,
  push by digest.
- `consumers`: builds `ci`, clones isc/windows/orchestration/aws at `main`, runs `tests/coverage.py`
  and `tests/collection_requirements.py`,
  yamllint + ansible-lint on isc, windows and aws, and one Molecule scenario (isc kea_dhcp, Debian 12)
  from inside the image against the runner's Docker.
- `release`: not on PRs; see Releasing.
- `manifest (target)`: not on PRs. Joins the two arches under the tags, refuses to overwrite an
  existing `X.Y.Z`, attests build provenance.
- Triggers: PR, push to `main`, tag `vX.Y.Z`, weekly (Mon 06:00 UTC, moves `:main` / `:main-ci` only;
  `sha-` tags are only made on push), manual.
- Required checks (ruleset): the four `image (…)` jobs and `consumers`. **Never `manifest`**: it
  doesn't run on PRs, so requiring it would block every merge.

## Releasing

**Automatic (collection bumps):** a merge to `main` whose only change is `version:` lines in
`requirements/collections-runtime.yml` (Renovate's automerged `git_cgallagher.*` PRs) is released
by `build.yml`'s `release` job as the next patch version. It tags that commit's `sha-` images (no
rebuild), then creates the git tag and a GitHub release through the API. These releases have no
CHANGELOG entry: the GitHub release is the record.

**By hand (everything else):**

1. Merge the change, with a `## X.Y.Z` entry in `CHANGELOG.md` in the same PR; `:main` / `:main-ci` publish.
2. Check the PR's merge commit is on `main` (`git log -1 origin/main`) **before tagging**.
3. `git tag -a vX.Y.Z -m … <merge commit> && git push origin vX.Y.Z` → `:X.Y.Z`, `:X.Y`, `:latest`
   (+ `-ci`), and the `release` job adds the GitHub release.

Semver for the image: patch = rebuild/doc-only; minor = any dependency bump; major = ansible-core
minor/major, Python minor, or a removed collection/package.

## Rules

- Every CI job sets `timeout-minutes` (2026-11-01): GitHub's default is 6 hours, and a stalled `apt-get`,
  pip or registry call would hold the runner that long. `image` and `consumers` get 30, `manifest` 15,
  several times their slowest green run. A new job needs one too.
- Every pin carries a comment saying why and who uses it. Versions live only in the pin files and
  the release notes (`tests/contents.py`); don't copy them into docs, where Renovate can't update them.
- `python.txt` is generated. Edit `python.in`, run `tests/lock.sh`.
- **Every version is chosen here** (docs/SHARED-DEPENDENCIES.md, issue #8). A consumer file that
  pins an exact version is a bug to remove, not a second source. Exceptions are listed in that doc.
- Never re-point a released `X.Y.Z` tag. Fix forward with a new version.
- A consumer adding a collection: add the pin here first, then the consumer's change. Until then
  this repo's `consumers` job fails on `main` (it reads consumers at `main`), which is the alarm.

## ⚠️ Gotchas

- **`ansible_collections.__path__` is a contract** (2026-11-02). setup-molecule 0.5.0's
  `collections-image` input copies the KVM labs' collections out of this image from that one
  directory (site-packages), instead of downloading them from Galaxy. `smoke.sh` checks it's a
  single directory holding every pinned collection. Moving collections elsewhere breaks the labs:
  change the action in the same round.

- **The driver pin moves with the labs, in one round.** `collections.yml`'s
  `ansible-collection-molecule` commit must equal the setup-molecule commit in isc's `windows-dc`
  and windows' `domain-lab`. A driver release that moves the labs without this pin leaves the image
  behind (happened with v0.3.2, 2026-11-02). Consumers' labs filter `git_cgallagher.molecule` out of
  the image's `collections.yml`, so a short gap doesn't break them, but the docker scenarios in the
  image then run an older driver than the labs.

- **Each `runtime.sh` call in a consumer is a fresh container.** Molecule's state under
  `~/.ansible/tmp` doesn't carry over between calls, so a separate `molecule prepare` after
  `molecule create` falls back to SSH. Use one `molecule test`, or one
  `runtime.sh bash -c '…'` for several steps (found by the aws Molecule work, 2026-11-01). The
  consumers' build and argument-specs jobs do the same for `/tmp` paths.
- **A job that varies ansible-core must drop `resolvelib` from the constraints too**
  (docs/SHARED-DEPENDENCIES.md, exception 2).

- **`python.txt` can't be a pip constraints file.** Its `--hash` lines put pip in
  `--require-hashes` mode, which then refuses any package the lock doesn't list (tested 2026-11-01).
  That's why the image carries a hash-free derived `constraints.txt`.
- **The derived `collections.yml` includes a git source** (`ansible-collection-molecule`), so
  `ansible-galaxy collection install -r` needs `git` (GitHub runners have it; `python:*-slim` doesn't).

- **One version per Python package, for every collection.** Collections declare floors in their
  `requirements.txt`; `python.txt` pins the version. If a collection release raises a floor past
  the pin, Renovate's bump PR for it fails `image (runtime, …)` and isn't automerged: bump the pin
  (`python.in` + `tests/lock.sh`, or merge the monthly Python PR), then the bump goes through.
  That's the intended failure, not a flake.
- **botocore caps `python-dateutil<3`** while kubernetes accepts 3.x. Adding boto3 (0.4.0) made
  `tests/lock.sh` backtrack into ancient botocore source releases that won't build
  (`README.rst` not found), because pip-compile kept the old `python-dateutil==3.0.0` pin. Fix:
  re-lock with `-P "python-dateutil<3"`. A fresh lock (Renovate's lock-file maintenance) resolves
  it on its own.

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
- **Renovate merges `git_cgallagher.*` bumps itself (2026-11-01, Chris's decision).** That's an
  exception to the baseline's merge-by-hand rule, scoped to those PRs: `automerge` with
  `platformAutomerge: false` (Renovate merges once every check passes; the repo's auto-merge setting
  stays off), and the Renovate app (id 2740) is the only bypass actor on the "external contributor
  review" ruleset (`pull_request` mode). "main protection" still requires every check. Nothing
  happens until the Mend Renovate app is installed on this repo.
- **A tag pushed with `GITHUB_TOKEN` starts no workflow.** That's why the automatic release tags the
  already-built `sha-` images instead of pushing a tag and letting the tag build run.
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

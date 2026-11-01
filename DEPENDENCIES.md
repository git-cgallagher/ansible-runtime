# Dependencies

Everything in the image is pinned in one of five places. Each file has a comment on every entry
saying **why it's there and who uses it**. Read those for the detail; this page is the map.

| What | File | Pinned how | Bumped by |
|---|---|---|---|
| Base OS + Python 3.13 | `Dockerfile` (`FROM python:3.13-slim-trixie@sha256:…`) | image digest | Renovate (`dockerfile`), monthly |
| docker CLI | `Dockerfile` (`FROM docker:X.Y.Z-cli@sha256:…`) | version + digest | Renovate (`dockerfile`), monthly |
| Debian packages | `requirements/apt.txt` | **not pinned** (Debian drops old versions); they follow the base digest and the weekly rebuild | weekly scheduled build |
| Python packages (ansible-core, ansible-lint, yamllint, Molecule, pypsrp, kubernetes, docker SDK) | `requirements/python.in` → `requirements/python.txt` | every package, transitive ones too, at one version + hashes; installed with `--require-hashes` | Renovate (`pip-compile`), monthly + lock-file maintenance |
| Third-party collections | `requirements/collections.yml` | exact version (a bare version is an exact pin to ansible-galaxy); transitive ones listed too | Renovate (`ansible-galaxy`), monthly |
| Our collections (`git_cgallagher.*`) | `requirements/collections-runtime.yml` | exact version, or a commit for one not on Galaxy yet | Renovate (`ansible-galaxy`) as soon as released; commit pins by hand |
| Molecule driver (`molecule-git-cgallagher` pip package + `git_cgallagher.molecule`) | `requirements/collections.yml` (one commit pin; the Dockerfile reuses it for the pip driver) | commit SHA of a tag | by hand, to the SHA the consumers' `setup-molecule` action pins |
| GitHub Actions | `.github/workflows/*.yml` | commit SHA + `# vX.Y.Z` comment | Renovate (`github-actions`), monthly |

Security fixes skip the monthly schedule: Renovate opens them as soon as a GitHub vulnerability
alert (Dependabot alerts are on for the repo) names a fixed version.

## Current contents

| | Version |
|---|---|
| Python | 3.13 (Debian 13 "trixie" slim) |
| ansible-core | 2.21.5 |
| ansible-lint | 26.10.1 |
| yamllint | 1.38.0 |
| molecule / molecule-plugins | 26.10.0 / 26.10.12 |
| pypsrp | 0.9.1 |
| kubernetes | 37.0.1 |
| docker (SDK) / docker CLI | 7.2.0 / 29.9.2 |
| ansible.windows | 3.9.2 |
| microsoft.ad | 1.12.1 |
| community.docker | 5.4.0 |
| community.library_inventory_filtering_v1 | 1.1.5 (community.docker dependency) |
| community.general | 13.5.0 |
| kubernetes.core | 6.6.0 |
| git_cgallagher.molecule + molecule-git-cgallagher | 0.2.0 at commit `b2601b3` (both targets) |
| git_cgallagher.isc | 1.6.2 (`runtime` only) |
| git_cgallagher.orchestration | 0.2.2 (`runtime` only) |
| git_cgallagher.windows | 0.2.0 at commit `00e66cd` (`runtime` only; not on Galaxy yet) |

Keep this table in step with the files in the same PR (Renovate PRs included: edit the table
on the Renovate branch before merging).

## Ranges vs pins

Published collections keep **`>=` ranges** in their own `galaxy.yml` / `requirements.yml`, because
Galaxy users need room. This image **pins exact versions**, because CI needs to be reproducible.
`tests/coverage.py` runs in CI and fails if a consumer repo declares a collection the image
doesn't pin, or a range the pin doesn't satisfy.

## How to…

**Add a Python package.** Add it to `requirements/python.in` with a comment (why, who), run
`tests/lock.sh` (needs Docker; resolves inside the base image), commit both files.

**Add a collection.** Add it to `requirements/collections.yml` (third-party) or
`collections-runtime.yml` (ours) with an exact version and a comment. If it pulls in another
collection, pin that too: `tests/smoke.sh` fails on any installed collection that isn't pinned.
Add a task using it to `tests/playbooks/ci.yml` or `runtime.yml`.

**Add a Debian package.** Add it to `requirements/apt.txt` with a comment.

**Bump ansible-core to a new minor.** Renovate opens it as its own PR (label `ansible-core`).
Widen the range in `python.in`, run `tests/lock.sh`, and check each collection's
`requires_ansible`. Release as a new **major** image version.

**Move to a new Python minor.** Manual on purpose (Renovate is told not to): change the
`FROM python:` tag + digest, `constraints.python` in `renovate.json`, re-run `tests/lock.sh`.

**Switch git_cgallagher.windows to Galaxy** once it's published (ansible-collection-windows
issue #3): replace the git entry with `name: git_cgallagher.windows` + `version:`.

**Bump the Molecule driver.** Change the `ansible-collection-molecule` commit in
`requirements/collections.yml` to the new tag's commit, the same SHA the consumers'
`setup-molecule` action moves to. The Dockerfile installs the pip driver from that commit too.

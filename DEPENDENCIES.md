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
| Our collections (`git_cgallagher.*`) | `requirements/collections-runtime.yml` | exact version | Renovate (`ansible-galaxy`) as soon as released, **merged by Renovate and released automatically** (below) |
| Molecule driver (`molecule-git-cgallagher` pip package + `git_cgallagher.molecule`) | `requirements/collections.yml` (one commit pin; the Dockerfile reuses it for the pip driver) | commit SHA of a tag | by hand, to the SHA the consumers' `setup-molecule` action pins |
| GitHub Actions | `.github/workflows/*.yml` | commit SHA + `# vX.Y.Z` comment | Renovate (`github-actions`), monthly |

**Your own collections reach the image with no human step.** A Galaxy release of
`git_cgallagher.isc`, `.windows` or `.orchestration` → Renovate opens a PR bumping
`collections-runtime.yml` (any time, not monthly) → when every check passes, Renovate merges it
itself → `build.yml`'s `release` job sees a merge that only changes those version lines, and
releases it as the next patch version (`:X.Y.Z`, `:X.Y`, `:latest`, + `-ci`) with a GitHub release
listing the contents. The collections' CI then picks it up when their `RUNTIME_IMAGE` is bumped.

Security fixes skip the monthly schedule: Renovate opens them as soon as a GitHub vulnerability
alert (Dependabot alerts are on for the repo) names a fixed version.

## Current contents

Each [GitHub release](https://github.com/git-cgallagher/ansible-runtime/releases) lists exactly what
its image contains: Python, every package `python.in` names, the Molecule driver, the docker CLI and
every collection. `tests/contents.py` writes that table from inside the image, so it reports what
is installed, not what the files say. For an unreleased build:

```bash
docker run --rm -v "$PWD":/src -w /src ghcr.io/git-cgallagher/ansible-runtime:main python tests/contents.py
```

(There used to be a hand-kept table here. Renovate can't edit it, so it went stale on every bump.)

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

**Bump the Molecule driver.** Change the `ansible-collection-molecule` commit in
`requirements/collections.yml` to the new tag's commit, the same SHA the consumers'
`setup-molecule` action moves to. The Dockerfile installs the pip driver from that commit too.

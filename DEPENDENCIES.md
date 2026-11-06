# Dependencies

**This repo is the only place a version is chosen** for any `git_cgallagher.*` repo's tooling.
Consumers either run in the image or read its derived pin files; their own files declare ranges
only. The model, its exceptions and the rollout: [docs/SHARED-DEPENDENCIES.md](docs/SHARED-DEPENDENCIES.md).

Everything in the image is pinned in one of five places. Each file has a comment on every entry
saying **why it's there and who uses it**. Read those for the detail; this page is the map.

| What | File | Pinned how | Bumped by |
|---|---|---|---|
| Base OS + Python 3.13 | `Dockerfile` (`FROM python:3.13-slim-trixie@sha256:…`) | image digest | Renovate (`dockerfile`), monthly |
| docker CLI | `Dockerfile` (`FROM docker:X.Y.Z-cli@sha256:…`) | version + digest | Renovate (`dockerfile`), monthly |
| Debian packages | `requirements/apt.txt` | **not pinned** (Debian drops old versions); every build runs `apt-get upgrade` on the pinned base, and `APT_REFRESH` re-runs that layer daily | every build (the cache refreshes daily), plus the weekly scheduled build |
| Python packages (ansible-core, ansible-lint, yamllint, Molecule, pypsrp, kubernetes, boto3/botocore, pyvmomi; test tools moto, flask, flask-cors, pytest) | `requirements/python.in` → `requirements/python.txt` | every package, transitive ones too, at one version + hashes; installed with `--require-hashes` | Renovate (`pip-compile`), monthly + lock-file maintenance |
| Third-party collections | `requirements/collections.yml` | exact version (a bare version is an exact pin to ansible-galaxy); transitive ones listed too | Renovate (`ansible-galaxy`), monthly |
| Our collections (`git_cgallagher.*`) | `requirements/collections-runtime.yml` | exact version | Renovate (`ansible-galaxy`) as soon as released, **merged by Renovate and released automatically** (below) |
| Molecule driver (`molecule-git-cgallagher` pip package + `git_cgallagher.molecule`) | `requirements/collections.yml` (one commit pin; the Dockerfile reuses it for the pip driver) | commit SHA of a tag | by hand, to the SHA the consumers' `setup-molecule` action pins |
| GitHub Actions | `.github/workflows/*.yml` | commit SHA + `# vX.Y.Z` comment | Renovate (`github-actions`), monthly |

**Your own collections reach the image with no human step.** A Galaxy release of
`git_cgallagher.isc`, `.windows`, `.orchestration` or `.aws` → Renovate opens a PR bumping
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

## Derived pin files, for jobs outside the image

Every image carries `/usr/share/ansible-runtime/constraints.txt` (`python.txt` without hashes) and
`collections.yml` (that target's collection pins), written by `build/derive_pins.py` at build time.
A job that has to run on the runner (a KVM lab, a release) reads them from the same `RUNTIME_IMAGE`
it already pins:

```bash
docker run --rm "$RUNTIME_IMAGE" cat /usr/share/ansible-runtime/constraints.txt > "$RUNNER_TEMP/constraints.txt"
pip install -c "$RUNNER_TEMP/constraints.txt" ansible-core molecule
```

## Ranges vs pins

Published collections keep **`>=` ranges** in their own `galaxy.yml` / `requirements.yml`, because
Galaxy users need room. This image **pins exact versions**, because CI needs to be reproducible.
`tests/coverage.py` runs in CI and fails if a consumer repo declares a collection the image
doesn't pin, or a range the pin doesn't satisfy.

## A collection's Python dependencies

A collection that needs Python on the controller (boto3 for `git_cgallagher.aws`) declares a
**floor** in its own `requirements.txt` (or the file its `meta/execution-environment.yml` names),
which ships in its Galaxy tarball. The image pins **one version** of each such package in
`python.txt`, shared by every collection, never one per collection. Two collections needing the
same package get the same version, and `tests/collection_requirements.py` proves it satisfies both:

- **Image build** (`runtime` target): checks every installed `git_cgallagher.*` collection's
  declaration against the installed packages. A miss fails the build, so an image can't ship with
  a collection whose Python needs it doesn't meet.
- **`consumers` job**: the same check against each consumer repo's `main`, so a raised floor shows up
  here before that collection's next Galaxy release does.

When it fails, the message names the file, the requirement and the pinned version. The usual fix
is a newer pin (add or bump in `python.in`, `tests/lock.sh`). If two collections' ranges can't both
be met, one of the collections has to change.

## How to…

**Add a Python package.** Add it to `requirements/python.in` with a comment (why, who), run
`tests/lock.sh` (needs Docker; resolves inside the base image), commit both files. For a package a
collection needs, the collection declares the floor in its `requirements.txt` and `python.in` names
the package (see above).

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

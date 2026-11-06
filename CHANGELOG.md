# Changelog

## 1.4.1 (unreleased)

### Fixed

- Debian security updates reach the image. Every build runs `apt-get upgrade` on the pinned base,
  and `build.yml` passes an `APT_REFRESH` build arg (the UTC date; the run id on scheduled and
  manual runs) so a cached layer can't keep old packages. 1.4.0 shipped `apt` 3.0.3
  (CVE-2026-109518, High; fixed in 3.0.4) because its apt layer came from a 2026-11-01 cache, and
  the weekly rebuild had never taken a Debian update.

### Changed

- The grype gate fails on fixable **High** and Critical findings (was Critical only). Accepted
  findings go in `.grype.yaml`, each with a reason (`tests/grype_ignores.py` checks).

## 1.4.0 (2026-11-06)

### Changed

- Molecule driver `molecule-git-cgallagher` + `git_cgallagher.molecule` v0.5.0 → v0.5.1 (`728a9fe`),
  in the same round as isc's `windows-dc` and windows' `domain-lab`. v0.5.1 changes only
  setup-molecule's QEMU install on the runner (`.deb`s from the actions cache, each checked against
  its SHA256; a crawling Ubuntu mirror dropped for the next one); the docker kind the image's
  scenarios use is unchanged.

## 1.3.0 (2026-11-02)

### Changed

- Molecule driver `molecule-git-cgallagher` + `git_cgallagher.molecule` v0.4.0 → v0.5.0 (`fe24140`),
  in the same round as isc's `windows-dc` and windows' `domain-lab`. v0.5.0's setup-molecule takes
  the KVM labs' collections out of this image (`collections-image`) instead of Galaxy, through
  `ansible_collections.__path__` (smoke-checked since PR #16); the docker kind is unchanged.

## 1.2.0 (2026-11-02)

### Changed

- Molecule driver `molecule-git-cgallagher` + `git_cgallagher.molecule` v0.3.2 → v0.4.0 (`ab9538d`),
  in the same round as isc's `windows-dc` and windows' `domain-lab`. v0.4.0 changes only the
  `windows_vm` kind and the `vm-screendump` action (QEMU under a supervisor, a dead or stopped VM
  fails the first-boot wait at once); the docker kind the image's scenarios use is unchanged.

## 1.1.0 (2026-11-02)

### Added

- `runtime` target: `git_cgallagher.vmware` 0.1.0, with its controller-side Python, pyvmomi
  9.1.1.0 (both targets; one lock). The `consumers` check covers ansible-collection-vmware too
  (coverage, Python requirements, yamllint + ansible-lint).

### Changed

- Molecule driver `molecule-git-cgallagher` + `git_cgallagher.molecule` v0.3.1 → v0.3.2 (`3cefe7f`),
  the version isc's `windows-dc` and windows' `domain-lab` moved to (a `quiet_vm` fix).
- `runtime` target: git_cgallagher.isc 2.2.2 → 2.2.3, git_cgallagher.windows 0.5.0 → 0.11.0
  (Renovate isn't installed yet, so these were behind Galaxy).

## 1.0.0 (2026-11-01)

Major by this repo's semver rule: a package is removed.

### Removed

- `molecule-plugins[docker]` and the `docker` Python SDK. Every Molecule scenario in the
  consumers (isc 9, windows 4, orchestration 1, aws 1) uses the `molecule-git-cgallagher`
  driver, which uses the docker CLI, and no consumer uses a `community.docker.docker_*` module.

### Changed

- Molecule driver `molecule-git-cgallagher` + `git_cgallagher.molecule` v0.2.1 → v0.3.1 (`d894cf0`),
  the version every consumer's setup-molecule uses after isc's `windows-dc` moves to it. 0.3.x
  changed only the Windows lab roles (`ad_forest` on `microsoft.ad.group`, new `quiet_vm`).

## 0.5.0 (2026-11-01)

### Added

- Shared dependency model ([docs/SHARED-DEPENDENCIES.md](docs/SHARED-DEPENDENCIES.md), issue #8): every
  version for the `git_cgallagher.*` repos' tooling is chosen in `requirements/`.
- Derived pin files in both images, `/usr/share/ansible-runtime/constraints.txt` (`python.txt` without
  hashes) and `collections.yml`, for runner jobs (`pip install -c`, `ansible-galaxy collection install -r`).
- Test tools consumers declare: moto[ssm,sts] 5.2.5, flask, flask-cors, pytest.

### Changed

- The `consumers` job's Python check also reads each consumer's `tests/unit/requirements.txt` and
  `tests/integration/requirements.txt`.

## 0.4.0 (2026-11-01)

### Added

- `runtime` target: `git_cgallagher.aws` 0.3.0, with its controller-side Python, boto3 and
  botocore 1.43.123 (in both targets; one lock).
- `ci` target: community.windows 3.3.0 (windows' IIS integration tests now declare it; the
  `consumers` check failed on `main` without it).
- `tests/collection_requirements.py`: checks that the pinned Python packages satisfy every
  collection's `requirements.txt`. It runs in the `runtime` build (a miss fails it), in `smoke.sh`
  and against each consumer's `main` in the `consumers` job.

### Changed

- python-dateutil 3.0.0 → 2.9.0.post0 (botocore needs `<3`); tzdata, which only dateutil 3 needed,
  is gone.
- CI: the `consumers` job also checks ansible-collection-aws (coverage, yamllint, ansible-lint),
  now that its Molecule job runs in this image. No image change.

## 0.3.0 (2026-11-01)

### Added

- Automatic releases: Renovate merges `git_cgallagher.*` collection bumps once every check passes,
  and `build.yml`'s new `release` job releases such a merge as the next patch version. Every
  release, by hand or automatic, gets a GitHub release listing the image's contents
  (`tests/contents.py`).

### Changed

- `runtime` target: git_cgallagher.isc 2.1.0 → 2.2.2, git_cgallagher.windows 0.4.0 → 0.5.0.
- `DEPENDENCIES.md` no longer keeps a version table; the release notes do.

## 0.2.1 (2026-11-01)

### Changed

- Molecule driver `molecule-git-cgallagher` + `git_cgallagher.molecule` 0.2.0 → 0.2.1 (the commit
  the consumers' `setup-molecule` uses; driver code unchanged, only the action's apt time limits).

## 0.2.0 (2026-11-01)

### Added

- `openssl`, for isc's Kea render test (`tests/kea_dhcp/run.sh` makes a throwaway CA).

### Changed

- `runtime` target: git_cgallagher.isc 1.6.2 → 2.1.0; git_cgallagher.windows 0.2.0 (git
  commit) → 0.4.0 from Galaxy.

## 0.1.0 (2026-11-01)

### Added

- Initial image: Python 3.13 (Debian trixie), ansible-core 2.21.5, ansible-lint, yamllint,
  Molecule + docker driver, pypsrp, kubernetes, docker SDK + CLI; collections ansible.windows,
  microsoft.ad, community.docker, community.general, kubernetes.core (`ci` target), plus
  git_cgallagher.isc 1.6.2, .orchestration 0.2.2 and .windows 0.2.0 (`runtime` target).
- Build pipeline: amd64 + arm64 native builds, smoke tests, consumer coverage/lint/Molecule
  checks, grype scan, multi-arch manifests on GHCR with build provenance.
- Renovate config for every pin (Dockerfile, pip-compile, ansible-galaxy, GitHub Actions).
- `bin/ar` local wrapper.
- The shared Molecule driver, `molecule-git-cgallagher` + `git_cgallagher.molecule` 0.2.0
  (`ci` target, one commit pin), which the consumers' scenarios now require.

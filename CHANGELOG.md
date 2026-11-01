# Changelog

## Unreleased

### Changed

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

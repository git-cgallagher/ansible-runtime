# Changelog

## Unreleased

### Added

- Initial image: Python 3.13 (Debian trixie), ansible-core 2.21.5, ansible-lint, yamllint,
  Molecule + docker driver, pypsrp, kubernetes, docker SDK + CLI; collections ansible.windows,
  microsoft.ad, community.docker, community.general, kubernetes.core (`ci` target), plus
  git_cgallagher.isc 1.6.2, .orchestration 0.2.2 and .windows 0.2.0 (`runtime` target).
- Build pipeline: amd64 + arm64 native builds, smoke tests, consumer coverage/lint/Molecule
  checks, grype scan, multi-arch manifests on GHCR with build provenance.
- Renovate config for every pin (Dockerfile, pip-compile, ansible-galaxy, GitHub Actions).
- `bin/ar` local wrapper.

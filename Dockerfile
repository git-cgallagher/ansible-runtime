# syntax=docker/dockerfile:1
# Ansible runtime image. Two targets from the same pinned toolchain:
#   ci      : ansible-core, linters, Molecule + the molecule-git-cgallagher driver, Python libs,
#             third-party collections.
#             Collection repos run their own CI in this one, so they test their checkout.
#   runtime : ci + the git_cgallagher.* collections, for running playbooks.
# Every version comes from requirements/; Renovate bumps the two FROM digests below. Debian
# packages aren't pinned (requirements/apt.txt): each build takes the current security updates.

# The docker CLI only (static binary): Molecule's docker driver and the community.docker
# docker connection shell out to it. The daemon is the host's, via /var/run/docker.sock.
FROM docker:29.9.2-cli@sha256:5e6baf67325a79f64ed3bed6863954d5e05d0f3d4e57cbdb14809346814bbfdb AS docker-cli

FROM python:3.13-slim-trixie@sha256:2d44738ebf4ce5f63b9d9ea871e9c7cfdc0426f7b0c97cac915fd88ded1d86bb AS base

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ANSIBLE_FORCE_COLOR=1 \
    PY_COLORS=1

# apt-get upgrade takes Debian's security updates on top of the pinned base digest. A cached layer
# would keep yesterday's packages, so build.yml passes APT_REFRESH (the UTC date, or the run id on
# scheduled and manual runs): a new value re-runs this layer and everything after it.
ARG APT_REFRESH=unset
COPY requirements/apt.txt /tmp/requirements/apt.txt
RUN echo "apt refresh: $APT_REFRESH" \
 && apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && grep -Ev '^[[:space:]]*(#|$)' /tmp/requirements/apt.txt \
      | xargs apt-get install -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/*

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

# --require-hashes: every package, transitive ones included, must match python.txt exactly.
COPY requirements/python.txt /tmp/requirements/python.txt
RUN pip install --require-hashes --no-deps -r /tmp/requirements/python.txt

# Collections go into Python's site-packages (ansible_collections/ under it), not
# ~/.ansible or /usr/share/ansible. ansible-core scans sys.path for collections
# (COLLECTIONS_SCAN_SYS_PATH, on by default) at the lowest precedence, so they stay
# visible when a repo's Molecule config replaces ANSIBLE_COLLECTIONS_PATH and when
# GitHub's container jobs override HOME, while a repo's own checkout still wins.
COPY requirements/collections.yml /tmp/requirements/collections.yml
RUN site=$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])') \
 && ansible-galaxy collection install --no-cache -r /tmp/requirements/collections.yml -p "$site" \
 && rm -rf /root/.ansible

# The molecule-git-cgallagher driver (pip) lives in the same repo as git_cgallagher.molecule,
# so it takes that collection's commit from collections.yml: one pin for both. A git install
# can't be hash-checked; the commit SHA is the pin. --no-deps: its only dependency (molecule)
# is already installed from python.txt.
RUN sha=$(python -c 'import yaml; print(next(c["version"] for c in yaml.safe_load(open("/tmp/requirements/collections.yml"))["collections"] if c["name"].endswith("/ansible-collection-molecule.git")))') \
 && pip install --no-deps "molecule-git-cgallagher @ git+https://github.com/git-cgallagher/ansible-collection-molecule.git@$sha"

# Derived pin files (/usr/share/ansible-runtime/): the same versions, readable by jobs that run on
# the runner rather than in the image (pip -c, ansible-galaxy -r). docs/SHARED-DEPENDENCIES.md.
COPY build/derive_pins.py /usr/local/share/ansible-runtime-build/derive_pins.py
RUN python /usr/local/share/ansible-runtime-build/derive_pins.py \
      /tmp/requirements/python.txt /tmp/requirements/collections.yml

WORKDIR /work
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]

FROM base AS ci
LABEL org.opencontainers.image.title="ansible-runtime (ci)" \
      org.opencontainers.image.description="Pinned ansible-core, ansible-lint, yamllint, Molecule and third-party collections for git_cgallagher.* CI" \
      org.opencontainers.image.source="https://github.com/git-cgallagher/ansible-runtime" \
      org.opencontainers.image.licenses="MIT"

FROM base AS runtime
COPY requirements/collections-runtime.yml /tmp/requirements/collections-runtime.yml
RUN site=$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])') \
 && ansible-galaxy collection install --no-cache -r /tmp/requirements/collections-runtime.yml -p "$site" \
 && rm -rf /root/.ansible
# Each collection declares its Python needs (requirements.txt); python.txt pins one version of
# each, shared by all of them. The build fails here if a pin doesn't satisfy every declaration,
# e.g. a collection release that raises its boto3 floor past the lock.
COPY tests/collection_requirements.py /tmp/collection_requirements.py
RUN python /tmp/collection_requirements.py && rm /tmp/collection_requirements.py
# The runtime target's pin files list its collections too.
RUN python /usr/local/share/ansible-runtime-build/derive_pins.py /tmp/requirements/python.txt \
      /tmp/requirements/collections.yml /tmp/requirements/collections-runtime.yml
LABEL org.opencontainers.image.title="ansible-runtime" \
      org.opencontainers.image.description="Pinned Ansible toolchain plus the git_cgallagher.* collections, for running playbooks locally and in CI" \
      org.opencontainers.image.source="https://github.com/git-cgallagher/ansible-runtime" \
      org.opencontainers.image.licenses="MIT"

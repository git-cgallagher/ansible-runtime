# syntax=docker/dockerfile:1
# Ansible runtime image. Two targets from the same pinned toolchain:
#   ci      : ansible-core, linters, Molecule, Python libs, third-party collections.
#             Collection repos run their own CI in this one, so they test their checkout.
#   runtime : ci + the git_cgallagher.* collections, for running playbooks.
# Every version comes from requirements/; Renovate bumps the two FROM digests below.

# The docker CLI only (static binary): Molecule's docker driver and the community.docker
# docker connection shell out to it. The daemon is the host's, via /var/run/docker.sock.
FROM docker:29.9.2-cli@sha256:5e6baf67325a79f64ed3bed6863954d5e05d0f3d4e57cbdb14809346814bbfdb AS docker-cli

FROM python:3.13-slim-trixie@sha256:2d44738ebf4ce5f63b9d9ea871e9c7cfdc0426f7b0c97cac915fd88ded1d86bb AS base

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ANSIBLE_FORCE_COLOR=1 \
    PY_COLORS=1

COPY requirements/apt.txt /tmp/requirements/apt.txt
RUN apt-get update \
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
LABEL org.opencontainers.image.title="ansible-runtime" \
      org.opencontainers.image.description="Pinned Ansible toolchain plus the git_cgallagher.* collections, for running playbooks locally and in CI" \
      org.opencontainers.image.source="https://github.com/git-cgallagher/ansible-runtime" \
      org.opencontainers.image.licenses="MIT"

#!/usr/bin/env bash
# Regenerates requirements/python.txt from requirements/python.in, inside the same Python
# the image uses (the Dockerfile's base image), so the lock resolves for Linux + Python 3.13.
# Renovate runs the equivalent pip-compile itself when it bumps a package; run this after
# editing python.in by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
base=$(sed -n 's/^FROM \(python:[^ ]*\) AS base$/\1/p' Dockerfile)
docker run --rm -v "$PWD":/src -w /src "$base" sh -c '
  pip install --quiet --timeout 60 --retries 5 pip-tools &&
  pip-compile --quiet --generate-hashes --allow-unsafe --strip-extras \
    --output-file=requirements/python.txt requirements/python.in'

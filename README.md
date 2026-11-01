# ansible-runtime

One pinned Ansible environment, used both locally and in GitHub Actions for the `git_cgallagher.*`
collections. It's a plain Dockerfile and a set of lockfiles. It does **not** use
ansible-builder / Execution Environments: there's no AWX or AAP here.

```
ghcr.io/git-cgallagher/ansible-runtime:<version>      # runtime: toolchain + git_cgallagher.* collections
ghcr.io/git-cgallagher/ansible-runtime:<version>-ci   # ci: toolchain + third-party collections only
```

Both are built for `linux/amd64` (GitHub runners) and `linux/arm64` (Apple Silicon), with build
provenance attestations. What's inside, and how each piece is kept current:
[DEPENDENCIES.md](DEPENDENCIES.md).

## Which image

- **`-ci`**: CI in the collection repos themselves (`ansible-collection-isc`, `-windows`, …).
  It has no `git_cgallagher.*` collections under test, so a repo always tests its own checkout
  and never a baked copy of its last release. The one exception is test tooling: the shared
  `molecule-git-cgallagher` driver and `git_cgallagher.molecule`, which every scenario names.
- **runtime** (no suffix): running playbooks, and CI in anything that *uses* the roles.

Tags: `X.Y.Z` (immutable, the pipeline refuses to overwrite one), `X.Y`, `latest`, `main`
(moves on every merge and weekly rebuild) and `sha-<commit>`, each with `-ci` for the ci
target. Pin `X.Y.Z` in CI.

A new release of `git_cgallagher.isc`, `.windows` or `.orchestration` on Galaxy reaches the
`runtime` image on its own: Renovate bumps the pin and merges once CI passes, and the pipeline
releases the next patch version. Each [release](https://github.com/git-cgallagher/ansible-runtime/releases)
lists the image's exact contents.

## Use it locally

`bin/ar` runs any command in the image in the current directory, with your ssh agent and the
host Docker socket (for Molecule):

```bash
ln -s ~/Code/ansible-runtime/bin/ar ~/.local/bin/ar
```

```bash
ar ansible-playbook -i inventory.yml site.yml
```

```bash
ANSIBLE_RUNTIME_IMAGE=ghcr.io/git-cgallagher/ansible-runtime:main-ci ar ansible-lint
```

## Use it in GitHub Actions

The collections run it through a small wrapper, `.github/ci/runtime.sh` (copy it from
`ansible-collection-isc`), with the image pinned by tag and digest:

```yaml
env:
  RUNTIME_IMAGE: ghcr.io/git-cgallagher/ansible-runtime:X.Y.Z-ci@sha256:<digest>
jobs:
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@<sha>  # vX.Y.Z
      - run: .github/ci/runtime.sh ansible-lint
```

The wrapper is `docker run --network host`, with the checkout mounted at the same path, the
runner's Docker socket, `TMPDIR` under the checkout and the checkout marked `safe.directory`.
Use it rather than a `container:` job. A `container:` job puts the checkout at `/__w` and the
controller on its own network, which breaks tests that bind-mount checkout files into containers
they start (isc's Kea render) or reach published ports on `127.0.0.1` (isc's Stork scenarios).
The collections live in Python's `site-packages`, so they're found even when a Molecule config
replaces `ANSIBLE_COLLECTIONS_PATH`.

Keep each collection's `ansible-test sanity` matrix (`ansible-community/ansible-test-gh-action`
across ansible-core versions) as it is. This image pins **one** ansible-core; that matrix
exists to test across many.

## Build and test locally

```bash
docker buildx build --load --target ci -t ansible-runtime:ci-local .
```

```bash
docker run --rm -v "$PWD":/src -w /src ansible-runtime:ci-local tests/smoke.sh ci
```

The CI pipeline is described in [AGENTS.md](AGENTS.md).

## License

MIT

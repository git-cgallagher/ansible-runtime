# Shared dependency model

**`ansible-runtime/requirements/` is the only place a version is chosen.** Every other repo either
runs inside the image or reads the image's pins as constraints. A collection's own files declare
*ranges* only, because that's the contract Galaxy users install against.

So for any dependency file in any `git_cgallagher.*` repo, ask: **does it choose a version?** If it
does, it goes away or becomes derived from the image.

Tracking issue: [ansible-runtime#8](https://github.com/git-cgallagher/ansible-runtime/issues/8) (linked from every PR in this plan).

## How the pins reach a job

One pin governs each consumer repo: `RUNTIME_IMAGE` (tag + digest) in its `ansible-test.yml`.

| Job runs… | Gets its versions from |
|---|---|
| inside the image (`.github/ci/runtime.sh …`) | the image itself |
| on the runner (KVM labs, release, matrices) | the image's derived pin files, read from that same `RUNTIME_IMAGE` |

The image carries two derived files, generated at build time and never edited by hand:

- `/usr/share/ansible-runtime/constraints.txt`: `python.txt` without hashes, for `pip install -c`.
  The hashed lock can't be used directly: pip treats hashes in a constraints file as
  `--require-hashes` mode and refuses any package the lock doesn't list (tested 2026-11-01).
- `/usr/share/ansible-runtime/collections.yml`: every collection pin of that target
  (`collections.yml`, plus `collections-runtime.yml` in the runtime target), for
  `ansible-galaxy collection install -r`.

A runner job reads them like this:

```bash
docker run --rm "$RUNTIME_IMAGE" cat /usr/share/ansible-runtime/constraints.txt > "$RUNNER_TEMP/constraints.txt"
pip install -c "$RUNNER_TEMP/constraints.txt" ansible-core molecule …
```

That costs one image pull. It's noise on a KVM lab and visible on a two-minute job, which is
why short jobs move *into* the image instead.

## What a collection repo keeps

- `galaxy.yml` `dependencies`, `requirements.yml`, `requirements.txt`: **ranges**, for Galaxy users.
- `tests/unit/requirements.txt`, `tests/integration/requirements.txt`: **ranges** (ansible-test reads
  them). The image pins a version of each.
- Nothing that picks an exact version. Today's exceptions are removed in Phase 2:
  isc `.github/ci/requirements.txt`, orchestration `extensions/molecule/requirements.txt`,
  molecule `.github/ci/constraints.txt`.

The `consumers` job checks every consumer's `main` against the image: collections
(`tests/coverage.py`) and Python, including the two test files above
(`tests/collection_requirements.py`). A consumer adding or raising a dependency fails it until the pin
lands here first.

## Deliberately not pinned by the image

1. **The ansible-test version matrices** (sanity / units / integration across ansible-core 2.18–2.21
   and several Pythons). They run in ansible-test's own containers, and a lock resolved for
   Python 3.13 doesn't necessarily install on 3.9. ansible-test does read
   `tests/unit/constraints.txt` and `tests/integration/constraints.txt` from a collection (checked in
   `ansible_test/_internal/python_requirements.py`), so Phase 4 evaluates feeding those from the
   image. Rule until then: pin everything except the dimension the matrix varies.
2. **isc `argument-specs`**: it loops over ansible-core minors, so it uses the constraints minus
   `ansible-core` **and `resolvelib`**. Only ansible-core uses resolvelib, and each minor allows a
   different range (2.18 needs `<1.1`; the image pins 1.2.1), so with the pin left in, 2.18 can't
   resolve (found 2026-11-01). Any job that varies ansible-core drops both:
   `grep -vE '^(ansible-core|resolvelib)=='`.
3. **`devel` canaries**: unpinned on purpose, because they exist to see upstream breakage early.
4. **`ansible-collection-molecule`'s own CI never runs in the image**, because it would test the
   baked copy of the driver instead of its checkout. It may still read the constraints file.
5. **Python on managed hosts** (the roles' bootstrap tasks): a target-side concern, out of scope
   (decided 2026-11-01).

## Phases

### Phase 1: ansible-runtime (0.5.0)

- `python.in` gains the test tools consumers declare: `moto[ssm,sts]`, `flask`, `flask-cors`, `pytest`
  (aws's `tests/unit` + `tests/integration`).
- The build derives `/usr/share/ansible-runtime/{constraints.txt,collections.yml}` in both targets.
  `smoke.sh` checks that every `==` in them is what's installed.
- `tests/collection_requirements.py` also reads `tests/unit/requirements.txt` and
  `tests/integration/requirements.txt` in the `consumers` job.
- Needs a hand-made `v0.5.0` tag (it changes more than version lines).

### Phase 2: consumers (one PR each, after 0.5.0 is tagged)

Merge one at a time on the Galaxy-publishing repos and wait for each release run.

| Repo | Into the image (`runtime.sh`) | On the runner, with `-c` constraints | Delete |
|---|---|---|---|
| aws, vmware | `lint` (`pip install ansible-core ansible-lint yamllint -r requirements.txt`), `build` | `release.yml` (`pip install "ansible-core>=2.18"`) | — |
| isc | — | `argument-specs` (minus ansible-core), `windows-dc` (setup-molecule `constraints`), `release.yml` | `.github/ci/requirements.txt` |
| windows | `argument-specs` (`pip install ansible-core`) | `domain-lab` (setup-molecule `constraints`; none today), `release.yml` | — |
| orchestration | — | `galaxy-publish.yml` (`ansible-core==2.21.5`, a second pin) | `extensions/molecule/requirements.txt` |
| molecule | — (must not run in the image) | `lint`, `molecule` and `windows-lab` (setup-molecule `constraints`) | `.github/ci/constraints.txt` |

Each PR also bumps `RUNTIME_IMAGE` to 0.5.0, so the image and the derived pins move together.
Opened 2026-11-01: aws PR 7, windows PR 45, isc PR 29, orchestration PR 19, molecule PR 17.

How each repo reads the pin: a runner job takes `RUNTIME_IMAGE` from `ansible-test.yml`
(`ci.yml` in molecule) with `sed -n 's/^ *RUNTIME_IMAGE: //p'`, so that one line stays the only
place it's set, including in `release.yml` and `argument-specs.yml`, which are separate workflows.

vmware joined the same way on 2026-11-02 (vmware PR 2, on `1.1.0-ci`), after image 1.1.0 pinned
pyvmomi and put it in the `consumers` check.

### Phase 2b: one driver, and collection pins in the labs (done 2026-11-02)

- **One Molecule driver everywhere.** The image's `collections.yml` commit and every consumer's
  setup-molecule / vm-screendump `uses:` line move in the same round: v0.3.1 (1.0.0, isc PR 30),
  v0.3.2 (1.1.0), v0.4.0 (`ab9538d`, 1.2.0, isc PR 32; windows by the molecule session). Whoever cuts
  a driver release tells this repo's maintainer in that round.
- **The Windows labs install the image's collection pins.** isc `windows-dc` (isc PR 32) and windows
  `domain-lab` (windows PR 53) read `/usr/share/ansible-runtime/collections.yml` from the image and
  pass it as setup-molecule's `requirements:`, **minus `git_cgallagher.molecule`**: the action
  installs that one from its own pinned commit, which may be newer than the image's during a driver
  round. The filter runs in the image's Python (`docker run … python -c`), so the runner needs no
  PyYAML. Molecule's own `dependency` step still names the repo's ranges and skips them, since the
  pinned versions already satisfy them.
- **Still on ranges, on purpose:** molecule's own CI, which tests its checkout of
  `git_cgallagher.molecule` and must not have it replaced.
- Image 1.0.0 also dropped `molecule-plugins[docker]` and the docker SDK: every scenario uses
  `molecule-git-cgallagher`, which uses the docker CLI.

### Phase 3: `RUNTIME_IMAGE` bumps without a human

**Built 2026-11-06, waiting on a token.** This repo's `build.yml` opens the bump PRs itself: after
every release (a tag, a collection bump, a daily security rebuild), its `bump-consumers` job runs
`.github/ci/bump-consumer.sh` for each consumer. A Renovate regex manager in each consumer was the
other option; it was set aside because it needs Renovate installed in six more repos, and the
consumers use Dependabot, which can't update an `env:` value. The PRs need a token beyond
`GITHUB_TOKEN`, which can't push to another repo and whose PRs start no CI: Chris sets
`CONSUMER_BUMP_TOKEN` in the `consumer-bumps` environment (AGENTS.md TODO). The PRs still merge by
hand, under each repo's merge rules.

### Phase 4: ansible-test constraints (evaluate)

Whether a constraints file derived from the 3.13 lock installs across the ansible-test matrix's
Pythons. If it does, generate each consumer's `tests/{unit,integration}/constraints.txt` from the
image. If not, record why and leave the matrix on ranges.

## Adding or bumping a dependency, under this model

1. The collection declares or widens a **range** (its `requirements.txt`, `requirements.yml`,
   `galaxy.yml`, or `tests/*/requirements.txt`).
2. This repo pins a version that satisfies it (`python.in` + `tests/lock.sh`, or the collection
   files). Land this **first**: until it does, the `consumers` job fails on `main`, which is the alarm.
3. Release the image; consumers move `RUNTIME_IMAGE`.

Two collections needing the same package always get the same version. If their ranges can't both
be met, the check names both, and one of the collections changes.

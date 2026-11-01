#!/usr/bin/env bash
# Runs INSIDE the image and proves it contains exactly what requirements/ pins.
#   docker run --rm -v "$PWD":/src -w /src <image> tests/smoke.sh ci|runtime
set -euo pipefail
target=${1:?usage: smoke.sh ci|runtime}
fail() { echo "::error::$*"; exit 1; }

echo "== ansible-core matches python.txt"
want=$(sed -n 's/^ansible-core==\([^ ]*\).*/\1/p' requirements/python.txt)
have=$(python -c 'from ansible.release import __version__; print(__version__)')
[ "$want" = "$have" ] || fail "ansible-core is $have, python.txt pins $want"
echo "ansible-core $have"

echo "== every python.txt pin is what pip installed"
python - <<'PY'
import re, sys
from importlib.metadata import version
bad = []
for line in open("requirements/python.txt"):
    m = re.match(r"^([A-Za-z0-9_.-]+)==([^ \\]+)", line)
    if m and version(m[1]) != m[2]:
        bad.append(f"{m[1]}: installed {version(m[1])}, pinned {m[2]}")
sys.exit("\n".join(bad) if bad else 0)
PY

echo "== installed collections equal the pins"
python - "$target" <<'PY'
import json, subprocess, sys, yaml
files = ["requirements/collections.yml"]
if sys.argv[1] == "runtime":
    files.append("requirements/collections-runtime.yml")
want = {}
for f in files:
    for c in yaml.safe_load(open(f))["collections"]:
        if c.get("type") == "git":
            # Name comes from the repo's galaxy.yml; the version isn't knowable here.
            name = c["name"].rstrip("/").removesuffix(".git").rsplit("/", 1)[1]
            name = "git_cgallagher." + name.removeprefix("ansible-collection-")
            want[name] = None
        else:
            want[c["name"]] = str(c["version"])
out = json.loads(subprocess.check_output(["ansible-galaxy", "collection", "list", "--format", "json"], stderr=subprocess.DEVNULL))
# ansible._* are ansible-core's own internal collections, versioned with core.
have = {n: d["version"] for path in out.values() for n, d in path.items() if not n.startswith("ansible._")}
errors = [f"{n}: want {v}, have {have.get(n)}" for n, v in want.items()
          if n not in have or (v is not None and have[n] != v)]
extra = sorted(set(have) - set(want))
if extra:
    errors.append(f"unpinned collections installed: {extra}")
for n in sorted(have):
    print(f"{n} {have[n]}")
sys.exit("\n".join(errors) if errors else 0)
PY

echo "== collections are found even when ANSIBLE_COLLECTIONS_PATH and HOME are overridden"
ANSIBLE_COLLECTIONS_PATH=/nonexistent HOME=/tmp \
  ansible-doc -t module community.docker.docker_container >/dev/null \
  || fail "collections in site-packages are not on the search path"

echo "== Python libraries the collections need"
python -c 'import pypsrp, kubernetes, docker, yaml, jinja2, boto3, botocore; print("ok")'
if [ "$target" = runtime ]; then
  echo "== python.txt satisfies every collection's requirements.txt"
  python tests/collection_requirements.py
fi

echo "== tools"
ansible-lint --version | head -1
yamllint --version
molecule --version | head -1
drivers=$(molecule drivers 2>&1); grep -qw docker <<<"$drivers" || fail "molecule has no docker driver"
grep -q molecule-git-cgallagher <<<"$drivers" || fail "molecule has no molecule-git-cgallagher driver"
want=$(python -c 'import yaml; print(next(c["version"] for c in yaml.safe_load(open("requirements/collections.yml"))["collections"] if c["name"].endswith("/ansible-collection-molecule.git")))')
have=$(python -c 'import json; from importlib.metadata import distribution as d; print(json.loads(d("molecule-git-cgallagher").read_text("direct_url.json"))["vcs_info"]["commit_id"])')
[ "$want" = "$have" ] || fail "molecule-git-cgallagher is at $have, collections.yml pins $want"
docker --version
git --version
openssl version
ssh -V

echo "== playbooks that use each collection parse"
playbooks=(tests/playbooks/ci.yml)
[ "$target" = runtime ] && playbooks+=(tests/playbooks/runtime.yml)
for p in "${playbooks[@]}"; do
  ansible-playbook -i localhost, --syntax-check "$p"
done
if [ "$target" = runtime ]; then
  ansible-doc -t strategy git_cgallagher.orchestration.time_offset >/dev/null \
    || fail "time_offset strategy plugin does not load"
  ansible-doc -t lookup git_cgallagher.aws.ssm_parameter >/dev/null \
    || fail "aws ssm_parameter lookup does not load"
fi
echo "smoke ($target): OK"

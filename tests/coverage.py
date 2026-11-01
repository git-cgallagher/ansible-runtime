"""Fail if a consumer repo needs a collection the image doesn't pin, or a pin is out of its range.

Runs inside the image (it uses ansible-core's own version matcher):
    python tests/coverage.py consumers/ansible-collection-isc consumers/...

For each consumer checkout it reads galaxy.yml `dependencies` and every requirements*.yml
(Molecule and lab ones included, since their CI runs in this image too). A requirement on
one of the git_cgallagher.* collections themselves is skipped: collection CI uses the `ci`
target and tests its own checkout.
"""
import pathlib
import sys

import yaml
from ansible.galaxy.dependency_resolution.versioning import meets_requirements

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", ".ansible", ".molecule-collections", "collections", "node_modules"}


def pins():
    out = {}
    for name in ("collections.yml", "collections-runtime.yml"):
        for c in yaml.safe_load((ROOT / "requirements" / name).read_text())["collections"]:
            if c.get("type") != "git":
                out[c["name"]] = str(c["version"])
    return out


def requirements(repo):
    """Yield (file, collection, range) for everything a consumer repo declares."""
    galaxy = repo / "galaxy.yml"
    if galaxy.exists():
        for name, spec in (yaml.safe_load(galaxy.read_text()).get("dependencies") or {}).items():
            yield galaxy, name, str(spec)
    for f in sorted(repo.rglob("requirements*.yml")):
        if SKIP_DIRS.intersection(f.relative_to(repo).parts):
            continue
        data = yaml.safe_load(f.read_text()) or {}
        for c in data.get("collections", []) if isinstance(data, dict) else []:
            if isinstance(c, str):
                c = {"name": c}
            if c.get("type") in ("git", "url", "file", "dir"):
                continue
            yield f, c["name"], str(c.get("version", "*"))


def main(repos):
    pinned = pins()
    errors, checked = [], 0
    for repo in map(pathlib.Path, repos):
        for f, name, spec in requirements(repo):
            if name.startswith("git_cgallagher."):
                continue
            checked += 1
            where = f"{repo.name}/{f.relative_to(repo)}"
            if name not in pinned:
                errors.append(f"{where}: needs {name} {spec}, which the image does not pin")
            elif not meets_requirements(pinned[name], spec):
                errors.append(f"{where}: needs {name} {spec}, image pins {pinned[name]}")
            else:
                print(f"ok  {where}: {name} {spec} (pinned {pinned[name]})")
    for e in errors:
        print(f"::error::{e}")
    print(f"{checked} requirement(s) checked across {len(repos)} repo(s), {len(errors)} problem(s)")
    return 1 if errors or not checked else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1:]))

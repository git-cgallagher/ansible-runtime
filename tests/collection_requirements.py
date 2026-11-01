"""Fail if the image's Python packages don't satisfy what each collection declares.

A collection declares its Python needs (usually floors, like boto3>=1.28.0) in requirements.txt,
or in the file meta/execution-environment.yml names. The image pins ONE version of each package
in python.txt, shared by every collection, so this checks the pin against every declaration and
reports every unmet line, including two collections whose ranges can't both be met.

    python tests/collection_requirements.py            # installed git_cgallagher.* collections
    python tests/collection_requirements.py DIR [...]  # collection checkouts (the consumers job)

For a checkout it also reads tests/unit/requirements.txt and tests/integration/requirements.txt
(ansible-test's files, not shipped to Galaxy): the image pins those test tools too.
"""
import pathlib
import sys
import sysconfig
from importlib.metadata import PackageNotFoundError, version

import yaml
from packaging.requirements import InvalidRequirement, Requirement


TEST_FILES = ("tests/unit/requirements.txt", "tests/integration/requirements.txt")


def declared_file(root):
    ee = root / "meta" / "execution-environment.yml"
    if ee.is_file():
        python = ((yaml.safe_load(ee.read_text()) or {}).get("dependencies") or {}).get("python")
        if isinstance(python, str):
            return root / python
        # A list of requirement strings isn't used by any of ours; refuse rather than guess.
        if python is not None:
            sys.exit(f"{ee}: dependencies.python must name a file")
    return root / "requirements.txt"


def main(roots, checkouts):
    errors, checked = [], 0
    for root in roots:
        paths = [declared_file(root)]
        if checkouts:
            paths += [root / t for t in TEST_FILES]
        for path in paths:
            if path.is_file():
                checked += check(root, path, errors)
    print(f"{checked} requirement(s) checked across {len(roots)} collection(s)")
    sys.exit("\n".join(errors) if errors else 0)


def check(root, path, errors):
    checked = 0
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        try:
            req = Requirement(line)
        except InvalidRequirement as e:
            errors.append(f"{path}: {line!r}: {e}")
            continue
        if req.marker and not req.marker.evaluate():
            continue
        checked += 1
        try:
            have = version(req.name)
        except PackageNotFoundError:
            errors.append(f"{path}: {req} -> not installed; add it to requirements/python.in")
            continue
        if not req.specifier.contains(have, prereleases=True):
            errors.append(f"{path}: {req} -> image has {req.name} {have}, which python.txt pins; change the pin or the collection")
        else:
            print(f"ok  {root.name}/{path.relative_to(root)}: {req} (image: {have})")
    return checked


if __name__ == "__main__":
    if sys.argv[1:]:
        main([pathlib.Path(a) for a in sys.argv[1:]], checkouts=True)
    else:
        site = pathlib.Path(sysconfig.get_paths()["purelib"]) / "ansible_collections" / "git_cgallagher"
        main(sorted(p for p in site.iterdir() if p.is_dir()), checkouts=False)

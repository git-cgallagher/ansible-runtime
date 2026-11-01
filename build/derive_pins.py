"""Write the image's derived pin files into /usr/share/ansible-runtime/ (run during the build).

    python derive_pins.py PYTHON_TXT COLLECTIONS_YML [COLLECTIONS_YML ...]

constraints.txt  python.txt without hashes, for `pip install -c` on runner jobs. The hashed lock
                 can't be a constraints file: pip then demands a hash for every package installed,
                 including ones the lock doesn't list.
collections.yml  every collection pin of this target, for `ansible-galaxy collection install -r`.

Both are derived, never edited: requirements/ in git-cgallagher/ansible-runtime is the source.
See docs/SHARED-DEPENDENCIES.md.
"""
import pathlib
import re
import sys

import yaml

OUT = pathlib.Path("/usr/share/ansible-runtime")
HEADER = ("# Generated from git-cgallagher/ansible-runtime requirements/ when this image was built.\n"
          "# Do not edit; see docs/SHARED-DEPENDENCIES.md in that repo.\n")


def constraints(python_txt):
    pins = []
    for line in pathlib.Path(python_txt).read_text().splitlines():
        # "name==1.2.3 \" or "name==1.2.3 ; marker \"; hash lines start with whitespace.
        m = re.match(r"^([A-Za-z0-9_.-]+==[^\s\\]+(?:\s*;[^\\]+)?)", line)
        if m:
            pins.append(m[1].strip())
    if not pins:
        sys.exit(f"{python_txt}: no pins found")
    return HEADER + "\n".join(pins) + "\n"


def collections(files):
    merged = []
    for f in files:
        merged += yaml.safe_load(pathlib.Path(f).read_text())["collections"]
    return HEADER + yaml.safe_dump({"collections": merged}, sort_keys=False)


def main(python_txt, *collection_files):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "constraints.txt").write_text(constraints(python_txt))
    (OUT / "collections.yml").write_text(collections(collection_files))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])

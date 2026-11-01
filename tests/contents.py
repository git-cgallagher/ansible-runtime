"""Print what an image actually contains, as a Markdown table: the release notes.

Runs INSIDE the image, so it reports installed versions, not what the files say:
    docker run --rm -v "$PWD":/src -w /src <runtime image> python tests/contents.py
Python packages are the ones python.in names (their dependencies are in python.txt).
"""
import json
import pathlib
import platform
import re
import subprocess
from importlib.metadata import distribution, version

ROOT = pathlib.Path(__file__).resolve().parent.parent

rows = [("Python", platform.python_version())]
for line in (ROOT / "requirements" / "python.in").read_text().splitlines():
    m = re.match(r"^([A-Za-z0-9_.-]+)", line.strip())
    if m:
        rows.append((m[1], version(m[1])))

direct = json.loads(distribution("molecule-git-cgallagher").read_text("direct_url.json"))
rows.append(("molecule-git-cgallagher", f"{version('molecule-git-cgallagher')} "
             f"(commit `{direct['vcs_info']['commit_id'][:7]}`)"))
docker = subprocess.run(["docker", "--version"], capture_output=True, text=True, check=True).stdout
rows.append(("docker CLI", docker.split()[2].rstrip(",")))

out = json.loads(subprocess.check_output(
    ["ansible-galaxy", "collection", "list", "--format", "json"], stderr=subprocess.DEVNULL))
collections = {n: d["version"] for path in out.values() for n, d in path.items()
               if not n.startswith("ansible._")}
ours = sorted(n for n in collections if n.startswith("git_cgallagher."))
for n in sorted(collections, key=lambda n: (n in ours, n)):
    note = "" if n not in ours or n == "git_cgallagher.molecule" else " (runtime image only)"
    rows.append((n, collections[n] + note))

print("| Component | Version |\n|---|---|")
for name, ver in rows:
    print(f"| {name} | {ver} |")

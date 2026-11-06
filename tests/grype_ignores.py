"""Every accepted finding in .grype.yaml names a vulnerability and gives a reason.

Runs in the image (it has PyYAML): python tests/grype_ignores.py [path]
"""
import sys

import yaml

path = sys.argv[1] if len(sys.argv) > 1 else ".grype.yaml"
rules = (yaml.safe_load(open(path)) or {}).get("ignore") or []
bad = [f"entry {i}: {r}" for i, r in enumerate(rules)
       if not isinstance(r, dict) or not r.get("vulnerability") or not str(r.get("reason", "")).strip()]
if bad:
    sys.exit(f"{path}: every ignore entry needs `vulnerability` and a `reason`:\n" + "\n".join(bad))
print(f"{path}: {len(rules)} accepted finding(s)")

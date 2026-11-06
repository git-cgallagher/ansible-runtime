#!/usr/bin/env bash
# Opens a PR in one consumer repo moving its RUNTIME_IMAGE to a new -ci image. Run by build.yml's
# bump-consumers job after each release:
#   bump-consumer.sh <owner/repo> <workflow file> <version> <image ref with digest>
# Needs GH_TOKEN with contents, pull requests and workflows (read and write) on the repo.
set -euo pipefail
repo=$1 file=$2 version=$3 ref=$4
branch="ci/ansible-runtime-$version"
dir=$(mktemp -d)
git clone --quiet --depth 1 "https://x-access-token:$GH_TOKEN@github.com/$repo" "$dir"
cd "$dir"
if git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
  echo "$branch already exists"; exit 0
fi
old=$(sed -n 's/^ *RUNTIME_IMAGE: //p' "$file")
[ -n "$old" ] || { echo "::error::no RUNTIME_IMAGE in $repo $file"; exit 1; }
[ "$old" != "$ref" ] || { echo "already on $version-ci"; exit 0; }
from=${old%%@*}; from=${from##*:}
sed -i "s|^\( *RUNTIME_IMAGE: \).*|\1$ref|" "$file"
git checkout --quiet -b "$branch"
git commit --quiet -am "CI: ansible-runtime $version-ci" \
  -m "RUNTIME_IMAGE $from -> $version-ci (opened by ansible-runtime's build workflow)."
git push --quiet origin "$branch"
digest=${ref##*@}
gh pr create -R "$repo" --head "$branch" --title "CI: ansible-runtime $version-ci" --body-file - <<BODY
\`RUNTIME_IMAGE\` → **ansible-runtime $version-ci** (\`$version-ci@${digest:0:19}…\`), from \`$from\`.

What changed: https://github.com/git-cgallagher/ansible-runtime/releases/tag/v$version

CI-only, so there's no version bump and no release. Opened by ansible-runtime's \`build\` workflow (${GITHUB_SERVER_URL:-https://github.com}/git-cgallagher/ansible-runtime/actions/runs/${GITHUB_RUN_ID:-local}); merge it by hand once every check is green.
BODY

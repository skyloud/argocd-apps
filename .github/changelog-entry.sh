#!/usr/bin/env bash
# Usage: changelog-entry.sh <chart dir> <tag> [<prev tag>]
# Prints the CHANGELOG.md entry of <tag>: commits since <prev tag> grouped by git-cliff, then the diff.
set -euo pipefail

dir=$1 tag=$2 prev=${3:-}
name=$(yq .name "$dir/Chart.yaml")
max_diff=60000 # GitHub rejects a release body over 125000 characters

# explicit range: --include-path drops tags on commits that don't touch the chart
git cliff -c cliff.toml --include-path "$dir/**" --tag-pattern "^$name-[v0-9]" \
  --tag "$tag" ${prev:+"$prev..HEAD"}
echo

if [ -z "$prev" ]; then
  echo "Initial release, no previous version to diff against."
  exit 0
fi

compare="https://github.com/skyloud/argocd-apps/compare/$prev...$tag"
echo "[Compare $prev...$tag]($compare)"
echo
diff=$(git diff "$prev" HEAD -- "$dir" ":!$dir/CHANGELOG.md")
[ -n "$diff" ] || exit 0
echo "<details><summary>git diff $prev..$tag</summary>"
echo
echo '```diff'
if [ ${#diff} -gt $max_diff ]; then
  printf '%s\n' "${diff:0:$max_diff}"
  echo '```'
  echo
  echo "Diff truncated, see the compare link."
else
  printf '%s\n' "$diff"
  echo '```'
fi
echo
echo "</details>"

#!/bin/sh
# List the apps there could be in a Unum: the repos of the unum-apps org and the tags each one can be pinned to.
# Pick one with make add. Usage: scripts/catalog.sh
set -e

gh repo list unum-apps --no-archived --limit 100 --json name --jq '.[].name' | sort | while read -r app; do
    tags=$(gh api "repos/unum-apps/$app/tags" --paginate --jq '.[].name' | sort -V | tr '\n' ' ')
    printf '%-16s %s\n' "$app" "${tags:-(no tags)}"
done

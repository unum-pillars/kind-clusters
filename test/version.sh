#!/bin/sh
# Prove the repo has a version: VERSION is x.y.z, and the top section of CHANGELOG.md is that version. Usage: test/version.sh
set -e

test -f VERSION || { echo "VERSION is missing"; exit 1; }
test -f CHANGELOG.md || { echo "CHANGELOG.md is missing"; exit 1; }

version=$(cat VERSION)
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "VERSION is $version, not x.y.z"; exit 1; }

top=$(grep -m1 '^## ' CHANGELOG.md | sed 's/^## //')
test "$top" = "$version" || { echo "CHANGELOG.md starts at $top, not $version"; exit 1; }

echo "version $version"

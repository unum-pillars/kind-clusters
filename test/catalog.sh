#!/bin/sh
# Prove scripts/catalog.sh lists the unum-apps repos with their tags, from GitHub. Needs the network and gh.
# Usage: test/catalog.sh
set -e

LIST=$(scripts/catalog.sh)

echo "$LIST" | grep -Eq '^unifist-unum +.*\b0\.1\.0\b' || { echo "unifist-unum with tag 0.1.0 is not in the catalog:"; echo "$LIST"; exit 1; }
echo "$LIST" | grep -Eq '^cumulus ' || { echo "cumulus is not in the catalog:"; echo "$LIST"; exit 1; }
echo "$LIST"
echo "ok"

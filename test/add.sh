#!/bin/sh
# Prove scripts/add.sh writes an apps.yaml: a new app is appended, a known app has its source replaced in place, the
# others and the header comment are left alone. Offline. Usage: test/add.sh
set -e

FILE=$(mktemp)
EXPECTED=$(mktemp)
trap 'rm -f "$FILE" "$EXPECTED"' EXIT

check() {
    diff "$EXPECTED" "$FILE" || { echo "apps.yaml is not what $1 should leave"; exit 1; }
    echo "$1"
}

cat > "$FILE" <<'YAML'
# The apps a Unum runs.
unifist-unum:
  tag: 0.1.0
YAML

scripts/add.sh "$FILE" ledger tag 0.1.5
cat > "$EXPECTED" <<'YAML'
# The apps a Unum runs.
unifist-unum:
  tag: 0.1.0
ledger:
  tag: 0.1.5
YAML
check "a new app is appended"

scripts/add.sh "$FILE" unifist-unum hash 414f9ac
cat > "$EXPECTED" <<'YAML'
# The apps a Unum runs.
unifist-unum:
  hash: 414f9ac
ledger:
  tag: 0.1.5
YAML
check "a tag becomes a hash in place"

scripts/add.sh "$FILE" ledger checkout ../../unum-apps/ledger
cat > "$EXPECTED" <<'YAML'
# The apps a Unum runs.
unifist-unum:
  hash: 414f9ac
ledger:
  checkout: ../../unum-apps/ledger
YAML
check "a hash or tag becomes a checkout in place"

scripts/add.sh "$FILE" ledger tag 0.1.5
scripts/add.sh "$FILE" unifist-unum tag 0.1.0
cat > "$EXPECTED" <<'YAML'
# The apps a Unum runs.
unifist-unum:
  tag: 0.1.0
ledger:
  tag: 0.1.5
YAML
check "both are back to tags"

if scripts/add.sh "$FILE" ledger branch main 2>/dev/null; then
    echo "a source that is not tag, hash or checkout was accepted"
    exit 1
fi
check "an unknown source is refused and the file is untouched"

echo "ok"

#!/bin/sh
# Put an app in a Unum's apps.yaml, or change where it comes from: its source is a tag, a hash or a checkout.
# Usage: scripts/add.sh <apps.yaml> <app> <tag|hash|checkout> <value>
set -e

FILE=$1
APP=$2
SOURCE=$3
VALUE=$4

case $SOURCE in
tag | hash | checkout) ;;
*)
    echo "the source is tag, hash or checkout, not '$SOURCE'"
    exit 1
    ;;
esac

TMP=$(mktemp)

# The app's old lines are dropped as its new ones go in the same place, or at the end when it's new.
awk -v app="$APP" -v source="$SOURCE" -v value="$VALUE" '
/^[^ #]/ && $1 == app ":" { print app ":"; print "  " source ": " value; found = 1; skip = 1; next }
skip && /^  / { next }
{ skip = 0; print }
END { if (!found) { print app ":"; print "  " source ": " value } }
' "$FILE" > "$TMP"

cat "$TMP" > "$FILE"
rm -f "$TMP"

#!/bin/sh
# Prove an app can move between sources without losing its data: the Unum up on what its apps.yaml says, then the app
# taken down, its line changed to a hash, then to a checkout, then back to its tag, each brought up and tested, the
# data in MySQL (a marker database made first) still there. Slow, it builds and starts the app several times. apps.yaml is put back after.
# Usage: test/swap.sh <cluster> <app> <hash> <checkout>, e.g. test/swap.sh us unifist-unum 414f9ac ../../unum-apps/unifist-unum
set -e

NAME=$1
APP=$2
HASH=$3
CHECKOUT=$4
CTX=kind-$NAME
APPS=$NAME/apps.yaml

SAVED=$(mktemp)
cp "$APPS" "$SAVED"
trap 'cp "$SAVED" "$APPS"; rm -f "$SAVED"; mysql_run "DROP DATABASE IF EXISTS swap_marker" || true' EXIT

mysql_run() {
    kubectl --context "$CTX" -n mysql exec deployment/mysql -- env MYSQL_PWD=root mysql -uroot -N -e "$1"
}

TAG=$(awk -v app="$APP:" '$1 == app {found = 1} found && /^  tag:/ {print $2; exit}' "$APPS")
test -n "$TAG" || { echo "$APP has to be at a tag in $APPS to start"; exit 1; }

# Take the app down, change its line, bring everything up again, prove it.
swap() {
    echo "==== $APP: $1 $2"
    kubectl --context "$CTX" delete namespace "$APP" --wait=true
    scripts/add.sh "$APPS" "$APP" "$1" "$2"
    make ci NAME="$NAME"
    make test NAME="$NAME"
    mysql_run "SHOW DATABASES" | grep -qx swap_marker || { echo "the data did not survive taking $APP down"; exit 1; }
}

make ci NAME="$NAME"
make test NAME="$NAME"
mysql_run "CREATE DATABASE swap_marker"

swap hash "$HASH"
swap checkout "$CHECKOUT"
swap tag "$TAG"

echo "ok"

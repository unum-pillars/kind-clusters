#!/bin/sh
# Prove nothing here switches the kubectl context: make up and make ci name their cluster in the call (tilt --context), and no
# file asks for use-context, so two Unums can come up at once without one deploying into the other. Usage: test/context.sh
set -e

for target in up ci; do
    plan=$(make -n "$target" NAME=us)

    echo "$plan" | grep -q 'use-context' && { echo "make $target switches the kubectl context"; exit 1; }
    echo "$plan" | grep -Eq 'tilt (up|ci) .*--context kind-us' || { echo "make $target does not give tilt --context kind-us"; exit 1; }

    echo "make $target names its cluster"
done

found=$(grep -rIl "use-context" --exclude-dir=.git --exclude-dir=data --exclude=CHANGELOG.md --exclude=context.sh . || true)
test -z "$found" || { echo "use-context is still in: $found"; exit 1; }

echo "no use-context"

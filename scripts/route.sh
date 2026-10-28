#!/bin/sh
# Route a Unum's names from the ingress cluster, the one holding the host's ports 80 and 443, to the Unum's node. Without
# an ingress cluster there is nothing to route and the Unum is reached by its host ports. Safe to run again.
# Usage: scripts/route.sh <cluster>
set -e

NAME=$1

if ! kind get clusters | grep -qx ingress; then
    echo "no ingress cluster (see gaf3/kind-ingress): $NAME is reached by its host port only"
    exit 0
fi

sed "s/__NAME__/$NAME/g" route/route.yaml | kubectl --context kind-ingress apply -f -

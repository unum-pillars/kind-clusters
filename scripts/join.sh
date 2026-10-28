#!/bin/sh
# Join two Unums: a Route row in each one's unum.route for the other, holder the other, owner of everything it made, at
# its cumulus api by name and no port. It goes through unifist-unum's REST, from a pod in the Unum, so it's the app that
# writes it. Safe to run again: a Unum that already has the row is left alone. Usage: scripts/join.sh <a> <b>, with both up.
set -e

A=$1
B=$2

test -n "$A" -a -n "$B" || { echo "usage: scripts/join.sh <a> <b>"; exit 1; }

# join <cluster> <other>: the row in cluster that makes other a member
join() {
    kubectl --context "kind-$1" run "join-$2" --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- sh -c "
        if curl -s -m 10 'http://api.unifist-unum/model/route?holder=$2' | grep -q '\"holder\": \"$2\"'; then
            echo '$1 already has $2'
        else
            curl -s -m 10 -X POST http://api.unifist-unum/model/route -H 'Content-Type: application/json' \
                -d '{\"route\": {\"unum\": \"$2\", \"role\": \"owner\", \"holder\": \"$2\", \"url\": \"http://api.cumulus.$2.localhost\"}}' |
                grep -q '\"holder\": \"$2\"' && echo '$1 joined $2'
        fi" 2>/dev/null
}

join "$A" "$B"
join "$B" "$A"

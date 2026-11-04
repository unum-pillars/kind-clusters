#!/bin/sh
# Join two Unums: a Route row in each one's unum.route for the other, holder the other, owner of everything it made, at its cumulus
# api by name and no port, on https. The Unums accept each other's client certificates (scripts/accept.sh) and each puts the other's
# root in cumulus's secret unum-roots, which the api verifies it with, so a call between them is mutual TLS. It goes through
# unifist-unum's REST, from a pod in the Unum, so it's the app that writes the rows. Safe to run again: a Unum that already has the
# row is left alone, and one that has it on http gets it on https. It waits until the api pods have the client certificate and the roots,
# which the kubelet brings in about a minute after they change. Usage: scripts/join.sh <a> <b>, with both up.
set -e

A=$1
B=$2

test -n "$A" -a -n "$B" || { echo "usage: scripts/join.sh <a> <b>"; exit 1; }

# join <cluster> <other>: the row in cluster that makes other a member
join() {
    # the script is single quoted on purpose: the pod expands it, from the --env values
    # shellcheck disable=SC2016
    kubectl --context "kind-$1" run "join-$2" --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
        --env "CLUSTER=$1" --env "OTHER=$2" --command -- sh -c '
        # kubectl attaches after the pod starts and loses the output of a pod that has already finished
        sleep 2
        url="https://api.cumulus.$OTHER.localhost"
        rows=$(curl -s -m 10 "http://api.unifist-unum/model/route?holder=$OTHER")
        if echo "$rows" | grep -q "\"url\": \"$url\""; then
            echo "$CLUSTER already has $OTHER"
        else
            for id in $(echo "$rows" | grep -o "\"id\": [0-9]*" | grep -o "[0-9]*"); do
                curl -s -m 10 -X DELETE "http://api.unifist-unum/model/route/$id" > /dev/null
            done
            curl -s -m 10 -X POST http://api.unifist-unum/model/route -H "Content-Type: application/json" \
                -d "{\"route\": {\"home\": \"$OTHER\", \"role\": \"owner\", \"holder\": \"$OTHER\", \"url\": \"$url\"}}" |
                grep -q "\"holder\": \"$OTHER\"" && echo "$CLUSTER joined $OTHER"
        fi' 2> /dev/null
}

# mounted <cluster>: whether the api pod of cumulus has the client certificate and every root the secret holds
mounted() {
    want=$(kubectl --context "kind-$1" -n cumulus get secret unum-roots -o 'jsonpath={.data.ca\.crt}' | base64 -d | grep -c 'BEGIN CERTIFICATE')
    have=$(kubectl --context "kind-$1" -n cumulus exec deployment/api -c api -- sh -c \
        'test -s /opt/service/certs/client/tls.crt && grep -c "BEGIN CERTIFICATE" /opt/service/certs/roots/ca.crt' 2> /dev/null || true)
    test "$have" = "$want"
}

scripts/accept.sh "$A" "$B"
scripts/accept.sh "$B" "$A"
scripts/accept.sh "$A" "$B" cert-manager/root-ca cumulus/unum-roots
scripts/accept.sh "$B" "$A" cert-manager/root-ca cumulus/unum-roots

join "$A" "$B"
join "$B" "$A"

for c in "$A" "$B"; do
    tries=0
    until mounted "$c"; do
        tries=$((tries + 1))
        test "$tries" -lt 90 || { echo "the api of cumulus in $c never got its client certificate and the roots"; exit 1; }
        sleep 2
    done
done

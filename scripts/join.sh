#!/bin/sh
# Join two Unums: each follows the other (a Route row in its unum.route for the other, owner of everything it made, at its cumulus api by
# name and no port, on https, and the other's root in cumulus's secret unum-roots, which the api verifies it with) and accepts it (its
# root in what the ingress trusts), so a call between them is mutual TLS. It all goes through unifist-unum's api, from a pod in the Unum,
# with the fingerprint of the other's root, which here is taken from the other's api (by its node, since curl sends every *.localhost to
# 127.0.0.1) and not confirmed by a person. Safe to run again:
# one that has it all is left alone, and a Route on http gets https. It waits until the api pods have the client certificate and the roots,
# which the kubelet brings in about a minute after they change. Usage: scripts/join.sh <a> <b>, with both up.
set -e

A=$1
B=$2

test -n "$A" -a -n "$B" || { echo "usage: scripts/join.sh <a> <b>"; exit 1; }

# join <cluster> <other>: cluster follows and accepts other
join() {
    # the script is single quoted on purpose: the pod expands it, from the --env values
    # shellcheck disable=SC2016
    kubectl --context "kind-$1" run "join-$2" --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
        --env "CLUSTER=$1" --env "OTHER=$2" --command -- sh -c '
        # kubectl attaches after the pod starts and loses the output of a pod that has already finished
        sleep 2
        url="https://api.unifist-unum.$OTHER.localhost"
        fingerprint=""
        for i in $(seq 1 60); do
            fingerprint=$(curl -sk -m 10 --connect-to "::$OTHER-control-plane:443" "$url/unum" | grep -o "\"fingerprint\": \"[0-9a-f]*\"" | grep -o "[0-9a-f]\{64\}" || true)
            test -z "$fingerprint" || break
            sleep 2
        done
        test -n "$fingerprint" || { echo "$url never said who it is"; exit 1; }
        body="{\"url\": \"$url\", \"fingerprint\": \"$fingerprint\"}"
        for verb in follow accept; do
            curl -s -m 30 -X POST "http://api.unifist-unum/$verb" -H "Content-Type: application/json" -d "$body" |
                grep -q "\"unum\": \"$OTHER\"" || { echo "$CLUSTER could not $verb $OTHER"; exit 1; }
        done
        echo "$CLUSTER joined $OTHER"' 2> /dev/null
}

# mounted <cluster>: whether the api pod of cumulus has the client certificate and every root the secret holds
mounted() {
    want=$(kubectl --context "kind-$1" -n cumulus get secret unum-roots -o 'jsonpath={.data.ca\.crt}' 2> /dev/null | base64 -d | grep -c 'BEGIN CERTIFICATE' || true)
    have=$(kubectl --context "kind-$1" -n cumulus exec deployment/api -c api -- sh -c \
        'test -s /opt/service/certs/client/tls.crt && grep -c "BEGIN CERTIFICATE" /opt/service/certs/roots/ca.crt' 2> /dev/null || true)
    test "$want" -gt 0 -a "$have" = "$want"
}

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

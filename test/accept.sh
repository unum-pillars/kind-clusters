#!/bin/sh
# Prove a Unum accepts the client certificate of another once it has taken that Unum's root, and not before: a pod in B calls the
# api of A on https with B's client certificate, which A refuses at the handshake, runs scripts/accept.sh, and A then answers it.
# Usage: test/accept.sh <a> <b> [app], app being unifist-unum unless named, with both clusters up (make ci NAME=<each>). A trusts
# only its own root to begin with and again when it's done. The pod calls A's own node (--connect-to), since curl sends every
# *.localhost to 127.0.0.1 itself without asking DNS. It prints how long A took to answer after accepting, which is how long
# Traefik takes to use a changed trusted secret.
set -e

A=$1
B=$2
APP=${3:-unifist-unum}
HOST=api.$APP.$A.localhost
NODE=$A-control-plane

test -n "$A" -a -n "$B" || { echo "usage: test/accept.sh <a> <b> [app]"; exit 1; }

secret() {
    kubectl --context "kind-$1" -n "$2" get secret "$3" -o "jsonpath={.data.$4}" | base64 -d
}

# A trusts only its own root
reset() {
    kubectl --context "kind-$A" -n traefik delete secret trusted --ignore-not-found > /dev/null
    scripts/trust.sh "$A" > /dev/null
}

# A call from the pod in B to A's api, with B's client certificate if given: the answer on stdout
call() {
    kubectl --context "kind-$B" exec accept-test -- curl -fsS -m 10 --cacert /tmp/root.crt --connect-to "::$NODE:443" "$@" "https://$HOST/health" 2> /dev/null
}

# wait_for <seconds> <command>: runs the command until it succeeds, for up to that many seconds, one try every two
wait_for() {
    limit=$1
    shift
    start=$(date +%s)
    while ! "$@"; do
        test $(($(date +%s) - start)) -lt "$limit" || return 1
        sleep 2
    done
}

answers() {
    call "$@" | grep -q OK
}

refused() {
    ! answers "$@"
}

cleanup() {
    reset
    kubectl --context "kind-$B" delete pod accept-test --ignore-not-found --wait=false > /dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --context "kind-$B" delete pod accept-test --ignore-not-found > /dev/null
kubectl --context "kind-$B" run accept-test --restart=Never --image=curlimages/curl:8.11.1 --command -- sleep 600 > /dev/null
kubectl --context "kind-$B" wait --for=condition=Ready pod/accept-test --timeout=120s > /dev/null

secret "$A" cert-manager root-ca 'tls\.crt' | kubectl --context "kind-$B" exec -i accept-test -- sh -c 'cat > /tmp/root.crt'
{ secret "$B" cert-manager client 'tls\.crt'; secret "$B" cert-manager client 'tls\.key'; } |
    kubectl --context "kind-$B" exec -i accept-test -- sh -c 'cat > /tmp/client.pem'

reset

wait_for 120 answers || { echo "https://$HOST never answered with no client certificate"; exit 1; }

wait_for 120 refused --cert /tmp/client.pem || { echo "$A still accepts the client certificate of $B before it has accepted it"; exit 1; }

scripts/accept.sh "$A" "$B" > /dev/null

start=$(date +%s)
wait_for 120 answers --cert /tmp/client.pem || { echo "$A does not answer the client certificate of $B after accepting it"; exit 1; }
seconds=$(($(date +%s) - start))

scripts/accept.sh "$A" "$B" > /dev/null

roots=$(secret "$A" traefik trusted 'ca\.crt' | grep -c 'BEGIN CERTIFICATE')
test "$roots" -eq 2 || { echo "$A trusts $roots roots after accepting $B twice, not its own and $B's"; exit 1; }

echo "$A refuses the client certificate of $B, then answers it $seconds seconds after accepting the root of $B, once"

#!/bin/sh
# Prove a Unum checks a client certificate if it is given, and does not require one: a pod in the Unum calls the app on https with no
# certificate (a browser), with the Unum's own client certificate (its root is trusted), and with a certificate from a stranger
# (refused at the handshake). Usage: test/trust.sh <cluster> [app], app being unifist-unum unless named, with the cluster up.
# The pod calls the Unum's own node (--connect-to), since curl sends every *.localhost to 127.0.0.1 itself without asking DNS.
set -e

NAME=$1
APP=${2:-unifist-unum}
CTX=kind-$NAME
HOST=api.$APP.$NAME.localhost

test -n "$NAME" || { echo "usage: test/trust.sh <cluster> [app]"; exit 1; }

secret() {
    kubectl --context "$CTX" -n "$1" get secret "$2" -o "jsonpath={.data.$3}" | base64 -d
}

ROOT=$(secret cert-manager root-ca 'tls\.crt')
CLIENT="$(secret cert-manager client 'tls\.crt')
$(secret cert-manager client 'tls\.key')"

# a certificate from nobody this Unum trusts, certificate and key in one file, made with openssl in a container
STRANGER=$(docker run --rm alpine/openssl:3.5.5 req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
    -subj "/CN=stranger" -addext extendedKeyUsage=clientAuth -keyout /dev/stdout -out /dev/stdout 2> /dev/null)

kubectl --context "$CTX" delete pod "trust-$NAME" --ignore-not-found > /dev/null

# the script is single quoted on purpose: the pod expands it, from the --env values
# shellcheck disable=SC2016
kubectl --context "$CTX" run "trust-$NAME" --rm -i --restart=Never --image=curlimages/curl:8.11.1 \
    --env "ROOT=$ROOT" --env "CLIENT=$CLIENT" --env "STRANGER=$STRANGER" --env "NAME=$NAME" --env "HOST=$HOST" --command -- sh -c '
    echo "$ROOT" > /tmp/root.crt
    echo "$CLIENT" > /tmp/client.pem
    echo "$STRANGER" > /tmp/stranger.pem
    node=$NAME-control-plane

    call() {
        curl -fsS --cacert /tmp/root.crt --connect-to ::$node:443 "$@" https://$HOST/health 2> /dev/null
    }

    for i in $(seq 1 60); do
        call | grep -q OK && break
        test "$i" -lt 60 || { echo "https://$HOST never answered with no certificate"; exit 1; }
        sleep 2
    done

    call --cert /tmp/client.pem | grep -q OK ||
        { echo "$HOST refused the own client certificate of $NAME"; exit 1; }

    call --cert /tmp/stranger.pem > /dev/null &&
        { echo "$HOST accepted a client certificate from a stranger"; exit 1; }

    echo "$HOST answers with no certificate and with its own, and refuses one from a stranger"'

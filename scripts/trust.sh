#!/bin/sh
# Have a Unum's ingress check a client certificate if it is given: the secret trusted holds the CAs it trusts, its own root to
# begin with (scripts/accept.sh adds others, so it's made only if it isn't there), and the TLS option that says to check them. The
# secret first, so the option never points at nothing. Safe to run again. Usage: scripts/trust.sh <cluster>
set -e

NAME=$1
CTX=kind-$NAME

test -n "$NAME" || { echo "usage: scripts/trust.sh <cluster>"; exit 1; }

if ! kubectl --context "$CTX" -n traefik get secret trusted > /dev/null 2>&1; then
    kubectl --context "$CTX" -n cert-manager get secret root-ca -o 'jsonpath={.data.tls\.crt}' | base64 -d > "${TMPDIR:-/tmp}/trust-$NAME.crt"
    trap 'rm -f "${TMPDIR:-/tmp}/trust-$NAME.crt"' EXIT

    kubectl --context "$CTX" -n traefik create secret generic trusted --save-config --from-file=ca.crt="${TMPDIR:-/tmp}/trust-$NAME.crt"
fi

kubectl --context "$CTX" apply -f trust/tlsoption.yaml

#!/bin/sh
# Have a Unum's ingress check a client certificate if it is given: the secret trusted holds the CAs it trusts, its own root to
# begin with, and the TLS option that says to check them. The secret first, so the option never points at nothing. Safe to run again.
# Usage: scripts/trust.sh <cluster>
set -e

NAME=$1
CTX=kind-$NAME

test -n "$NAME" || { echo "usage: scripts/trust.sh <cluster>"; exit 1; }

kubectl --context "$CTX" -n cert-manager get secret root-ca -o 'jsonpath={.data.tls\.crt}' | base64 -d > "${TMPDIR:-/tmp}/trust-$NAME.crt"
trap 'rm -f "${TMPDIR:-/tmp}/trust-$NAME.crt"' EXIT

kubectl --context "$CTX" -n traefik create secret generic trusted --from-file=ca.crt="${TMPDIR:-/tmp}/trust-$NAME.crt" \
    --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
kubectl --context "$CTX" apply -f trust/tlsoption.yaml

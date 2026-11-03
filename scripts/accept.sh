#!/bin/sh
# Have a Unum accept client certificates from another: the root of the other is added to the secret trusted that the ingress of the
# Unum checks them against, if it isn't there already. The root is read from the other cluster's cert-manager/root-ca, as both are
# up on this machine. Safe to run again. Usage: scripts/accept.sh <cluster> <other>
set -e

NAME=$1
OTHER=$2
CTX=kind-$NAME

test -n "$NAME" -a -n "$OTHER" || { echo "usage: scripts/accept.sh <cluster> <other>"; exit 1; }

root=$(kubectl --context "kind-$OTHER" -n cert-manager get secret root-ca -o 'jsonpath={.data.tls\.crt}' | base64 -d)
trusted=$(kubectl --context "$CTX" -n traefik get secret trusted -o 'jsonpath={.data.ca\.crt}' | base64 -d)

case "$trusted" in
*"$root"*)
    echo "$NAME already accepts $OTHER"
    exit 0
    ;;
esac

printf '%s\n%s\n' "$trusted" "$root" > "${TMPDIR:-/tmp}/accept-$NAME.crt"
trap 'rm -f "${TMPDIR:-/tmp}/accept-$NAME.crt"' EXIT

kubectl --context "$CTX" -n traefik create secret generic trusted --from-file=ca.crt="${TMPDIR:-/tmp}/accept-$NAME.crt" \
    --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
echo "$NAME accepts $OTHER"

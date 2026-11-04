#!/bin/sh
# Have a Unum stop accepting client certificates from another: every root named for the other (its subject's common name, as a Unum's
# root is named for the Unum, so the roots a renewed CA left behind go too) is taken out of the secret trusted that the ingress of the
# Unum checks them against. The secret is changed in place, never deleted, since with none the ingress has no CA to check against.
# It refuses if no root would be left. New connections are refused within seconds; ones already open last until they close.
# Safe to run again. Usage: scripts/revoke.sh <cluster> <other>
set -e

NAME=$1
OTHER=$2
CTX=kind-$NAME

test -n "$NAME" -a -n "$OTHER" || { echo "usage: scripts/revoke.sh <cluster> <other>"; exit 1; }

trusted=$(kubectl --context "$CTX" -n traefik get secret trusted -o 'jsonpath={.data.ca\.crt}' | base64 -d)

# the roots whose common name isn't the other's, each certificate split out and read with openssl in a container
# the script is single quoted on purpose: the container expands it
# shellcheck disable=SC2016
kept=$(printf '%s\n' "$trusted" | docker run --rm -i -e "OTHER=$OTHER" --entrypoint sh alpine/openssl:3.5.5 -c '
    cd /tmp
    awk "/-----BEGIN CERTIFICATE-----/ {n++} n {print > (\"c\" n \".pem\")}"
    for i in $(seq 1 $(ls c*.pem 2> /dev/null | wc -l)); do
        name=$(openssl x509 -in "c$i.pem" -noout -subject -nameopt RFC2253 | sed -n "s/^subject=.*CN=\([^,]*\).*/\1/p")
        test "$name" = "$OTHER" || cat "c$i.pem"
    done')

before=$(printf '%s\n' "$trusted" | grep -c 'BEGIN CERTIFICATE' || true)
after=$(printf '%s\n' "$kept" | grep -c 'BEGIN CERTIFICATE' || true)

if [ "$before" -eq "$after" ]; then
    echo "$NAME does not accept $OTHER"
    exit 0
fi

if [ "$after" -eq 0 ]; then
    echo "refusing: $NAME would trust no one without the roots of $OTHER"
    exit 1
fi

printf '%s\n' "$kept" > "${TMPDIR:-/tmp}/revoke-$NAME.crt"
trap 'rm -f "${TMPDIR:-/tmp}/revoke-$NAME.crt"' EXIT

kubectl --context "$CTX" -n traefik create secret generic trusted --save-config --from-file=ca.crt="${TMPDIR:-/tmp}/revoke-$NAME.crt" \
    --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
echo "$NAME no longer accepts $OTHER"

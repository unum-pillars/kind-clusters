#!/bin/sh
# Prove a Unum's apps answer on HTTPS beside HTTP, with a certificate from the Unum's own root: a pod in the Unum calls the app by name,
# trusting the root and then not, and the certificate it gets is issued by the root (its CN is the Unum's name).
# Usage: test/https.sh <cluster> [app], app being unifist-unum unless named, with the cluster up. The pod calls the Unum's own node
# (--connect-to), since curl sends every *.localhost to 127.0.0.1 itself without asking DNS.
set -e

NAME=$1
APP=${2:-unifist-unum}
CTX=kind-$NAME
HOST=api.$APP.$NAME.localhost

test -n "$NAME" || { echo "usage: test/https.sh <cluster> [app]"; exit 1; }

ROOT=$(kubectl --context "$CTX" -n cert-manager get secret root-ca -o 'jsonpath={.data.tls\.crt}' | base64 -d)

kubectl --context "$CTX" delete pod "https-$NAME" --ignore-not-found > /dev/null

# the script is single quoted on purpose: the pod expands it, from the --env values
# shellcheck disable=SC2016
kubectl --context "$CTX" run "https-$NAME" --rm -i --restart=Never --image=curlimages/curl:8.11.1 \
    --env "ROOT=$ROOT" --env "NAME=$NAME" --env "HOST=$HOST" --command -- sh -c '
    # kubectl attaches after the pod starts and loses the output of a pod that has already finished, and then exits 0
    sleep 2
    echo "$ROOT" > /tmp/root.crt
    node=$NAME-control-plane

    for i in $(seq 1 60); do
        curl -fsS --cacert /tmp/root.crt --connect-to ::$node:443 https://$HOST/health 2> /dev/null | grep -q OK && break
        test "$i" -lt 60 || { echo "https://$HOST never answered with the root trusted"; exit 1; }
        sleep 2
    done

    curl -sS --connect-to ::$node:443 https://$HOST/health > /dev/null 2>&1 &&
        { echo "https://$HOST answered without the root trusted"; exit 1; }

    curl -sv --cacert /tmp/root.crt --connect-to ::$node:443 https://$HOST/health 2>&1 | grep -q "issuer: CN=$NAME\$" ||
        { echo "the certificate for $HOST is not issued by $NAME"; exit 1; }

    curl -fsS --connect-to ::$node:80 http://$HOST/health | grep -q OK ||
        { echo "http://$HOST stopped answering"; exit 1; }

    echo "$HOST answers on https with a certificate from $NAME, and on http"'

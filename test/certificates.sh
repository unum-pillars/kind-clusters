#!/bin/sh
# Prove a Unum can issue a certificate: ask cert-manager for one from the Unum's own authority (the ClusterIssuer named unum, which
# signs with the Unum's self-signed root), and check it is signed by that root, in a namespace made for this and removed after.
# Usage: test/certificates.sh <cluster>, with the cluster up.
set -e

NAME=$1
CTX=kind-$NAME
NS=certificates-test

test -n "$NAME" || { echo "usage: test/certificates.sh <cluster>"; exit 1; }

kubectl --context "$CTX" delete namespace "$NS" --ignore-not-found > /dev/null
kubectl --context "$CTX" create namespace "$NS" > /dev/null
trap 'kubectl --context "$CTX" delete namespace "$NS" --ignore-not-found --wait=false > /dev/null' EXIT

kubectl --context "$CTX" apply -f - > /dev/null <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test
  namespace: $NS
spec:
  secretName: test
  dnsNames:
  - test.$NAME.localhost
  issuerRef:
    kind: ClusterIssuer
    name: unum
EOF

kubectl --context "$CTX" -n "$NS" wait --for=condition=Ready certificate/test --timeout=120s > /dev/null || {
    echo "$NAME did not issue a certificate"; exit 1; }

secret() {
    kubectl --context "$CTX" -n "$1" get secret "$2" -o "jsonpath={.data.$3}" | base64 -d
}

CERT=$(secret "$NS" test 'tls\.crt')
ROOT=$(secret cert-manager root-ca 'tls\.crt')
CA=$(secret "$NS" test 'ca\.crt')

test "$CA" = "$ROOT" || { echo "the certificate's ca.crt isn't the Unum's root"; exit 1; }

# the certificate is signed by the root, checked with openssl in a container, so nothing here depends on the host's
docker run --rm --entrypoint sh -e CERT="$CERT" -e ROOT="$ROOT" alpine/openssl:3.5.5 -c \
    'echo "$ROOT" > /root.crt && echo "$CERT" > /cert.crt && openssl verify -CAfile /root.crt /cert.crt' > /dev/null || {
    echo "the certificate is not signed by the Unum's root"; exit 1; }

echo "$NAME issues certificates, signed by its own root"

#!/bin/sh
# Prove a renewed certificate or CA is used with no restart, and measure how long each takes. It is B's client certificate that is
# renewed, and a CA of B's, not B's own (a throwaway root, Issuer and client certificate in B's default namespace, the secret mounted
# as a directory into a pod that makes the calls with relations-rest's Source), so nothing of B's is left to put back:
#   - the client certificate: cert-manager renews it, the mounted file changes, a new connection to the echo app of A (test/whoami.sh)
#     shows the new serial, and a connection held open since before keeps showing the old one
#   - the CA: the root is renewed with a new key and the client certificate issued again from it, A refuses that until it accepts the new
#     root (scripts/accept.sh), then answers it
#   - the server certificate: A's for the echo app is renewed, and the pod sees the new one on its next connection while Traefik keeps
#     its pod and restarts nothing
# Usage: test/rotate.sh <a> <b> [app], app being unifist-unum unless named, with both clusters up (make ci NAME=<each>). It prints the
# seconds each took: the Secret mount delay (the kubelet's sync) and how long Traefik takes to use a changed secret. A trusts only its
# own root to begin with and again when it's done. The names resolve in the pod through the cluster's own DNS, which sends
# *.<unum>.localhost to the node of the Unum.
set -e

A=$1
B=$2
APP=${3:-unifist-unum}
WHOAMI=whoami.$APP.$A.localhost

test -n "$A" -a -n "$B" || { echo "usage: test/rotate.sh <a> <b> [app]"; exit 1; }

in_a() {
    kubectl --context "kind-$A" "$@"
}

in_b() {
    kubectl --context "kind-$B" "$@"
}

digest() {
    cksum | cut -d' ' -f1
}

EMPTY=$(printf '' | digest)

now() {
    date +%s
}

# A trusts only its own root
reset() {
    in_a -n traefik delete secret trusted --ignore-not-found > /dev/null
    scripts/trust.sh "$A" > /dev/null
}

# B's throwaway root, Issuer, client certificate and the pod that uses them
tidy() {
    in_b delete pod rotate-test --ignore-not-found --wait=false > /dev/null 2>&1 || true
    in_b delete certificate rotate-root rotate-client --ignore-not-found > /dev/null 2>&1 || true
    in_b delete issuer rotate-ca rotate-selfsigned --ignore-not-found > /dev/null 2>&1 || true
    in_b delete secret rotate-root rotate-client rotate-right --ignore-not-found > /dev/null 2>&1 || true
}

cleanup() {
    tidy
    reset
    test/whoami.sh "$A" "$APP" down
}
trap cleanup EXIT

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

# the Source's request, in the pod: ERR and what went wrong, or OK, the status, and the serial of the certificate the app was told the
# caller presented. The arguments are the url, the path and the file verify is.
CALL='
import re
import sys
import urllib.parse
import relations_rest

url, path, verify = sys.argv[1:4]

source = relations_rest.Source("check", url, cert=("/certs/client/tls.crt", "/certs/client/tls.key"), verify=verify)

try:
    response = source.session.get(f"{source.url}{path}", timeout=10)
except Exception as exception:
    print("ERR", type(exception).__name__, exception)
    sys.exit(0)

found = re.search(r"SerialNumber=\"(\d+)\"", urllib.parse.unquote(response.text))

print("OK", response.status_code, found.group(1) if found else "")
'

# the same request held open: one session, so one connection, asked again every two seconds, what it was told written to a log
HOLD='
import re
import sys
import time
import urllib.parse
import requests

session = requests.Session()
session.cert = ("/certs/client/tls.crt", "/certs/client/tls.key")
session.verify = "/certs/right/ca.crt"

while True:
    try:
        found = re.search(r"SerialNumber=\"(\d+)\"", urllib.parse.unquote(session.get(sys.argv[1], timeout=10).text))
        print(found.group(1) if found else "none", flush=True)
    except Exception as exception:
        print("ERR", type(exception).__name__, flush=True)
    time.sleep(2)
'

# the sha256 of the certificate a host serves, whether or not it can be verified
FINGER='
import hashlib
import socket
import ssl
import sys

context = ssl.create_default_context()
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE

with socket.create_connection((sys.argv[1], 443), timeout=10) as sock:
    with context.wrap_socket(sock, server_hostname=sys.argv[1]) as secure:
        print(hashlib.sha256(secure.getpeercert(binary_form=True)).hexdigest())
'

call() {
    in_b exec rotate-test -- python -c "$CALL" "https://$WHOAMI" / /certs/right/ca.crt
}

answers() {
    call | grep -q '^OK 200 [0-9]'
}

# the serial the app was told the caller presented
serial() {
    call | sed -n 's/^OK 200 \([0-9]*\)$/\1/p'
}

# the call a Unum that has not accepted B's CA is refused: not a failure to verify A, which would mean the wrong thing was tested
refused() {
    out=$(call)
    case "$out" in
    *CERTIFICATE_VERIFY_FAILED*) return 1 ;;
    "ERR "*) return 0 ;;
    esac
    return 1
}

fingerprint() {
    in_b exec rotate-test -- python -c "$FINGER" "$WHOAMI"
}

# the digest of a key of a secret in B, the empty one if it isn't there
held() {
    in_b get secret "$1" -o "jsonpath={.data.$2}" 2> /dev/null | digest
}

# reissued <secret> <digest>: whether cert-manager has made the secret again, and not as it was
reissued() {
    new=$(held "$1" 'tls\.crt')
    test "$new" != "$2" -a "$new" != "$EMPTY"
}

# mounted: whether the pod has the file the secret holds
mounted() {
    test "$(in_b exec rotate-test -- cat /certs/client/tls.crt | digest)" = "$(held rotate-client 'tls\.crt')"
}

# the client certificate issued again by the root as it is now: the root is in the chain the secret holds
renewed_client() {
    old=$(held rotate-client 'tls\.crt')
    in_b delete secret rotate-client > /dev/null
    wait_for 60 reissued rotate-client "$old" || return 1
    chain=$(in_b get secret rotate-client -o 'jsonpath={.data.tls\.crt}' | base64 -d)
    root=$(in_b get secret rotate-root -o 'jsonpath={.data.tls\.crt}' | base64 -d)
    case "$chain" in
    *"$root"*) return 0 ;;
    esac
    return 1
}

# the traefik pods of A and how often they've restarted
traefik() {
    in_a -n traefik get pods -o 'jsonpath={.items[*].metadata.uid} {.items[*].status.containerStatuses[*].restartCount}'
}

tidy
reset
test/whoami.sh "$A" "$APP" up

in_b apply -f - > /dev/null <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: rotate-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rotate-root
spec:
  isCA: true
  commonName: rotate-$B
  secretName: rotate-root
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    group: cert-manager.io
    kind: Issuer
    name: rotate-selfsigned
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: rotate-ca
spec:
  ca:
    secretName: rotate-root
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rotate-client
spec:
  commonName: $B
  secretName: rotate-client
  usages:
  - client auth
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    group: cert-manager.io
    kind: Issuer
    name: rotate-ca
EOF

in_b wait --for=condition=Ready certificate/rotate-root --timeout=120s > /dev/null
in_b wait --for=condition=Ready certificate/rotate-client --timeout=120s > /dev/null

in_b create secret generic rotate-right --from-literal="ca.crt=$(in_a -n cert-manager get secret root-ca -o 'jsonpath={.data.tls\.crt}' | base64 -d)" > /dev/null

in_b apply -f - > /dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: rotate-test
spec:
  restartPolicy: Never
  containers:
  - name: rotate-test
    image: python:3.12-alpine
    command:
    - sleep
    - "1800"
    volumeMounts:
    - name: client
      mountPath: /certs/client
    - name: right
      mountPath: /certs/right
  volumes:
  - name: client
    secret:
      secretName: rotate-client
  - name: right
    secret:
      secretName: rotate-right
EOF
in_b wait --for=condition=Ready pod/rotate-test --timeout=180s > /dev/null

in_b exec rotate-test -- pip install -q --no-cache-dir relations-rest==0.5.5 > /dev/null 2>&1 ||
    { echo "relations-rest 0.5.5 did not install in the pod"; exit 1; }

# A accepts B's throwaway root, and the Source gets through, with the serial of the certificate it presented
scripts/accept.sh "$A" "$B" default/rotate-root > /dev/null

wait_for 120 answers || { echo "$A does not answer B's client certificate from its throwaway root: $(call)"; exit 1; }

first=$(serial)
test -n "$first" || { echo "$WHOAMI was not told the serial of B's client certificate"; exit 1; }

# One connection held open from now on
# the script is single quoted on purpose: the pod expands it
# shellcheck disable=SC2016
in_b exec rotate-test -- sh -c 'nohup python -c "$1" "$2" > /tmp/hold.log 2>&1 &' sh "$HOLD" "https://$WHOAMI/"

holding() {
    in_b exec rotate-test -- tail -1 /tmp/hold.log | grep -q "^$first\$"
}

wait_for 30 holding || { echo "the connection held open never got through"; exit 1; }

# The client certificate renewed
old=$(held rotate-client 'tls\.crt')
in_b delete secret rotate-client > /dev/null
wait_for 60 reissued rotate-client "$old" || { echo "cert-manager did not renew the client certificate"; exit 1; }

start=$(now)
wait_for 240 mounted || { echo "the pod did not get the renewed client certificate in 240 seconds"; exit 1; }
mount_seconds=$(($(now) - start))

second=$(serial)
test -n "$second" -a "$second" != "$first" || { echo "a new connection did not use the renewed client certificate: $first then $second"; exit 1; }

held_serial=$(in_b exec rotate-test -- tail -1 /tmp/hold.log)
test "$held_serial" = "$first" || { echo "the connection held open did not keep the old certificate: $first, then $held_serial"; exit 1; }

# The CA renewed, with a new key, and the client certificate issued again by it
old=$(held rotate-root 'tls\.crt')
in_b delete secret rotate-root > /dev/null
wait_for 60 reissued rotate-root "$old" || { echo "cert-manager did not renew the root"; exit 1; }

wait_for 120 renewed_client || { echo "cert-manager did not issue the client certificate again from the renewed root"; exit 1; }
wait_for 240 mounted || { echo "the pod did not get the client certificate from the renewed root in 240 seconds"; exit 1; }

wait_for 30 refused || { echo "$A did not refuse the client certificate from B's renewed root before accepting it: $(call)"; exit 1; }

scripts/accept.sh "$A" "$B" default/rotate-root > /dev/null

start=$(now)
wait_for 120 answers || { echo "$A does not answer B's client certificate from the renewed root after accepting it: $(call)"; exit 1; }
ca_seconds=$(($(now) - start))

roots=$(in_a -n traefik get secret trusted -o 'jsonpath={.data.ca\.crt}' | base64 -d | grep -c 'BEGIN CERTIFICATE')
test "$roots" -eq 3 || { echo "$A trusts $roots roots, not its own and the two of B's"; exit 1; }

# The server certificate renewed, and Traefik keeping its pod
before=$(fingerprint)
pods=$(traefik)

in_a -n "$APP" delete secret whoami-tls > /dev/null

served() {
    now_serving=$(fingerprint 2> /dev/null || true)
    test -n "$now_serving" -a "$now_serving" != "$before" && answers
}

start=$(now)
wait_for 180 served || { echo "the pod did not see a renewed certificate for $WHOAMI in 180 seconds"; exit 1; }
server_seconds=$(($(now) - start))

test "$(traefik)" = "$pods" || { echo "Traefik in $A restarted when the certificate for $WHOAMI was renewed"; exit 1; }

echo "renewed client certificate: in the pod $mount_seconds seconds after cert-manager made it, used by the next connection, not by one held open; renewed CA: $A answers $ca_seconds seconds after accepting it; renewed server certificate: used by the next connection $server_seconds seconds after cert-manager lost it, Traefik not restarted"

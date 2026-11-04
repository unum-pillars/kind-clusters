#!/bin/sh
# Prove a relations-rest Source in one Unum calls another over mutual TLS with its cert and verify as paths to mounted secrets: from a
# pod in B, a Source to the api of A is refused until A accepts the root of B, then answers, fails the handshake when verify is the
# root of B instead of A's (B is not who A says it is), and the echo app of A (test/whoami.sh) is told that B called. The Source is
# relations-rest's, from PyPI, and the requests are the ones it makes: its session carries the cert and verify. The secrets are mounted
# as directories, never subPath, so a renewed one is seen on the next connection. Usage: test/rest.sh <a> <b> [app], app being
# unifist-unum unless named, with both clusters up (make ci NAME=<each>). A trusts only its own root to begin with and again when it's
# done. The names resolve in the pod through the cluster's own DNS, which sends *.<unum>.localhost to the node of the Unum.
set -e

A=$1
B=$2
APP=${3:-unifist-unum}
API=api.$APP.$A.localhost
WHOAMI=whoami.$APP.$A.localhost

test -n "$A" -a -n "$B" || { echo "usage: test/rest.sh <a> <b> [app]"; exit 1; }

secret() {
    kubectl --context "kind-$1" -n "$2" get secret "$3" -o "jsonpath={.data.$4}" | base64 -d
}

# A trusts only its own root
reset() {
    kubectl --context "kind-$A" -n traefik delete secret trusted --ignore-not-found > /dev/null
    scripts/trust.sh "$A" > /dev/null
}

cleanup() {
    reset
    test/whoami.sh "$A" "$APP" down
    kubectl --context "kind-$B" delete pod rest-test --ignore-not-found --wait=false > /dev/null 2>&1 || true
    kubectl --context "kind-$B" delete secret rest-client rest-right rest-wrong --ignore-not-found > /dev/null 2>&1 || true
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

# the Source's request, in the pod: ERR and what went wrong, or OK, the status, and what the app was told about the caller. The
# arguments are the url, the path and the file verify is.
# the script is single quoted on purpose: python reads it
# shellcheck disable=SC2016
CHECK='
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

told = [urllib.parse.unquote(line.split(": ", 1)[1]) for line in response.text.splitlines()
        if line.lower().startswith("x-forwarded-tls-client-cert-info: ")]

print("OK", response.status_code, " ".join(told))
'

# check <right|wrong> <host> <path>: the Source's request to the host, verify being the root of A (right) or of B (wrong)
check() {
    kubectl --context "kind-$B" exec rest-test -- python -c "$CHECK" "https://$2" "$3" "/certs/$1/ca.crt"
}

# the call a Unum that has not accepted B is refused: not a failure to verify A, which would mean the wrong thing was tested
refused() {
    out=$(check right "$API" /health)
    case "$out" in
    *CERTIFICATE_VERIFY_FAILED*) return 1 ;;
    "ERR "*) return 0 ;;
    esac
    return 1
}

answers() {
    check right "$API" /health | grep -q '^OK 200 '
}

# secret_for <name> <create secret arguments>: the secret in B, made or made again
secret_for() {
    name=$1
    shift
    kubectl --context "kind-$B" create secret generic "$name" --dry-run=client -o yaml "$@" | kubectl --context "kind-$B" apply -f - > /dev/null
}

reset
test/whoami.sh "$A" "$APP" up

secret_for rest-client "--from-literal=tls.crt=$(secret "$B" cert-manager client 'tls\.crt')" "--from-literal=tls.key=$(secret "$B" cert-manager client 'tls\.key')"
secret_for rest-right "--from-literal=ca.crt=$(secret "$A" cert-manager root-ca 'tls\.crt')"
secret_for rest-wrong "--from-literal=ca.crt=$(secret "$B" cert-manager root-ca 'tls\.crt')"

kubectl --context "kind-$B" delete pod rest-test --ignore-not-found > /dev/null
kubectl --context "kind-$B" apply -f - > /dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: rest-test
spec:
  restartPolicy: Never
  containers:
  - name: rest-test
    image: python:3.12-alpine
    command:
    - sleep
    - "900"
    volumeMounts:
    - name: client
      mountPath: /certs/client
    - name: right
      mountPath: /certs/right
    - name: wrong
      mountPath: /certs/wrong
  volumes:
  - name: client
    secret:
      secretName: rest-client
  - name: right
    secret:
      secretName: rest-right
  - name: wrong
    secret:
      secretName: rest-wrong
EOF
kubectl --context "kind-$B" wait --for=condition=Ready pod/rest-test --timeout=180s > /dev/null

kubectl --context "kind-$B" exec rest-test -- pip install -q --no-cache-dir relations-rest==0.5.5 > /dev/null 2>&1 ||
    { echo "relations-rest 0.5.5 did not install in the pod"; exit 1; }

wait_for 120 refused || { echo "the Source in $B is not refused by $A before it has accepted $B: $(check right "$API" /health)"; exit 1; }

scripts/accept.sh "$A" "$B" > /dev/null

wait_for 120 answers || { echo "the Source in $B does not get an answer from $A after it accepted $B: $(check right "$API" /health)"; exit 1; }

check wrong "$API" /health | grep -q 'CERTIFICATE_VERIFY_FAILED' ||
    { echo "the Source in $B did not fail the handshake with the root of $B to verify $A: $(check wrong "$API" /health)"; exit 1; }

check right "$WHOAMI" / | grep -q "^OK 200 Subject=\"CN=$B\"" ||
    { echo "$WHOAMI was not told $B called through the Source: $(check right "$WHOAMI" /)"; exit 1; }

echo "a Source in $B is refused by $A, answered once $A accepts $B, fails the handshake with the wrong root to verify, and $A is told $B called"

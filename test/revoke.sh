#!/bin/sh
# Prove a Unum stops accepting the client certificates of another once it revokes it, and what that does not do: from a pod in B, a
# relations-rest Source calls the api of A with B's client certificate, which A answers once it has accepted B and refuses with a TLS
# alert once scripts/revoke.sh has taken B's roots out of what it trusts, while a connection held open since before keeps being answered
# (the certificate is checked when the connection is made, so it lasts until it closes). A revoke that would leave A trusting no one is
# refused. Usage: test/revoke.sh <a> <b> [app], app being unifist-unum unless named, with both clusters up (make ci NAME=<each>). It
# prints how long A took to refuse. A trusts only its own root to begin with and again when it's done. The names resolve in the pod
# through the cluster's own DNS, which sends *.<unum>.localhost to the node of the Unum.
set -e

A=$1
B=$2
APP=${3:-unifist-unum}
API=api.$APP.$A.localhost

test -n "$A" -a -n "$B" || { echo "usage: test/revoke.sh <a> <b> [app]"; exit 1; }

in_a() {
    kubectl --context "kind-$A" "$@"
}

in_b() {
    kubectl --context "kind-$B" "$@"
}

# A trusts only its own root
reset() {
    in_a -n traefik delete secret trusted --ignore-not-found > /dev/null
    scripts/trust.sh "$A" > /dev/null
}

tidy() {
    in_b delete pod revoke-test --ignore-not-found --grace-period=1 > /dev/null 2>&1 || true
    in_b delete secret revoke-client revoke-right --ignore-not-found > /dev/null 2>&1 || true
}

cleanup() {
    tidy
    reset
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

# the Source's request, in the pod: ERR and what went wrong, or OK and the status. The arguments are the url, the path and the file verify is.
CALL='
import sys
import relations_rest

url, path, verify = sys.argv[1:4]

source = relations_rest.Source("check", url, cert=("/certs/client/tls.crt", "/certs/client/tls.key"), verify=verify)

try:
    response = source.session.get(f"{source.url}{path}", timeout=10)
except Exception as exception:
    print("ERR", type(exception).__name__, exception)
    sys.exit(0)

print("OK", response.status_code)
'

# the same request held open: one session, so one connection, asked again every two seconds, what came of it written to a log
HOLD='
import sys
import time
import requests

session = requests.Session()
session.cert = ("/certs/client/tls.crt", "/certs/client/tls.key")
session.verify = "/certs/right/ca.crt"

while True:
    try:
        print("OK", session.get(sys.argv[1], timeout=10).status_code, flush=True)
    except Exception as exception:
        print("ERR", type(exception).__name__, flush=True)
    time.sleep(2)
'

call() {
    in_b exec revoke-test -- python -c "$CALL" "https://$API" /health /certs/right/ca.crt
}

answers() {
    call | grep -q '^OK 200'
}

# the call a Unum that has revoked B is refused: not a failure to verify A, which would mean the wrong thing was tested
refused() {
    out=$(call)
    case "$out" in
    *CERTIFICATE_VERIFY_FAILED*) return 1 ;;
    "ERR "*) return 0 ;;
    esac
    return 1
}

holding() {
    in_b exec revoke-test -- tail -1 /tmp/hold.log | grep -q '^OK 200'
}

roots() {
    in_a -n traefik get secret trusted -o 'jsonpath={.data.ca\.crt}' | base64 -d | grep -c 'BEGIN CERTIFICATE'
}

secret_for() {
    name=$1
    shift
    in_b create secret generic "$name" --dry-run=client -o yaml "$@" | in_b apply -f - > /dev/null
}

tidy
reset

secret_for revoke-client "--from-literal=tls.crt=$(in_b -n cert-manager get secret client -o 'jsonpath={.data.tls\.crt}' | base64 -d)" "--from-literal=tls.key=$(in_b -n cert-manager get secret client -o 'jsonpath={.data.tls\.key}' | base64 -d)"
secret_for revoke-right "--from-literal=ca.crt=$(in_a -n cert-manager get secret root-ca -o 'jsonpath={.data.tls\.crt}' | base64 -d)"

in_b apply -f - > /dev/null <<EOY
apiVersion: v1
kind: Pod
metadata:
  name: revoke-test
spec:
  restartPolicy: Never
  containers:
  - name: revoke-test
    image: python:3.12-alpine
    command:
    - sleep
    - "900"
    volumeMounts:
    - name: client
      mountPath: /certs/client
    - name: right
      mountPath: /certs/right
  volumes:
  - name: client
    secret:
      secretName: revoke-client
  - name: right
    secret:
      secretName: revoke-right
EOY
in_b wait --for=condition=Ready pod/revoke-test --timeout=180s > /dev/null

in_b exec revoke-test -- pip install -q --no-cache-dir relations-rest==0.5.5 > /dev/null 2>&1 ||
    { echo "relations-rest 0.5.5 did not install in the pod"; exit 1; }

scripts/accept.sh "$A" "$B" > /dev/null

wait_for 120 answers || { echo "$A does not answer B's client certificate after accepting it: $(call)"; exit 1; }

# One connection held open from now on
# the script is single quoted on purpose: the pod expands it
# shellcheck disable=SC2016
in_b exec revoke-test -- sh -c 'nohup python -c "$1" "$2" > /tmp/hold.log 2>&1 &' sh "$HOLD" "https://$API/health"
wait_for 30 holding || { echo "the connection held open never got through"; exit 1; }

# Revoked: new connections are refused
test "$(roots)" -eq 2 || { echo "$A trusts $(roots) roots after accepting $B, not its own and the one of $B"; exit 1; }

scripts/revoke.sh "$A" "$B" > /dev/null

start=$(date +%s)
wait_for 120 refused || { echo "$A still answers B's client certificate after revoking $B: $(call)"; exit 1; }
seconds=$(($(date +%s) - start))

test "$(roots)" -eq 1 || { echo "$A trusts $(roots) roots after revoking $B, not only its own"; exit 1; }

# The connection held open lasts until it closes
sleep 6
holding || { echo "the connection held open did not keep being answered after revoking $B: $(in_b exec revoke-test -- tail -3 /tmp/hold.log)"; exit 1; }

# Revoking again changes nothing, and so does revoking the last root
scripts/revoke.sh "$A" "$B" | grep -q 'does not accept' || { echo "revoking $B twice did not say $A does not accept it"; exit 1; }

if scripts/revoke.sh "$A" "$A" > /dev/null 2>&1; then
    echo "$A revoked its own root, and trusts no one"
    exit 1
fi
test "$(roots)" -eq 1 || { echo "$A trusts $(roots) roots after refusing to revoke its own"; exit 1; }

echo "$A refuses the client certificate of $B $seconds seconds after revoking $B, a connection held open since before is still answered, and it will not revoke its own root"

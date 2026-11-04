#!/bin/sh
# Prove joined Unums read each other's records over https with mutual TLS: the Route rows each holds for the other are https urls (joining
# again changes one that is on http), a
# record made in A is read from B, and once A has revoked B, with Traefik restarted to cut the connection B's api held open, B no
# longer reads it, until A accepts B again. Usage: test/secure.sh <a> <b>, with both clusters up (make ci NAME=<each>). It joins
# them first, which also has each accept the other's root, so the Unums are joined and A accepts B when it's done. The calls are curl
# from a pod in each cluster, by service name, so they need no ingress cluster.
set -e

A=$1
B=$2
WHO="secure-test-$$"

test -n "$A" -a -n "$B" || { echo "usage: test/secure.sh <a> <b>"; exit 1; }

# A pod in each cluster to call from, and the record made, taken away however this ends.
cleanup() {
    scripts/accept.sh "$A" "$B" > /dev/null 2>&1 || true
    kubectl --context "kind-$A" exec secure-test -- curl -s -m 10 -X DELETE "http://api.cumulus/model/unifist/$WHO:unifist.cumulus:$A" > /dev/null 2>&1 || true
    for c in "$A" "$B"; do
        kubectl --context "kind-$c" delete pod secure-test --ignore-not-found --grace-period=1 > /dev/null 2>&1 || true
    done
}
trap cleanup EXIT

for c in "$A" "$B"; do
    kubectl --context "kind-$c" delete pod secure-test --ignore-not-found > /dev/null
    kubectl --context "kind-$c" run secure-test --restart=Never --image=curlimages/curl:8.10.1 --command -- sleep 600 > /dev/null
    kubectl --context "kind-$c" wait --for=condition=Ready pod/secure-test --timeout=120s > /dev/null
done

# call <cluster> <curl arguments>: curl from the pod in the cluster, the answer on stdout
call() {
    cluster=$1
    shift
    kubectl --context "kind-$cluster" exec secure-test -- curl -s -m 10 "$@"
}

# count <cluster>: how many records with the who of A the cluster's cumulus api answers with
count() {
    call "$1" "http://api.cumulus/model/unifist?who=$WHO" | grep -o "\"who\": \"$WHO\"" | wc -l | tr -d ' '
}

# reads <cluster> <count>: whether the cluster reads that many, tried for up to a minute
reads() {
    tries=0
    while [ "$tries" -lt 30 ]; do
        test "$(count "$1")" = "$2" && return 0
        tries=$((tries + 1))
        sleep 2
    done
    return 1
}

scripts/join.sh "$A" "$B" > /dev/null

# A Route that is still on http is changed to https by joining again
for id in $(call "$A" "http://api.unifist-unum/model/route?holder=$B" | grep -o '"id": [0-9]*' | grep -o '[0-9]*'); do
    call "$A" -X DELETE "http://api.unifist-unum/model/route/$id" > /dev/null
done
call "$A" -X POST http://api.unifist-unum/model/route -H 'Content-Type: application/json' \
    -d "{\"route\": {\"home\": \"$B\", \"role\": \"owner\", \"holder\": \"$B\", \"url\": \"http://api.cumulus.$B.localhost\"}}" |
    grep -q '"url": "http://' || { echo "no Route on http made in $A for $B"; exit 1; }

scripts/join.sh "$A" "$B" > /dev/null

# Https urls
for c in "$A" "$B"; do
    other=$A
    test "$c" != "$A" || other=$B
    call "$c" "http://api.unifist-unum/model/route?holder=$other" | grep -q "\"url\": \"https://api.cumulus.$other.localhost\"" ||
        { echo "$c does not reach $other by an https url"; exit 1; }
done

# A record made in A is read from B, over https
call "$A" -X POST http://api.cumulus/model/unifist -H 'Content-Type: application/json' -d "{\"unifist\": {\"who\": \"$WHO\"}}" |
    grep -q "\"id\": \"$WHO:unifist.cumulus:$A\"" || { echo "no record made in $A with the id of $A"; exit 1; }

reads "$A" 1 || { echo "$A does not read its own record"; exit 1; }
reads "$B" 1 || { echo "$B does not read the record of $A over https"; exit 1; }

# A revokes B, and Traefik in A is restarted to cut the connection B's api holds open, which a revoke leaves: B no longer reads it
scripts/revoke.sh "$A" "$B" > /dev/null
kubectl --context "kind-$A" -n traefik rollout restart deployment/traefik > /dev/null
kubectl --context "kind-$A" -n traefik rollout status deployment/traefik --timeout=120s > /dev/null

reads "$B" 0 || { echo "$B still reads the record of $A after $A revoked it"; exit 1; }
reads "$A" 1 || { echo "$A does not read its own record after revoking $B"; exit 1; }

# A accepts B again, and B reads it again
scripts/accept.sh "$A" "$B" > /dev/null
reads "$B" 1 || { echo "$B does not read the record of $A after $A accepted it again"; exit 1; }

echo "$B reads the record of $A over https, stops when $A revokes it, and reads it again when $A accepts it"

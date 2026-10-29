#!/bin/sh
# Prove the one-writer half of writes across joined Unums: the owner of a record creates, updates and deletes it, and the other Unum
# reads each change straight away, with one version bump and one journal entry for each write, and no copy kept in the other. A write
# from a Unum that doesn't own the record isn't covered, since it isn't supported yet (relations-dil/python-relations-unifist#19).
# Usage: test/write.sh <a> <b>, with both clusters up and joined. Each takes a turn as the owner. The calls are curl from a pod in
# each cluster, by service name, so they need no ingress cluster, and the database is read in each cluster's MySQL.
set -e

A=$1
B=$2
WHO="write-test-$$"

# The records made and their journal entries, and the pods, taken away however this ends.
cleanup() {
    for c in "$A" "$B"; do
        kubectl --context "kind-$c" -n mysql exec deployment/mysql -- env MYSQL_PWD=root mysql -uroot -N -e \
            "DELETE FROM unifist.journal WHERE id LIKE '%:$WHO-%'; DELETE FROM cumulus.unifist WHERE who LIKE '$WHO-%'" >/dev/null 2>&1 || true
        kubectl --context "kind-$c" delete pod write-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

for c in "$A" "$B"; do
    kubectl --context "kind-$c" delete pod write-test --ignore-not-found >/dev/null
    kubectl --context "kind-$c" run write-test --restart=Never --image=curlimages/curl:8.10.1 --command -- sleep 600 >/dev/null
    kubectl --context "kind-$c" wait --for=condition=Ready pod/write-test --timeout=120s >/dev/null
done

scripts/join.sh "$A" "$B" >/dev/null

# call <cluster> <curl arguments>: curl from the pod in the cluster, the answer on stdout
call() {
    cluster=$1
    shift
    kubectl --context "kind-$cluster" exec write-test -- curl -s -m 10 "$@"
}

# sql <cluster> <statement>: one value from the cluster's MySQL
sql() {
    kubectl --context "kind-$1" -n mysql exec deployment/mysql -- env MYSQL_PWD=root mysql -uroot -N -e "$2" 2>/dev/null
}

# expect <what> <got> <wanted>
expect() {
    test "$2" = "$3" || { echo "$1: $2, not $3"; exit 1; }
    echo "$1: $2"
}

# version <json> and what <json>: the record's version and what, from an api answer
version() { sed -n 's/.*"version": \([0-9][0-9]*\).*/\1/p' | head -1; }
what() { grep -o '"what": {[^}]*}' | head -1; }

# journal <cluster> <who>: how many journal entries the cluster holds for the record, and held <cluster> <who>: how many records
journal() { sql "$1" "SELECT COUNT(*) FROM unifist.journal WHERE id LIKE '%:$2:unifist.cumulus:%'"; }
held() { sql "$1" "SELECT COUNT(*) FROM cumulus.unifist WHERE who = '$2'"; }

# One turn: owner $1 writes, reader $2 reads
turn() {
    owner=$1
    reader=$2
    who="$WHO-$owner"
    id="$who:unifist.cumulus:$owner"

    echo "== $owner owns, $reader reads"

    call "$owner" -X POST http://api.cumulus/model/unifist -H 'Content-Type: application/json' -d "{\"unifist\": {\"who\": \"$who\"}}" |
        grep -q "\"id\": \"$id\"" || { echo "no record made in $owner with its id"; exit 1; }

    seen=$(call "$reader" "http://api.cumulus/model/unifist/$id")
    expect "created: $reader reads version" "$(echo "$seen" | version)" 1
    expect "created: $reader reads the home" "$(echo "$seen" | grep -o '"home": "[a-z]*"' | head -1)" "\"home\": \"$owner\""
    expect "created: $owner journal entries" "$(journal "$owner" "$who")" 1

    expect "updated" "$(call "$owner" -X PATCH "http://api.cumulus/model/unifist/$id" -H 'Content-Type: application/json' -d "{\"unifist\": {\"what\": {\"by\": \"$owner\"}}}")" '{"updated": 1}'
    seen=$(call "$reader" "http://api.cumulus/model/unifist/$id")
    expect "updated: $reader reads version" "$(echo "$seen" | version)" 2
    expect "updated: $reader reads what" "$(echo "$seen" | what)" "\"what\": {\"by\": \"$owner\"}"
    expect "updated: $owner journal entries" "$(journal "$owner" "$who")" 2

    expect "deleted" "$(call "$owner" -X DELETE "http://api.cumulus/model/unifist/$id")" '{"deleted": 1}'
    expect "deleted: $reader reads" "$(call "$reader" "http://api.cumulus/model/unifist/$id" | grep -o 'none retrieved')" "none retrieved"
    expect "deleted: $owner journal entries" "$(journal "$owner" "$who")" 3

    # The reader never kept a copy, in its records or its journal.
    expect "$reader records kept" "$(held "$reader" "$who")" 0
    expect "$reader journal entries kept" "$(journal "$reader" "$who")" 0
}

turn "$A" "$B"
turn "$B" "$A"

echo ok

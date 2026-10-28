#!/bin/sh
# Prove two Unums read each other's cumulus records once they're joined, and not before: a record made in one is read from
# the other, is in one place only, and keeps the id of the Unum that made it. Usage: test/route.sh <a> <b>, with both
# clusters up (make ci NAME=<each>). It takes the join away first, and puts it back with scripts/join.sh, so the
# Unums are joined when it's done. The calls are curl from a pod in each cluster, by service name, so they need no ingress cluster.
set -e

A=$1
B=$2
WHO="route-test-$$"

# A pod in each cluster to call from, and the records made, taken away however this ends.
cleanup() {
    for c in "$A" "$B"; do
        for who in "$WHO-$c" $(ordered "$c"); do
            kubectl --context "kind-$c" exec route-test -- curl -s -m 10 -X DELETE "http://api.cumulus/model/unifist/$who:unifist.cumulus:$c" >/dev/null 2>&1 || true
        done
        kubectl --context "kind-$c" delete pod route-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

for c in "$A" "$B"; do
    kubectl --context "kind-$c" delete pod route-test --ignore-not-found >/dev/null
    kubectl --context "kind-$c" run route-test --restart=Never --image=curlimages/curl:8.10.1 --command -- sleep 600 >/dev/null
    kubectl --context "kind-$c" wait --for=condition=Ready pod/route-test --timeout=120s >/dev/null
done

# call <cluster> <curl arguments>: curl from the pod in the cluster, the answer on stdout
call() {
    cluster=$1
    shift
    kubectl --context "kind-$cluster" exec route-test -- curl -s -m 10 "$@"
}

# count <cluster> <who>: how many cumulus records with the who the cluster's api answers with
count() {
    call "$1" "http://api.cumulus/model/unifist?who=$2" | grep -o "\"who\": \"$2\"" | wc -l | tr -d ' '
}

# expect <what> <got> <wanted>
expect() {
    test "$2" = "$3" || { echo "$1: $2, not $3"; exit 1; }
    echo "$1: $2"
}

# ordered <cluster>: the names of the records the order check makes in the cluster, A the odd ones and B the even, so that
# sorted by id they alternate between the two Unums
ordered() {
    if test "$1" = "$A"; then echo "$WHO-o1 $WHO-o3"; else echo "$WHO-o2 $WHO-o4"; fi
}

# Not joined: the join rows are the ones the other holds, the only ones with a holder that isn't the Unum itself.
unjoin() {
    for id in $(call "$1" "http://api.unifist-unum/model/route?holder=$2" | grep -o '"id": [0-9]*' | grep -o '[0-9]*'); do
        call "$1" -X DELETE "http://api.unifist-unum/model/route/$id" >/dev/null
    done
}

unjoin "$A" "$B"
unjoin "$B" "$A"

for c in "$A" "$B"; do
    call "$c" -X POST http://api.cumulus/model/unifist -H 'Content-Type: application/json' -d "{\"unifist\": {\"who\": \"$WHO-$c\"}}" |
        grep -q "\"id\": \"$WHO-$c:unifist.cumulus:$c\"" || { echo "no record made in $c with the id of $c"; exit 1; }
done

echo "== not joined"
expect "$A reads its own" "$(count "$A" "$WHO-$A")" 1
expect "$B reads its own" "$(count "$B" "$WHO-$B")" 1
expect "$A reads $B's" "$(count "$A" "$WHO-$B")" 0
expect "$B reads $A's" "$(count "$B" "$WHO-$A")" 0

scripts/join.sh "$A" "$B"
scripts/join.sh "$A" "$B"

echo "== joined"
expect "$A reads its own" "$(count "$A" "$WHO-$A")" 1
expect "$B reads its own" "$(count "$B" "$WHO-$B")" 1
expect "$A reads $B's" "$(count "$A" "$WHO-$B")" 1
expect "$B reads $A's" "$(count "$B" "$WHO-$A")" 1

# Once, not twice: all the records with the who, not those the who matches, and the ids the Unum that made each.
for c in "$A" "$B"; do
    other=$A
    test "$c" != "$A" || other=$B
    expect "$c reads both" "$(call "$c" "http://api.cumulus/model/unifist" | grep -o "\"who\": \"$WHO-" | wc -l | tr -d ' ')" 2
    call "$c" "http://api.cumulus/model/unifist?who=$WHO-$other" | grep -q "\"id\": \"$WHO-$other:unifist.cumulus:$other\"" ||
        { echo "$c does not read $other's with the id of $other"; exit 1; }
done

# And each is held in one place only: the database of the Unum that made it.
for c in "$A" "$B"; do
    for held in "$A" "$B"; do
        want=0
        test "$held" != "$c" || want=1
        got=$(kubectl --context "kind-$held" -n mysql exec deployment/mysql -- env MYSQL_PWD=root mysql -uroot -N -e "SELECT COUNT(*) FROM cumulus.unifist WHERE who='$WHO-$c'")
        expect "$WHO-$c is held in $held" "$got" "$want"
    done
done

# Read in order, whichever Unum asks: the records of both merged as if they were one, ascending and descending.
for c in "$A" "$B"; do
    for who in $(ordered "$c"); do
        call "$c" -X POST http://api.cumulus/model/unifist -H 'Content-Type: application/json' -d "{\"unifist\": {\"who\": \"$who\"}}" |
            grep -q "\"id\": \"$who:unifist.cumulus:$c\"" || { echo "no record $who made in $c"; exit 1; }
    done
done

ids() {
    call "$1" "http://api.cumulus/model/unifist$2" | grep -o "\"id\": \"$WHO-o[0-9]:" | grep -o "$WHO-o[0-9]" | tr '\n' ' '
}

for c in "$A" "$B"; do
    expect "$c reads in order" "$(ids "$c" "")" "$WHO-o1 $WHO-o2 $WHO-o3 $WHO-o4 "
    expect "$c reads in reverse" "$(ids "$c" "?sort=-id")" "$WHO-o4 $WHO-o3 $WHO-o2 $WHO-o1 "
done

# And it answers, fast: joined both ways, a read that asked for ever would time out, or fail when the database ran out of connections.
for c in "$A" "$B"; do
    expect "$c answers a read of everything" "$(call "$c" -m 5 -o /dev/null -w '%{http_code}' http://api.cumulus/model/unifist)" 200
done

echo ok

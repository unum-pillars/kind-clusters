#!/bin/sh
# Prove one Unum reaches another's unifist-unum API from inside its cluster, by the other's node name and NodePort
# (see the port table in the README). Usage: test/cross.sh <from> <to>, with both clusters up. Run it both ways.
set -e

FROM=$1
TO=$2
PORT=30465

kubectl --context "kind-$FROM" run "cross-$TO" --rm -i --restart=Never --image=busybox:1.36 --command -- sh -c "
    for i in \$(seq 1 30); do
        wget -q -T 5 -O - http://$TO-control-plane:$PORT/health | grep -q OK && echo ok && exit 0
        sleep 2
    done
    echo '$TO-control-plane:$PORT never answered from $FROM'
    exit 1"

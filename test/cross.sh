#!/bin/sh
# Prove a pod in one Unum reaches another's app (unifist-unum unless named) by its public name and no port, through the other's ingress:
# <service>.<namespace>.<cluster>.localhost, the name the README gives. Usage: test/cross.sh <from> <to> [app], with both
# clusters up; FROM and TO can be the same cluster. Run it both ways. It's wget, not curl: curl sends every
# *.localhost to 127.0.0.1 itself without asking DNS, so it never uses the CoreDNS rewrite.
set -e

FROM=$1
TO=$2
APP=${3:-unifist-unum}

kubectl --context "kind-$FROM" run "cross-$TO" --rm -i --restart=Never --image=busybox:1.36 --command -- sh -c "
    for i in \$(seq 1 30); do
        wget -q -T 5 -O - http://api.$APP.$TO.localhost/health | grep -q OK &&
        wget -q -T 5 -O - http://gui.$APP.$TO.localhost/api/health | grep -q OK && echo ok && exit 0
        sleep 2
    done
    echo 'api.$APP.$TO.localhost never answered from $FROM'
    exit 1"

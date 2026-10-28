#!/bin/sh
# Prove a browser on this machine reaches a Unum's apps by the same names pods use, on port 80, through the ingress
# cluster that holds the host's ports 80 and 443 (kind-ingress): <service>.<namespace>.<cluster>.localhost.
# Usage: test/browser.sh <cluster>, with the Unum and the ingress cluster up. curl is right here: on the host it sends
# every *.localhost to 127.0.0.1 itself, which is where the ingress cluster listens.
set -e

NAME=$1
APP=unifist-unum

# shellcheck disable=SC2034
for i in $(seq 1 30); do
    if curl -fsS "http://api.$APP.$NAME.localhost/health" | grep -q OK && curl -fsS "http://gui.$APP.$NAME.localhost/api/health" | grep -q OK; then
        echo "api and gui answer at <service>.$APP.$NAME.localhost on port 80"
        exit 0
    fi
    sleep 2
done

echo "api.$APP.$NAME.localhost never answered from this machine"
exit 1

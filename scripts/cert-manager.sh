#!/bin/sh
# Give a Unum cert-manager, its own root authority and the ClusterIssuer named unum that signs with it. Safe to run again.
# Usage: scripts/cert-manager.sh <cluster>
set -e

NAME=$1
CTX=kind-$NAME

test -n "$NAME" || { echo "usage: scripts/cert-manager.sh <cluster>"; exit 1; }

kubectl --context "$CTX" apply --server-side --force-conflicts -k pillars/cert-manager
for deployment in cert-manager cert-manager-cainjector cert-manager-webhook; do
    kubectl --context "$CTX" -n cert-manager rollout status "deployment/$deployment" --timeout=180s
done

sed "s/__NAME__/$NAME/g" pillars/cert-manager/issuers.yaml | kubectl --context "$CTX" apply -f -
kubectl --context "$CTX" -n cert-manager wait --for=condition=Ready certificate/root-ca --timeout=120s
kubectl --context "$CTX" wait --for=condition=Ready clusterissuer/unum --timeout=120s

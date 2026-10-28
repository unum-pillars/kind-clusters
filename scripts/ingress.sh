#!/bin/sh
# Give a Unum its ingress and its names: Traefik on node ports 80 and 443, and CoreDNS answering
# <anything>.<cluster>.localhost with the cluster's node. Safe to run again. Usage: scripts/ingress.sh <cluster>
set -e

CTX=kind-$1

kubectl --context "$CTX" apply --server-side --force-conflicts -k ingress
kubectl --context "$CTX" -n traefik rollout status deployment/traefik --timeout=180s

kubectl --context "$CTX" apply --server-side --force-conflicts -f coredns/coredns.yaml
kubectl --context "$CTX" -n kube-system rollout restart deployment/coredns
kubectl --context "$CTX" -n kube-system rollout status deployment/coredns --timeout=120s

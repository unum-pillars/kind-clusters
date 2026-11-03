#!/bin/sh
# An echo app for the tests that need to see what the ingress passes on: traefik/whoami in the app's namespace, answering with the
# headers it was sent at whoami.<app>.<cluster>.localhost on https, its Ingress taking the same middlewares as the app's api Ingress.
# Usage: test/whoami.sh <cluster> <app> up|down, with the cluster up. Up waits until it's rolled out; down is safe to run again.
set -e

NAME=$1
APP=$2
ACTION=$3
CTX=kind-$NAME
HOST=whoami.$APP.$NAME.localhost

test -n "$NAME" -a -n "$APP" || { echo "usage: test/whoami.sh <cluster> <app> up|down"; exit 1; }

app() {
    kubectl --context "$CTX" -n "$APP" "$@"
}

up() {
    MIDDLEWARES=$(app get ingress api -o 'jsonpath={.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.middlewares}')

    test -n "$MIDDLEWARES" || { echo "the api Ingress of $APP has no middlewares, so it does not pass on who called"; exit 1; }

    app apply -f - > /dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
spec:
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:v1.10.3
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  selector:
    app: whoami
  ports:
  - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  annotations:
    cert-manager.io/cluster-issuer: unum
    traefik.ingress.kubernetes.io/router.middlewares: $MIDDLEWARES
spec:
  tls:
  - hosts:
    - $HOST
    secretName: whoami-tls
  rules:
  - host: $HOST
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: whoami
            port:
              number: 80
EOF

    app rollout status deployment/whoami --timeout=120s > /dev/null
}

case "$ACTION" in
up)
    up
    ;;
down)
    app delete ingress/whoami service/whoami deployment/whoami --ignore-not-found > /dev/null
    ;;
*)
    echo "usage: test/whoami.sh <cluster> <app> up|down"
    exit 1
    ;;
esac

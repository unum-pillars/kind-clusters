#!/bin/sh
# Prove an app sees which Unum is calling, from the common name of the client certificate, and never from a header the caller
# sends: an echo app (whoami) takes the same middlewares as the app's api Ingress, and a pod in the Unum calls it on https with the
# Unum's own client certificate (the header names the Unum first: it lists the certificates it was sent, the Unum's then its root's),
# with none (no header), and with a forged header on https and on http, with and without the certificate (the forgery never gets
# through). Usage: test/caller.sh <cluster> [app], app being unifist-unum unless named, with the cluster up. The pod calls the
# Unum's own node (--connect-to), since curl sends every *.localhost to 127.0.0.1 itself without asking DNS.
set -e

NAME=$1
APP=${2:-unifist-unum}
CTX=kind-$NAME
HOST=whoami.$APP.$NAME.localhost

test -n "$NAME" || { echo "usage: test/caller.sh <cluster> [app]"; exit 1; }

app() {
    kubectl --context "$CTX" -n "$APP" "$@"
}

secret() {
    kubectl --context "$CTX" -n "$1" get secret "$2" -o "jsonpath={.data.$3}" | base64 -d
}

MIDDLEWARES=$(app get ingress api -o 'jsonpath={.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.middlewares}')

test -n "$MIDDLEWARES" || { echo "the api Ingress of $APP has no middlewares, so it does not pass on who called"; exit 1; }

ROOT=$(secret cert-manager root-ca 'tls\.crt')
CLIENT="$(secret cert-manager client 'tls\.crt')
$(secret cert-manager client 'tls\.key')"

gone() {
    app delete ingress/whoami service/whoami deployment/whoami --ignore-not-found > /dev/null
}

gone
trap gone EXIT

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

kubectl --context "$CTX" delete pod "caller-$NAME" --ignore-not-found > /dev/null

# the script is single quoted on purpose: the pod expands it, from the --env values
# shellcheck disable=SC2016
kubectl --context "$CTX" run "caller-$NAME" --rm -i --restart=Never --image=curlimages/curl:8.11.1 \
    --env "ROOT=$ROOT" --env "CLIENT=$CLIENT" --env "NAME=$NAME" --env "HOST=$HOST" --command -- sh -c '
    # kubectl attaches after the pod starts and loses the output of a pod that has already finished, and then exits 0
    sleep 2
    echo "$ROOT" > /tmp/root.crt
    echo "$CLIENT" > /tmp/client.pem
    node=$NAME-control-plane
    forged="X-Forwarded-Tls-Client-Cert-Info: Subject=\"CN=mallory\""

    # what the app was told about the caller: the echoed header, decoded
    told() {
        sed -n "s/^X-Forwarded-Tls-Client-Cert-Info: //p" | sed "s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\\\x\1/g" | while read -r line; do printf "%b\n" "$line"; done
    }

    secure() {
        curl -fsS --cacert /tmp/root.crt --connect-to ::$node:443 "$@" https://$HOST/ 2> /dev/null
    }

    for i in $(seq 1 60); do
        secure | grep -q Hostname && break
        test "$i" -lt 60 || { echo "https://$HOST never answered"; exit 1; }
        sleep 2
    done

    secure --cert /tmp/client.pem | told | grep -q "^Subject=\"CN=$NAME\"" ||
        { echo "$HOST was not told that $NAME called, with its client certificate"; exit 1; }

    test -z "$(secure | told)" ||
        { echo "$HOST was told who called, with no client certificate"; exit 1; }

    secure -H "$forged" | told | grep -q mallory &&
        { echo "$HOST took a forged caller on https, with no client certificate"; exit 1; }

    curl -fsS --connect-to ::$node:80 -H "$forged" http://$HOST/ | told | grep -q mallory &&
        { echo "$HOST took a forged caller on http"; exit 1; }

    secure --cert /tmp/client.pem -H "$forged" | told | grep -q mallory &&
        { echo "$HOST took a forged caller over the real one"; exit 1; }

    echo "$HOST is told that $NAME called with its client certificate, and never from a header the caller sends"'

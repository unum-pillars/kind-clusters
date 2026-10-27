#!/bin/sh
# Prove an Unum cluster runs what its apps.yaml says: every app at its pinned image, answering, with the databases it
# made on first deploy. Usage: test/unum.sh <cluster>, with the cluster up (make ci NAME=<cluster>).
set -e

NAME=$1
CTX=kind-$NAME
APPS=$NAME/apps.yaml

test -f "$APPS" || { echo "$APPS is missing"; exit 1; }

# One "app tag" line per app in apps.yaml.
awk '/^[^ #]/ {app=$1; sub(":", "", app)} /^  tag:/ {print app, $2}' "$APPS" | while read -r app tag; do
    echo "== $app $tag"

    for deployment in $(kubectl --context "$CTX" -n "$app" get deployments -o name); do
        kubectl --context "$CTX" -n "$app" rollout status "$deployment" --timeout=300s

        image=$(kubectl --context "$CTX" -n "$app" get "$deployment" -o jsonpath='{.spec.template.spec.containers[0].image}')
        expected="gaf3/unum-apps-$app-${deployment#deployment.apps/}:$tag"
        test "$image" = "$expected" || { echo "$deployment runs $image, not $expected"; exit 1; }
        echo "$deployment runs $image"
    done

    # The app answers inside the cluster, by its service name.
    kubectl --context "$CTX" run "health-$app" --rm -i --restart=Never --image=busybox:1.36 --command -- sh -c "
        wget -q -T 5 -O - http://api.$app/health | grep -q OK &&
        wget -q -T 5 -O - http://gui.$app/api/health | grep -q OK" || { echo "$app did not answer /health"; exit 1; }
    echo "$app answers"

    # What the app made in the cluster's MySQL on first deploy.
    case $app in
    unifist-unum)
        databases=$(kubectl --context "$CTX" -n mysql exec deployment/mysql -- env MYSQL_PWD=root mysql -uroot -N -e 'SHOW DATABASES')
        for database in unifist unum; do
            echo "$databases" | grep -qx "$database" || { echo "database $database was not made"; exit 1; }
        done
        echo "$app made unifist and unum"
        ;;
    esac
done

echo "ok"

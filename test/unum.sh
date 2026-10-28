#!/bin/sh
# Prove an Unum cluster runs what its apps.yaml says: every app at its pinned image, answering, with the databases it
# made on first deploy. Usage: test/unum.sh <cluster>, with the cluster up (make ci NAME=<cluster>).
set -e

NAME=$1
CTX=kind-$NAME
APPS=$NAME/apps.yaml

test -f "$APPS" || { echo "$APPS is missing"; exit 1; }

# The ingress every Unum has: Traefik up, its Service on node ports 80 and 443.
kubectl --context "$CTX" -n traefik rollout status deployment/traefik --timeout=180s
ports=$(kubectl --context "$CTX" -n traefik get service traefik -o jsonpath='{range .spec.ports[*]}{.nodePort} {end}')
test "$ports" = "80 443 " || { echo "traefik is on node ports $ports, not 80 443"; exit 1; }
echo "traefik answers on node ports 80 and 443"

# One "app source value" line per app in apps.yaml, the source being tag, hash or checkout.
awk '/^[^ #]/ {app=$1; sub(":", "", app)} /^  (tag|hash|checkout):/ {source=$1; sub(":", "", source); print app, source, $2}' "$APPS" |
while read -r app source value; do
    echo "== $app $source $value"

    for deployment in $(kubectl --context "$CTX" -n "$app" get deployments -o name); do
        kubectl --context "$CTX" -n "$app" rollout status "$deployment" --timeout=300s

        image=$(kubectl --context "$CTX" -n "$app" get "$deployment" -o jsonpath='{.spec.template.spec.containers[0].image}')
        part=${deployment#deployment.apps/}

        # A tag or a hash is the published image at that tag or the hash's first 7 characters; a checkout is built here by Tilt.
        case $source in
        tag) expected="gaf3/unum-apps-$app-$part:$value" ;;
        hash) expected="gaf3/unum-apps-$app-$part:$(echo "$value" | cut -c1-7)" ;;
        checkout) expected="unum-apps-$app-$part:tilt-*" ;;
        esac

        # shellcheck disable=SC2254
        case $image in
        $expected) echo "$deployment runs $image" ;;
        *) echo "$deployment runs $image, not $expected"; exit 1 ;;
        esac
    done

    # Every Service has an Ingress at <service>.<namespace>.<cluster>.localhost.
    for service in $(kubectl --context "$CTX" -n "$app" get services -o name | sed 's|service/||' | grep -v -- '-node$'); do
        host="$service.$app.$NAME.localhost"
        kubectl --context "$CTX" -n "$app" get ingress "$service" -o jsonpath='{.spec.rules[0].host}' | grep -qx "$host" ||
            { echo "no ingress for $host"; exit 1; }
        echo "$service is at $host"
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

        # A browser reaches the GUI on this Unum's host port, see the port table in the README.
        port=$(awk '/hostPort:/ {print $2}' "$NAME/kind.yaml")
        curl -fsS "http://localhost:$port/api/health" | grep -q OK || { echo "the GUI did not answer on localhost:$port"; exit 1; }
        echo "$app GUI answers on localhost:$port"
        ;;
    cumulus)
        databases=$(kubectl --context "$CTX" -n mysql exec deployment/mysql -- env MYSQL_PWD=root mysql -uroot -N -e 'SHOW DATABASES')
        echo "$databases" | grep -qx cumulus || { echo "database cumulus was not made"; exit 1; }
        echo "$app made cumulus"

        # The config it reads is this Unum's: the routed source's own arguments.
        kubectl --context "$CTX" -n "$app" get configmap config -o jsonpath='{.data.unum\.json}' | grep -q "\"unum\": \"$NAME\"" ||
            { echo "cumulus config is not for $NAME"; exit 1; }

        # And it routed its data here: a Route row for this Unum's cumulus, which unifist-unum made the table for.
        routes=$(kubectl --context "$CTX" -n mysql exec deployment/mysql -- env MYSQL_PWD=root mysql -uroot -N -e \
            "SELECT COUNT(*) FROM unum.route WHERE unum = '$NAME' AND source = 'cumulus' AND role = 'owner'")
        test "$routes" = 1 || { echo "cumulus has $routes owner routes for $NAME, not 1"; exit 1; }
        echo "$app routes its data to $NAME"
        ;;
    esac
done

echo "ok"

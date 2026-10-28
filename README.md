# kind-clusters
Listing of different clusters so spin up to use for Unum testing

One folder per cluster:

- `us/`
- `them/`

`we/` comes later, a third unum apart from these two. A cluster folder holds `kind.yaml` for the cluster and a
`kustomization.yaml` listing what runs in it, picked from the shared folders:

- `mysql/`: MySQL at `mysql.mysql:3306`, root/root.
- `redis/`: Redis at `redis.redis:6379`, no password, append-only.

Local dev only, the password is public on purpose.

## An Unum cluster

A cluster is the pillars above plus the apps in its `apps.yaml`, each pinned to a tag:

    unifist-unum:
      tag: 0.1.0

The tag is the app's git tag and its Docker Hub image tag (`gaf3/unum-apps-<app>`), so it pins the app's YAML and its
image together. `apps/<app>/glue.yaml` holds what the app needs around it that its own YAML doesn't carry, its namespace
and the secret that points it at the cluster's MySQL. `us/` and `them/` both run `unifist-unum` at 0.1.0, from tags only; hashes and checkouts come next (#3).

    make up   NAME=us   # make the cluster if it's missing, then tilt up: everything pinned in us/apps.yaml
    make ci   NAME=us   # the same, but wait until every workload is healthy and stop
    make test NAME=us   # prove it: pinned images, /health answers, the databases the app made
    make down NAME=us   # delete the cluster, its data in data/us stays

    make test-cross FROM=us TO=them   # each reaches the other's API from a pod, both ways

Needs Tilt too: `make setup` installs it.

### Calling between Unums

Server to server goes by node name and NodePort, not ingress. A kind node's container is named `<cluster>-control-plane`
on the shared `kind` Docker network, so a pod in `us` calls `http://them-control-plane:30465/health`. An app that can be
called from another Unum has a `NodePort` Service in its `apps/<app>/glue.yaml`, on a fixed port from this table so no
two clash:

| Port  | App                     |
|-------|-------------------------|
| 30465 | `unifist-unum` API      |

## Use

From the directory you want the data in (it goes in `data/<name>`):

    kind create cluster --name us --config us/kind.yaml
    kubectl --context kind-us apply -k us

Once, to install kind, kubectl and Docker Desktop:

    make setup

From another repo, the services can be referenced from a `kustomization.yaml`:

    resources:
    - github.com/unum-pillars/kind-clusters/us?ref=main

The cluster itself is made with `kind create cluster` as above, since kustomize can't make it.

## Test

Throwaway apps in `test/` do what an app does on first deploy: create their database, write a row, count a visit in
Redis. Run them twice, across deleting and recreating the cluster, and `rows=` and `visits=` climb.

    kubectl --context kind-us apply -f test/data.yaml -f test/cache.yaml
    kubectl --context kind-us logs job/data job/cache

## Lint

    make lint

Offline, only Docker needed: every `kustomization.yaml` builds, `test/*.sh` passes shellcheck, and the YAML passes
yamllint (`.yamllint`). Jenkins runs it on every push. It doesn't cover the Tiltfiles or anything that needs a cluster,
so run `make ci`, `make test` and `make test-cross` yourself before merging.

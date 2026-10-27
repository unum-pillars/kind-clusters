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

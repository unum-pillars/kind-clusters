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

A cluster is the pillars above plus the apps in its `apps.yaml`. Each app comes from one of three places:

    unifist-unum:
      tag: 0.1.0                              # the app's YAML at git tag 0.1.0, its image gaf3/unum-apps-unifist-unum-<part>:0.1.0

    unifist-unum:
      hash: 414f9ac                           # a commit on the app's main: its YAML there, its image at the hash's first 7 characters

    unifist-unum:
      checkout: ../../unum-apps/unifist-unum  # the repo on disk, built and run in place by Tilt, from here or an absolute path

A tag is the app's git tag and its Docker Hub image tag, so it pins the YAML and the image together. A hash has to be a
commit on `main`, since that is all Jenkins publishes images for; code on a branch is a checkout. A checkout runs the
repo's own `kubernetes/tilt` YAML, with its images built from the repo and loaded into the cluster, so changes to the
code show up live while Tilt runs. Every app gets its namespace and the `secret` that points it at the cluster's MySQL
from `unum.star`, the same whichever the source. What only some apps have, like NodePorts, is in `apps/<app>/extra.yaml`.

    make up   NAME=us   # make the cluster if it's missing, then tilt up: everything in us/apps.yaml
    make ci   NAME=us   # the same, but wait until every workload is healthy and stop
    make test NAME=us   # prove it: the images, /health answers, the databases the app made, the GUI on its host port
    make down NAME=us   # delete the cluster, its data in data/us stays

    make test-cross FROM=us TO=them   # each reaches the other's API from a pod, both ways

Needs Tilt too: `make setup` installs it.

### Choosing apps

The apps there could be are the repos of the `unum-apps` org, and their versions are those repos' tags:

    make catalog                                           # every repo with its tags (needs gh)
    make add NAME=us APP=ledger TAG=0.1.5                  # writes it into us/apps.yaml
    make add NAME=us APP=ledger HASH=1270925
    make add NAME=us APP=ledger CHECKOUT=../../unum-apps/ledger

`make add` changes the app's line if it's there and appends one if it isn't. An app that's already running is moved by
taking it down, changing its line and bringing it up: its data is in MySQL and Redis, which stay.

    kubectl --context kind-us delete namespace unifist-unum
    make add NAME=us APP=unifist-unum CHECKOUT=../../unum-apps/unifist-unum
    make up NAME=us

### Calling between Unums

Server to server goes by node name and NodePort, not ingress. A kind node's container is named `<cluster>-control-plane`
on the shared `kind` Docker network, so a pod in `us` calls `http://them-control-plane:30465/health`. An app that can be
called from another Unum has a `NodePort` Service in its `apps/<app>/extra.yaml`, on a fixed port from this table so no
two clash:

| Port  | App                     |
|-------|-------------------------|
| 30465 | `unifist-unum` API      |
| 30466 | `unifist-unum` GUI      |

### Browsers

A browser reaches an app's GUI through a NodePort that the cluster's `kind.yaml` maps to a port on the host, 127.0.0.1
only. Each Unum has its own host port, so `us` and `them` can be up together:

| Cluster | `unifist-unum` GUI      |
|---------|-------------------------|
| `us`    | http://localhost:5465   |
| `them`  | http://localhost:5466   |

Changing a mapping means recreating the cluster (`make down`, `make up`); its data stays. Ingress is not part of this: only
one cluster can hold the host's 80 and 443, so it is left to kind-ingress.

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
    make test-add

Offline, only Docker needed: every `kustomization.yaml` builds, `test/*.sh` and `scripts/*.sh` pass shellcheck, and the
YAML passes yamllint (`.yamllint`); `test-add` proves `scripts/add.sh`. Jenkins runs both on every push. It doesn't cover the Tiltfiles or anything that needs a cluster,
so run `make ci`, `make test`, `make test-cross` and, for anything about where an app comes from, `make test-swap` and
`make test-catalog` yourself before merging.

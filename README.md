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
from `unum.star`, the same whichever the source. What only some apps have, like a NodePort for browsers, is in
`apps/<app>/extra.yaml`.

    make up   NAME=us   # make the cluster if it's missing, then tilt up: everything in us/apps.yaml
    make ci   NAME=us   # the same, but wait until every workload is healthy and stop
    make test NAME=us   # prove it: the ingress, the images, the names, /health answers, the databases, the GUI on its host port
    make down NAME=us   # delete the cluster, its data in data/us stays

    make test-cross FROM=us TO=them   # each reaches the other, and itself, by name and no port
    make test-browser NAME=us         # this machine reaches it by name on port 80, the ingress cluster up

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

### Names

Every Unum runs an ingress (Traefik, from kind-ingress, pinned in `ingress/`) on its node's ports 80 and 443. Every
Service of every app gets an Ingress at

    <service>.<namespace>.<cluster>.localhost

made by `unum.star`, whichever way the app comes in. CoreDNS in each Unum sends any `<name>.<cluster>.localhost` to
`<cluster>-control-plane`, the kind node's container name on the shared `kind` Docker network. So a pod in `us` calls

    http://api.unifist-unum.them.localhost/health

with no port, and a pod in `us` calls its own cluster's apps the same way. One rule covers `us`, `them` and `we` later.
Server to server, a Route's url is that name. Use `wget`, not `curl`, to try it in a pod: curl sends every `*.localhost`
to 127.0.0.1 itself, without asking DNS. The node ports go down to 80 because each cluster's `kind.yaml` widens the range
when it is made; an existing cluster has to be deleted and made again (its data stays).

### Browsers

The same names work in a browser on your Mac, on port 80. The ingress cluster from
[kind-ingress](https://github.com/gaf3/kind-ingress) holds the host's ports 80 and 443 and sends everything under
`*.<cluster>.localhost` to that Unum's node, where the Unum's own ingress takes it. `make up` sets the route (see
`route/route.yaml`) when an ingress cluster exists, and says so when it doesn't. So with both up,

    http://gui.unifist-unum.us.localhost/

is the GUI of `us`. `make test-browser NAME=us` proves it from the host. Without an ingress cluster a Unum's GUI is still on
its own host port, `us` on http://localhost:5465 and `them` on http://localhost:5466, a NodePort that the cluster's
`kind.yaml` maps to the host, 127.0.0.1 only.

### Calling without the ingress

An app that can be called by node name and NodePort has a `NodePort` Service in its `apps/<app>/extra.yaml`, on a fixed
port from this table so no two clash. A pod in `us` can call `http://them-control-plane:30465/health`.

| Port  | App                     |
|-------|-------------------------|
| 30465 | `unifist-unum` API      |
| 30466 | `unifist-unum` GUI      |

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

Only Docker and the network needed (`ingress/` pulls kind-ingress from GitHub): every `kustomization.yaml` builds, `test/*.sh` and `scripts/*.sh` pass shellcheck, and the
YAML passes yamllint (`.yamllint`); `test-add` proves `scripts/add.sh`. Jenkins runs both on every push. It doesn't cover the Tiltfiles or anything that needs a cluster,
so run `make ci`, `make test`, `make test-cross` and, for anything about where an app comes from, `make test-swap` and
`make test-catalog` yourself before merging.

# kind-clusters
Listing of different clusters so spin up to use for Unum testing

Plain kind clusters for Unum testing, each with a data directory on the host and a MySQL and a redis.

## Clusters

- `us`
- `them`

`we` comes later, a third unum apart from these two.

## Use

    make setup                    # install kind, kubectl and Docker Desktop, safe to run again
    make all                      # us and them
    make cluster NAME=us          # kind cluster + MySQL + redis, safe to run again
    make down    NAME=us          # delete the cluster, keep its data
    make wipe    NAME=us          # delete its data too, refuses while the cluster is up
    make test-data    NAME=us     # throwaway apps create their database and count a visit in redis
    make test-persist NAME=us     # same, across deleting and recreating the cluster (wipes the data first)

## In each cluster

- MySQL at `mysql.mysql:3306`, root/root. Apps create their own databases on first deploy.
- Redis at `redis.redis:6379`, no password, append-only.

Nothing here knows about apps. Local dev only, the password is public on purpose.

## Data

Each cluster's data is `~/.kind-data/<name>` on the host, mounted into the node at `/data` (`mysql/`, `redis/`). The
cluster owns that directory. The mount only happens when a cluster is made, so a cluster made before this has to be
deleted and made again.

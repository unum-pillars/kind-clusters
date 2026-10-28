# Changelog

## 0.1.0

- Unum clusters, `us` and `them`, each a kind cluster with the pillars (MySQL at `mysql.mysql:3306`, Redis at `redis.redis:6379`) and the apps in its `apps.yaml`. `make up`, `make ci`, `make test` and `make down` bring one up, prove it and delete it, its data in `data/<name>` staying.
- An app comes from a `tag` (its YAML at the git tag and its Docker Hub image at the tag), a `hash` (a commit on its main) or a `checkout` (the repo on disk, run live by Tilt). `make catalog` lists the apps there could be and `make add` puts one in a Unum's `apps.yaml`.
- Names, no ports: every Unum runs Traefik (from kind-ingress) and every Service of every app is at `<service>.<namespace>.<cluster>.localhost`. CoreDNS in each Unum sends `*.<cluster>.localhost` to the Unum's node, so a pod in one Unum calls another's apps the same way, and the permanent ingress cluster routes the same names to a browser on the host.
- `unifist-unum` and `cumulus` run in both Unums, `unifist-unum` first, and an app that mounts a ConfigMap named `config` gets the `unum.json` of its Unum.
- `make lint` builds every kustomization, shellchecks the scripts and yamllints; `make test-add` proves `scripts/add.sh`; Jenkins runs both. `make test-cross`, `make test-browser`, `make test-swap` and `make test-catalog` run against live clusters, by hand.
- A version, `VERSION` and this changelog, `make tag`, and Jenkins tags the version on main, so other repos can reference `github.com/unum-pillars/kind-clusters/us?ref=<version>` (unum-pillars/kind-clusters#15).

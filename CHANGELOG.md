# Changelog

## 0.2.0

- Joined Unums: `make join A=us B=them` puts a Route row in each Unum's `unum.route` for the other (the records whose `home` is the other, owned by it as `holder`, at its cumulus api by name, no port), through unifist-unum's REST, safe to run again. `make test-route` proves a cumulus record made in one is read from the other once, with the id of the Unum that made it and held only there, that neither sees the other's before they are joined, that records made in both Unums come back merged in order (and in reverse) from either side, and that a read of everything answers 200 within 5 seconds, so joined Unums asking each other for ever would fail it (unum-pillars/kind-clusters#13).
- Jenkins brings up `us` and `them` on the agent from their `apps.yaml` tags and proves them: a `clusters` stage runs `make ci` and `make test` for each, then `make test-cross` and `make test-route`, and deletes the clusters and their databases after. `scripts/tools.sh` puts `kind`, `kubectl` and `tilt` (pinned) in `bin/` when the agent doesn't have them. `make test-browser`, `make test-swap` and `make test-catalog` are still run by hand.
- A record's `unum` field is `home` (relations-unifist 0.5.0, relations-unum 0.5.0, unifist-unum 0.2.0, cumulus 0.2.0), so `test/unum.sh` counts cumulus's owner Route by `home`, and `us` and `them` run `unifist-unum` and `cumulus` at 0.2.0 (relations-dil/python-relations-unifist#17).

## 0.1.0

- Unum clusters, `us` and `them`, each a kind cluster with the pillars (MySQL at `mysql.mysql:3306`, Redis at `redis.redis:6379`) and the apps in its `apps.yaml`. `make up`, `make ci`, `make test` and `make down` bring one up, prove it and delete it, its data in `data/<name>` staying.
- An app comes from a `tag` (its YAML at the git tag and its Docker Hub image at the tag), a `hash` (a commit on its main) or a `checkout` (the repo on disk, run live by Tilt). `make catalog` lists the apps there could be and `make add` puts one in a Unum's `apps.yaml`.
- Names, no ports: every Unum runs Traefik (from kind-ingress) and every Service of every app is at `<service>.<namespace>.<cluster>.localhost`. CoreDNS in each Unum sends `*.<cluster>.localhost` to the Unum's node, so a pod in one Unum calls another's apps the same way, and the permanent ingress cluster routes the same names to a browser on the host.
- `unifist-unum` and `cumulus` run in both Unums, `unifist-unum` first, and an app that mounts a ConfigMap named `config` gets the `unum.json` of its Unum.
- `make lint` builds every kustomization, shellchecks the scripts and yamllints; `make test-add` proves `scripts/add.sh`; Jenkins runs both. `make test-cross`, `make test-browser`, `make test-swap` and `make test-catalog` run against live clusters, by hand.
- A version, `VERSION` and this changelog, `make tag`, and Jenkins tags the version on main, so other repos can reference `github.com/unum-pillars/kind-clusters/us?ref=<version>` (unum-pillars/kind-clusters#15).

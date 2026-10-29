# Changelog

## 0.2.7

- Each Unum has cert-manager, its own self-signed root authority (named for the Unum, valid ten years) and the ClusterIssuer `unum` that signs with that root, so a Unum can issue certificates. `scripts/cert-manager.sh` applies cert-manager v1.21.3 server side (its CRDs are too big for a client side apply), waits for it, then the root and the issuer; Tilt runs it as the `cert-manager` resource. `make test-certificates NAME=us` proves it by asking for a certificate from `unum` and checking, with openssl in a container, that it is signed by the Unum's root, and Jenkins runs it in each Unum's lane after `make test`. The root is made in the cluster for now, so a rebuilt cluster gets a new one; keeping its key outside the cluster comes later (unum-pillars/unum#3).
- The folders are organized: `pillars/` holds what apps use (`mysql/`, `redis/` and `cert-manager/`) and `clusters/` holds `us/` and `them/`. `ingress/`, `coredns/` and `route/` are plumbing and stay at the root with `apps/`, `scripts/`, `test/` and `data/`. The commands are the same (`make up NAME=us`); `NAME` is still the cluster's name, and `checkout:` paths in `apps.yaml` are still from the repo root (unum-pillars/kind-clusters#29).

## 0.2.6

- `unifist-unum` and `cumulus` are pinned at `0.2.1` in `us/apps.yaml` and `them/apps.yaml`, which have relations-unifist 0.6.0 and relations-unum 0.6.0, so a record's title reads `Full Name (handle)`, with `@home` when it is from another Unum (unum-pillars/kind-clusters#27, unum-apps/unifist-unum#12).

## 0.2.5

- The `tag` stage reads the repo's URL with `git remote get-url origin` instead of `$GIT_URL`. `checkout scm` as a step (since `clone` became its own stage) leaves `GIT_URL` unset in the shell, so the remote became `https://admin:****@` and the push failed with `unable to access 'https:///'`, and `0.2.2`, `0.2.3` and `0.2.4` were never tagged. `make test-stages` fails if the Jenkinsfile uses `GIT_URL` again (unum-pillars/kind-clusters#25).

## 0.2.4

- The Jenkinsfile groups its stages by function and has one step for each make command, so the graph is four bubbles and a pair of lanes, and each command is its own collapsible row with its own status, time and log: `clone` (the clean, then the checkout), `within` (`lint`, `test-add`, `test-version`, `test-context`, `test-stages` and `tools`), `clusters` (an `us` and a `them` lane side by side, each `down`, `ci` and `test`, then `across` with `test-cross`, `test-route` and `test-write`) and `tag`. `make test-stages` proves the stages and the order of the make commands, and that nothing else is run but the clean, the cleanup and the tag (unum-pillars/kind-clusters#23).
- The clean runs before the checkout and removes `data/` with a docker run, and the checkout is a step of its own (`skipDefaultCheckout`). The clusters' databases are root's, and a run that was stopped before its cleanup left them behind, so the next checkout's `git clean` failed with `Permission denied` and `main` could not build. Whatever happened last time, the workspace is now cleaned first.

## 0.2.3

- `make test-write` proves the one-writer half of writes across joined Unums: the owner of a record creates, updates and deletes it, and the other Unum reads each change at once, with one version bump and one journal entry for each write, and no copy kept in the other. Each Unum takes a turn as the owner. Jenkins runs it as its own stage after `test-route`. A write from a Unum that doesn't own the record is not covered, since it isn't supported yet: it lands in the owner but bumps the version twice and journals twice (unum-pillars/kind-clusters#18, relations-dil/python-relations-unifist#19).

## 0.2.2

- The Jenkinsfile is one-for-one: every stage runs exactly one make command, so a red bubble is one act, in one Unum, and nothing else. The checks are `test-add`, `test-version`, `test-context` and `test-stages`; the `clusters` stage is `tools`, then `unums` with an `us` and a `them` lane side by side, each `down`, `up` and `test`, then `test-cross` and `test-route`. `make tools` runs `scripts/tools.sh`. `make test-stages` proves the stage shape and that no stage runs two commands, and Jenkins runs it (unum-pillars/kind-clusters#20).

## 0.2.1

- `make up` and `make ci` name their cluster in the call (`tilt --context kind-<name>`) and nothing switches the kubectl context any more, so two Unums can come up at once (`make ci` also runs Tilt without its web UI, since two Tilts can't share its port). `make test-context` proves it, and Jenkins runs it. The guard in `unum.star` still checks that Tilt is on `kind-<name>`, and its message says to run it with `--context`.
- The Jenkins `clusters` stage runs `us` and `them` in parallel, each `make ci` then `make test`, and then `make test-cross` and `make test-route` once both are up (unum-pillars/kind-clusters#17).

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

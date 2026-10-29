# Install what the clusters need with Homebrew: kind, kubectl, and Docker Desktop to run them. Safe to run again. Docker
# Desktop has to be started once by hand after it's installed.
setup: ## Installs kind, kubectl, tilt and Docker Desktop with Homebrew
	command -v brew >/dev/null || { echo "Homebrew is needed first: https://brew.sh"; exit 1; }
	command -v kind >/dev/null || brew install kind
	command -v kubectl >/dev/null || brew install kubectl
	command -v tilt >/dev/null || brew install tilt
	command -v docker >/dev/null || brew install --cask docker
	docker info >/dev/null 2>&1 || { echo "Docker is installed but not running: start Docker Desktop, then make setup again"; exit 1; }
	@echo "ok"

VERSION?=$(shell cat VERSION)

.PHONY: setup lint cluster up ci test test-cross test-route test-write join test-browser test-swap test-add test-catalog test-version test-context test-stages catalog add down tools tag untag help
.DEFAULT_GOAL := help

# The Unum's kind cluster, made if it's missing, its data in data/$(NAME) here. Safe to run again. Every call names its cluster
# (kind-$(NAME)) and none switches the kubectl context, so two Unums can come up at once.
cluster: ## Makes the Unum cluster NAME if it is missing
	test -f $(NAME)/kind.yaml
	mkdir -p data/$(NAME)
	kind get clusters | grep -qx $(NAME) || kind create cluster --name $(NAME) --config $(NAME)/kind.yaml

# Bring the Unum up and keep Tilt running, or (ci) wait until everything is ready and stop.
up: cluster ## Brings the Unum NAME up and keeps Tilt running
	tilt up --context kind-$(NAME) -f $(NAME)/Tiltfile

ci: cluster ## Brings the Unum NAME up, waits until everything is healthy, and stops
	tilt ci --context kind-$(NAME) --port 0 -f $(NAME)/Tiltfile --timeout 15m

# Prove the running Unum is what its apps.yaml says.
test: ## Proves the running Unum NAME is what its apps.yaml says
	test/unum.sh $(NAME)

# Prove each of FROM and TO reaches the other's unifist-unum, and its own, by name and no port, both clusters up.
APPS?=unifist-unum cumulus
FROM?=us
TO?=them
test-cross: ## Proves FROM and TO reach each other, and themselves, by name and no port
	for app in $(APPS); do test/cross.sh $(FROM) $(TO) $$app && test/cross.sh $(TO) $(FROM) $$app && \
	test/cross.sh $(FROM) $(FROM) $$app && test/cross.sh $(TO) $(TO) $$app || exit 1; done

# Join two Unums: a Route row in each for the other, at its cumulus api by name. Safe to run again. Both up.
A?=us
B?=them
join: ## Joins the Unums A and B with a Route row each, safe to run again
	scripts/join.sh $(A) $(B)

# Prove A and B read each other's cumulus records once they're joined, and not before; it takes the join away first and puts it back.
test-route: ## Proves the Unums A and B read each other's cumulus records once joined, and not before
	test/route.sh $(A) $(B)

# Prove the owner of a record writes it, and the other Unum reads each change at once, with one version bump and one journal entry each.
test-write: ## Proves the owner writes a record and the other Unum A or B reads each change, joined
	test/write.sh $(A) $(B)

# Prove a browser on this machine reaches the Unum NAME by name on port 80, through the ingress cluster being up.
test-browser: ## Proves the Unum NAME answers by name on port 80 from this machine, the ingress cluster up
	for app in $(APPS); do test/browser.sh $(NAME) $$app || exit 1; done

# Prove an app can move between sources and keep its data, slow: make test-swap NAME=us APP=unifist-unum HASH=414f9ac, HASH
# being a commit on the app's main and CHECKOUT (../../unum-apps/<app> unless given) its repo on disk.
HASH?=
CHECKOUT?=../../unum-apps/$(APP)
test-swap: ## Proves APP moves from tag to HASH to CHECKOUT and back, keeping its data (slow)
	test -n "$(APP)" -a -n "$(HASH)"
	test/swap.sh $(NAME) $(APP) $(HASH) $(CHECKOUT)

# Prove scripts/add.sh offline, and scripts/catalog.sh against GitHub (needs gh).
test-add: ## Proves scripts/add.sh, offline
	test/add.sh

test-catalog: ## Proves scripts/catalog.sh against GitHub
	test/catalog.sh

test-version: ## Proves VERSION is x.y.z and CHANGELOG.md starts at it
	test/version.sh

test-context: ## Proves make up and make ci name their cluster and nothing switches the kubectl context
	test/context.sh

test-stages: ## Proves the Jenkinsfile has up and test as stages inside each Unum lane
	test/stages.sh

# The apps there could be, then pick one for a Unum. To move an app that's running, take it down first
# (kubectl --context kind-$(NAME) delete namespace $(APP), its data is in MySQL and Redis and stays), then make add, then make up.
TAG?=
catalog: ## Lists the unum-apps repos with their tags
	scripts/catalog.sh

add: ## Puts APP in NAME/apps.yaml from TAG, HASH or CHECKOUT
	test -n "$(APP)" -a -n "$(NAME)"
	scripts/add.sh $(NAME)/apps.yaml $(APP) $(if $(TAG),tag $(TAG),$(if $(HASH),hash $(HASH),checkout $(CHECKOUT)))

# Put kind, kubectl and tilt in bin/ when the machine has none, as the Jenkins agent has none. Pinned to what the clusters are tested with.
tools: ## Puts kind, kubectl and tilt in bin/ when they are missing
	scripts/tools.sh

# Delete the cluster. Its data in data/$(NAME) stays.
down: ## Deletes the cluster NAME, its data stays
	kind delete cluster --name $(NAME)

# Tag the version and push the tag so others can use ?ref=$(VERSION), doing nothing if it is already there.
tag: ## Tags VERSION and pushes the tag, doing nothing if it is already there
	git ls-remote --exit-code --tags origin $(VERSION) > /dev/null 2>&1 || { \
	git rev-parse -q --verify refs/tags/$(VERSION) > /dev/null || git tag -a $(VERSION) -m "Version $(VERSION)"; \
	git push origin $(VERSION); }

untag: ## Removes the tag of VERSION here and on origin
	-git tag -d $(VERSION)
	git push origin ":refs/tags/$(VERSION)"

# Checks that need only Docker and the network (ingress/ pulls kind-ingress): every kustomization builds, the shell scripts are clean, the YAML is tidy. It does
# not cover the Tiltfiles or anything that needs a live cluster; those are make ci, test and test-cross by hand.
KUSTOMIZE=registry.k8s.io/kustomize/kustomize:v5.7.1
SHELLCHECK=koalaman/shellcheck:v0.10.0
YAMLLINT=pipelinecomponents/yamllint:0.35.8
lint: ## Builds the kustomizations, shellchecks the scripts, yamllints, in Docker
	for dir in $$(find . -name kustomization.yaml -not -path './data/*' -not -path './.git/*' -exec dirname {} \; | sort); do \
	echo "kustomize $$dir"; docker run --rm -v "$$PWD:/work:ro" -w /work $(KUSTOMIZE) build $$dir >/dev/null || exit 1; done
	scripts=$$(find test scripts -name '*.sh' | sort); test -z "$$scripts" || docker run --rm -v "$$PWD:/work:ro" -w /work $(SHELLCHECK) $$scripts
	docker run --rm -v "$$PWD:/work:ro" -w /work $(YAMLLINT) yamllint --strict .
	@echo "ok"

help: ## Lists the targets
	@awk -F ':.*## ' '/^[a-z-]+:.*## /{printf "%-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

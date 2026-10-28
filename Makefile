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

.PHONY: setup lint cluster up ci test test-cross test-swap test-add test-catalog catalog add down help
.DEFAULT_GOAL := help

# The Unum's kind cluster, made if it's missing, its data in data/$(NAME) here. Safe to run again.
cluster: ## Makes the Unum cluster NAME if it is missing
	test -f $(NAME)/kind.yaml
	mkdir -p data/$(NAME)
	kind get clusters | grep -qx $(NAME) || kind create cluster --name $(NAME) --config $(NAME)/kind.yaml
	kubectl config use-context kind-$(NAME)

# Bring the Unum up and keep Tilt running, or (ci) wait until everything is ready and stop.
up: cluster ## Brings the Unum NAME up and keeps Tilt running
	tilt up -f $(NAME)/Tiltfile

ci: cluster ## Brings the Unum NAME up, waits until everything is healthy, and stops
	tilt ci -f $(NAME)/Tiltfile --timeout 15m

# Prove the running Unum is what its apps.yaml says.
test: ## Proves the running Unum NAME is what its apps.yaml says
	test/unum.sh $(NAME)

# Prove each of FROM and TO reaches the other's unifist-unum API by node name and NodePort, both clusters up.
FROM?=us
TO?=them
test-cross: ## Proves FROM and TO reach each other by node name and NodePort
	test/cross.sh $(FROM) $(TO)
	test/cross.sh $(TO) $(FROM)

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

# The apps there could be, then pick one for a Unum. To move an app that's running, take it down first
# (kubectl --context kind-$(NAME) delete namespace $(APP), its data is in MySQL and Redis and stays), then make add, then make up.
TAG?=
catalog: ## Lists the unum-apps repos with their tags
	scripts/catalog.sh

add: ## Puts APP in NAME/apps.yaml from TAG, HASH or CHECKOUT
	test -n "$(APP)" -a -n "$(NAME)"
	scripts/add.sh $(NAME)/apps.yaml $(APP) $(if $(TAG),tag $(TAG),$(if $(HASH),hash $(HASH),checkout $(CHECKOUT)))

# Delete the cluster. Its data in data/$(NAME) stays.
down: ## Deletes the cluster NAME, its data stays
	kind delete cluster --name $(NAME)

# Offline checks, only Docker needed: every kustomization builds, the shell scripts are clean, the YAML is tidy. It does
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

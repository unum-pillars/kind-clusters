# Install what the clusters need with Homebrew: kind, kubectl, and Docker Desktop to run them. Safe to run again. Docker
# Desktop has to be started once by hand after it's installed.
setup:
	command -v brew >/dev/null || { echo "Homebrew is needed first: https://brew.sh"; exit 1; }
	command -v kind >/dev/null || brew install kind
	command -v kubectl >/dev/null || brew install kubectl
	command -v tilt >/dev/null || brew install tilt
	command -v docker >/dev/null || brew install --cask docker
	docker info >/dev/null 2>&1 || { echo "Docker is installed but not running: start Docker Desktop, then make setup again"; exit 1; }
	@echo "ok"

.PHONY: setup lint cluster up ci test test-cross down

# The Unum's kind cluster, made if it's missing, its data in data/$(NAME) here. Safe to run again.
cluster:
	test -f $(NAME)/kind.yaml
	mkdir -p data/$(NAME)
	kind get clusters | grep -qx $(NAME) || kind create cluster --name $(NAME) --config $(NAME)/kind.yaml
	kubectl config use-context kind-$(NAME)

# Bring the Unum up and keep Tilt running, or (ci) wait until everything is ready and stop.
up: cluster
	tilt up -f $(NAME)/Tiltfile

ci: cluster
	tilt ci -f $(NAME)/Tiltfile --timeout 15m

# Prove the running Unum is what its apps.yaml says.
test:
	test/unum.sh $(NAME)

# Prove each of FROM and TO reaches the other's unifist-unum API by node name and NodePort, both clusters up.
FROM?=us
TO?=them
test-cross:
	test/cross.sh $(FROM) $(TO)
	test/cross.sh $(TO) $(FROM)

# Delete the cluster. Its data in data/$(NAME) stays.
down:
	kind delete cluster --name $(NAME)

# Offline checks, only Docker needed: every kustomization builds, the shell scripts are clean, the YAML is tidy. It does
# not cover the Tiltfiles or anything that needs a live cluster; those are make ci, test and test-cross by hand.
KUSTOMIZE=registry.k8s.io/kustomize/kustomize:v5.7.1
SHELLCHECK=koalaman/shellcheck:v0.10.0
YAMLLINT=pipelinecomponents/yamllint:0.35.8
lint:
	for dir in $$(find . -name kustomization.yaml -not -path './data/*' -not -path './.git/*' -exec dirname {} \; | sort); do \
	echo "kustomize $$dir"; docker run --rm -v "$$PWD:/work:ro" -w /work $(KUSTOMIZE) build $$dir >/dev/null || exit 1; done
	scripts=$$(find test -name '*.sh' | sort); test -z "$$scripts" || docker run --rm -v "$$PWD:/work:ro" -w /work $(SHELLCHECK) $$scripts
	docker run --rm -v "$$PWD:/work:ro" -w /work $(YAMLLINT) yamllint --strict .
	@echo "ok"

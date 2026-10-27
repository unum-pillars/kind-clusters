# Install what the clusters need with Homebrew: kind, kubectl, and Docker Desktop to run them. Safe to run again. Docker
# Desktop has to be started once by hand after it's installed.
setup:
	command -v brew >/dev/null || { echo "Homebrew is needed first: https://brew.sh"; exit 1; }
	command -v kind >/dev/null || brew install kind
	command -v kubectl >/dev/null || brew install kubectl
	command -v docker >/dev/null || brew install --cask docker
	docker info >/dev/null 2>&1 || { echo "Docker is installed but not running: start Docker Desktop, then make setup again"; exit 1; }
	@echo "ok"

.PHONY: lint

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

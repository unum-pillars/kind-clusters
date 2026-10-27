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

.PHONY: setup cluster up ci test down

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

# Delete the cluster. Its data in data/$(NAME) stays.
down:
	kind delete cluster --name $(NAME)

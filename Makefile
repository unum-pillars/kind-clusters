# Install what the clusters need with Homebrew: kind, kubectl, and Docker Desktop to run them. Safe to run again. Docker
# Desktop has to be started once by hand after it's installed.
setup:
	command -v brew >/dev/null || { echo "Homebrew is needed first: https://brew.sh"; exit 1; }
	command -v kind >/dev/null || brew install kind
	command -v kubectl >/dev/null || brew install kubectl
	command -v docker >/dev/null || brew install --cask docker
	docker info >/dev/null 2>&1 || { echo "Docker is installed but not running: start Docker Desktop, then make setup again"; exit 1; }
	@echo "ok"

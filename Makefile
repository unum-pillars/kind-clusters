# Add we here when it exists: a third unum, apart from these two.
CLUSTERS=us them
DATA=$(HOME)/.kind-data
CTX=kind-$(NAME)

.PHONY: setup all cluster up down wipe test-data test-persist

# Install what the clusters need with Homebrew: kind, kubectl, and Docker Desktop to run them. Safe to run again. Docker
# Desktop has to be started once by hand after it's installed.
setup:
	command -v brew >/dev/null || { echo "Homebrew is needed first: https://brew.sh"; exit 1; }
	command -v kind >/dev/null || brew install kind
	command -v kubectl >/dev/null || brew install kubectl
	command -v docker >/dev/null || brew install --cask docker
	docker info >/dev/null 2>&1 || { echo "Docker is installed but not running: start Docker Desktop, then make setup again"; exit 1; }
	@echo "ok"

# Every cluster in $(CLUSTERS), one after another.
all:
	for n in $(CLUSTERS); do $(MAKE) cluster NAME=$$n || exit 1; done

# Make the cluster with kind, with its data directory mounted at /data and a MySQL (mysql.mysql:3306, root/root)
# and a redis (redis.redis:6379) on top. Data lives in $(DATA)/<name> on the host so it survives deleting the cluster.
# The mount only happens when the cluster is made. Safe to run again.
cluster:
	test -n "$(NAME)"
	mkdir -p $(DATA)/$(NAME)
	kind get clusters | grep -qx $(NAME) || sed 's|__DATA__|$(DATA)/$(NAME)|' kind/cluster.yaml | kind create cluster --name $(NAME) --config -
	kubectl --context $(CTX) apply --server-side -k kubernetes/services
	docker inspect $(NAME)-control-plane --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' | grep -qx /data \
	|| { echo "$(NAME) has no /data mount, it was made before the data directory: make down NAME=$(NAME), then make cluster again"; exit 1; }
	kubectl --context $(CTX) -n mysql rollout status deployment/mysql --timeout=300s
	kubectl --context $(CTX) -n redis rollout status deployment/redis --timeout=120s

up: cluster

# Delete the cluster. Its data in $(DATA)/<name> stays, and the next make cluster NAME= picks it up.
down:
	test -n "$(NAME)"
	kind delete cluster --name $(NAME)

# Delete the cluster's data too, for good. The cluster has to be down first, or the servers would lose their files underneath them.
wipe:
	test -n "$(NAME)"
	! kind get clusters | grep -qx $(NAME) || { echo "$(NAME) is still up: make down NAME=$(NAME) first"; exit 1; }
	rm -rf $(DATA)/$(NAME)

# Deploy the throwaway apps that do what an app does on first deploy. data: create its database if missing, migrate,
# write a row. cache: count a visit in redis. Run twice on one cluster, or across down and cluster, and rows= and visits=
# climb and the database is "exists", not "created".
test-data:
	test -n "$(NAME)"
	kubectl --context $(CTX) delete job data cache --ignore-not-found
	kubectl --context $(CTX) apply -f test/data.yaml -f test/cache.yaml
	kubectl --context $(CTX) wait --for=condition=complete job/data job/cache --timeout=180s
	kubectl --context $(CTX) logs job/data
	kubectl --context $(CTX) logs job/cache

# Prove the data outlives the cluster: wipe, make, first deploy creates the database and writes row 1 and visit 1,
# delete the cluster, make it again, second deploy finds the database and the old row and visit and writes number 2.
# Destroys $(DATA)/<name>.
test-persist:
	test -n "$(NAME)"
	-$(MAKE) down NAME=$(NAME)
	$(MAKE) wipe NAME=$(NAME)
	$(MAKE) cluster NAME=$(NAME)
	out=$$($(MAKE) test-data NAME=$(NAME)) && echo "$$out" && echo "$$out" | grep -q "created database hello" && echo "$$out" | grep -q "visits=1"
	$(MAKE) down NAME=$(NAME)
	$(MAKE) cluster NAME=$(NAME)
	out=$$($(MAKE) test-data NAME=$(NAME)) && echo "$$out" && echo "$$out" | grep -q "database hello exists" && echo "$$out" | grep -q "rows=2" && echo "$$out" | grep -q "visits=2"
	@echo "ok"

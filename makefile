.PHONY: build test run update-browser update-caddy bookmarks clean clean-all

.DEFAULT_GOAL := help

help:
	@echo 'usage: make [target]'
	@echo ''
	@echo 'available targets:'
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  %-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## build isolator container image
	./scripts/build.sh

test: build ## run bats tests (cues build)
	./scripts/test.sh

run: ## run isolator locally
	./scripts/run.sh

update-browser: ## update to latest tor browser version
	./scripts/update-browser.sh

update-caddy: ## update to latest caddy version
	./scripts/update-caddy.sh

bookmarks: ## regenerate bookmarks.html from bookmarks.csv
	cd scripts && python3 bookmarks.py

clean: ## remove docker images
	@docker rmi isolator:latest isolator:test 2>/dev/null || true

clean-all: ## stop and remove all running isolator containers
	@echo "stopping all isolator containers..."
	@docker ps -q --filter ancestor=isolator:latest --filter ancestor=isolator:test | xargs -r docker stop 2>/dev/null || true
	@docker ps -aq --filter ancestor=isolator:latest --filter ancestor=isolator:test | xargs -r docker rm 2>/dev/null || true
	@echo "done"

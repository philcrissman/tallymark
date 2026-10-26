.PHONY: build build-backend build-dashboard deploy release clean \
       local-db local-db-stop local-setup local-seed local-api local-test

# --- Production ---

build: build-backend build-dashboard

build-backend:
	./scripts/build-backend.sh

build-dashboard:
	./scripts/build-dashboard.sh

deploy: build
	./scripts/deploy.sh

release: build
	./scripts/package-release.sh

clean:
	rm -rf backend/build dashboard/build dist

# --- Local Development ---

local-db:
	docker compose up -d
	@echo "DynamoDB Local running on http://localhost:8000"

local-db-stop:
	docker compose down

local-setup: local-db
	@sleep 1
	./scripts/create-local-table.sh

local-seed:
	./scripts/seed-data.sh

local-api: build-backend
	cd infra && sam local start-api \
		--env-vars ../local-env.json \
		--docker-network tallymark_default \
		--warm-containers EAGER

local-test:
	@echo "==> POST /track"
	curl -s -X POST http://localhost:3000/track \
		-d '{"url":"/posts/test-post/","referrer":"https://example.com","siteId":"example.com"}' | python3 -m json.tool
	@echo ""
	@echo "==> GET /stats"
	curl -s -H "Authorization: Bearer localdevkey" \
		"http://localhost:3000/stats?site=example.com&start=2026-01-01&end=2026-12-31" | python3 -m json.tool

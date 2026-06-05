COMPOSE_FILE=infra/docker-compose.prod.yml
PROJECT_NAME=auto-search-tg-bot
BACKUP_DIR=infra/backups
POSTGRES_CONTAINER=auto-search-bot-postgres
POSTGRES_USER=auto
POSTGRES_DB=auto_search
BOT_API_CONTAINER=auto-search-bot-api
TG_BOT_CONTAINER=auto-search-tg-bot
WORKER_CONTAINER=auto-search-worker
BOT_API_URL=http://localhost:8100/api/v1
TEST_TELEGRAM_USER_ID?=123
TEST_TELEGRAM_CHAT_ID?=123
TEST_QUERY?=BMW до 3 млн пробег до 50 тыс
INTERNAL_API_KEY?=change-me-in-env

.PHONY: build up down restart ps logs logs-api logs-bot logs-worker logs-migrate migrate health backup restore diagnostics diagnostics-full diagnostics-network diagnostics-health diagnostics-logs diagnostics-db diagnostics-search-core diagnostics-bot-api-from-bot diagnostics-search-from-bot-api crashloop-check shell-api shell-db db-tables smoke-user smoke-search-core smoke-search smoke-favorites smoke-saved-searches smoke-subscription smoke-all prune

build:
	docker compose -f $(COMPOSE_FILE) build

up:
	docker compose -f $(COMPOSE_FILE) up -d

down:
	docker compose -f $(COMPOSE_FILE) down

restart:
	docker compose -f $(COMPOSE_FILE) restart

ps:
	docker compose -f $(COMPOSE_FILE) ps

logs:
	docker compose -f $(COMPOSE_FILE) logs -f --tail=200

logs-api:
	docker logs $(BOT_API_CONTAINER) --tail 200 -f

logs-bot:
	docker logs $(TG_BOT_CONTAINER) --tail 200 -f

logs-worker:
	docker logs $(WORKER_CONTAINER) --tail 200 -f

logs-migrate:
	docker logs auto-search-bot-api-migrate --tail 200

migrate:
	docker exec -it $(BOT_API_CONTAINER) alembic upgrade head

health:
	curl -f $(BOT_API_URL)/health
	curl -f $(BOT_API_URL)/health/ready
	curl -f $(BOT_API_URL)/health/live
	curl -f $(BOT_API_URL)/health/full

smoke-search-core:
	curl -s -f $(BOT_API_URL)/health/search-core

smoke-user:
	curl -s -f -X POST "$(BOT_API_URL)/users/telegram/upsert" \
		-H "Content-Type: application/json" \
		-H "X-Internal-API-Key: $(INTERNAL_API_KEY)" \
		-d '{"telegram_user_id":$(TEST_TELEGRAM_USER_ID),"telegram_chat_id":$(TEST_TELEGRAM_CHAT_ID),"username":"smoke_user","first_name":"Smoke","last_name":"Test","language_code":"ru"}'

smoke-search:
	curl -s -f -X POST "$(BOT_API_URL)/search-proxy/search?telegram_user_id=$(TEST_TELEGRAM_USER_ID)" \
		-H "Content-Type: application/json" \
		-H "X-Internal-API-Key: $(INTERNAL_API_KEY)" \
		-d '{"query":"$(TEST_QUERY)","page":1,"limit":10,"include_answer":false}'

smoke-favorites:
	curl -s -f "$(BOT_API_URL)/favorites?telegram_user_id=$(TEST_TELEGRAM_USER_ID)" \
		-H "X-Internal-API-Key: $(INTERNAL_API_KEY)"

smoke-saved-searches:
	curl -s -f "$(BOT_API_URL)/saved-searches?telegram_user_id=$(TEST_TELEGRAM_USER_ID)" \
		-H "X-Internal-API-Key: $(INTERNAL_API_KEY)"

smoke-subscription:
	curl -s -f "$(BOT_API_URL)/subscriptions/me?telegram_user_id=$(TEST_TELEGRAM_USER_ID)" \
		-H "X-Internal-API-Key: $(INTERNAL_API_KEY)"

smoke-all: health smoke-search-core smoke-user smoke-search smoke-favorites smoke-saved-searches smoke-subscription
	@echo "Smoke tests completed"

db-tables:
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "\dt"
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "select count(*) as users from users;"
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "select count(*) as favorites from favorites;"
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "select count(*) as saved_searches from saved_searches;"
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "select count(*) as search_history from search_history;"
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "select count(*) as subscriptions from subscriptions;"
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "select count(*) as payments from payments;"
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "select count(*) as notifications from notifications;"

backup:
	mkdir -p $(BACKUP_DIR)
	docker exec $(POSTGRES_CONTAINER) pg_dump -U $(POSTGRES_USER) -d $(POSTGRES_DB) > $(BACKUP_DIR)/auto_search_$$(date +%Y%m%d_%H%M%S).sql

restore:
ifndef FILE
	$(error FILE is required. Example: make restore FILE=infra/backups/auto_search.sql)
endif
	cat $(FILE) | docker exec -i $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

diagnostics: diagnostics-full

diagnostics-full: diagnostics-health diagnostics-network diagnostics-db diagnostics-search-core diagnostics-bot-api-from-bot diagnostics-search-from-bot-api diagnostics-logs crashloop-check
	@echo "Diagnostics completed"

diagnostics-health:
	@echo "== Bot API health =="
	-curl -s $(BOT_API_URL)/health
	@echo ""
	@echo "== Bot API live =="
	-curl -s $(BOT_API_URL)/health/live
	@echo ""
	@echo "== Bot API ready =="
	-curl -s $(BOT_API_URL)/health/ready
	@echo ""
	@echo "== Bot API full =="
	-curl -s $(BOT_API_URL)/health/full
	@echo ""

diagnostics-network:
	@echo "== Docker compose ps =="
	docker compose -f $(COMPOSE_FILE) ps
	@echo ""
	@echo "== Docker networks =="
	-docker network ls
	@echo ""
	@echo "== Bot internal network inspect =="
	-docker network inspect auto-search-tg-bot_bot_internal

diagnostics-db:
	@echo "== Postgres health =="
	-docker exec $(POSTGRES_CONTAINER) pg_isready -U $(POSTGRES_USER) -d $(POSTGRES_DB)
	@echo ""
	@echo "== DB tables and counts =="
	-$(MAKE) db-tables

diagnostics-search-core:
	@echo "== Search core through bot-api =="
	-curl -s $(BOT_API_URL)/health/search-core
	@echo ""

diagnostics-bot-api-from-bot:
	@echo "== bot-api health from tg-bot container =="
	-docker exec $(TG_BOT_CONTAINER) python -c "import os, urllib.request; base=os.environ.get('BOT_API_BASE_URL','http://bot-api:8100').rstrip('/'); prefix=os.environ.get('BOT_API_PREFIX','/api/v1').rstrip('/'); print(urllib.request.urlopen(base + prefix + '/health').read().decode())"

diagnostics-search-from-bot-api:
	@echo "== search-core health from bot-api container =="
	-docker exec $(BOT_API_CONTAINER) python -c "import os, urllib.request; base=os.environ.get('SEARCH_API_BASE_URL','http://host.docker.internal:8000').rstrip('/'); prefix=os.environ.get('SEARCH_API_PREFIX','/api/v1').rstrip('/'); print(urllib.request.urlopen(base + prefix + '/health').read().decode())"

diagnostics-logs:
	@echo "== Recent bot-api logs =="
	-docker logs $(BOT_API_CONTAINER) --tail 120
	@echo ""
	@echo "== Recent tg-bot logs =="
	-docker logs $(TG_BOT_CONTAINER) --tail 120
	@echo ""
	@echo "== Recent worker logs =="
	-docker logs $(WORKER_CONTAINER) --tail 120
	@echo ""
	@echo "== Migration logs =="
	-docker logs auto-search-bot-api-migrate --tail 120

crashloop-check:
	@echo "== Crashloop/restart check =="
	-docker inspect $(BOT_API_CONTAINER) --format='bot-api restart_count={{.RestartCount}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
	-docker inspect $(TG_BOT_CONTAINER) --format='tg-bot restart_count={{.RestartCount}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
	-docker inspect $(WORKER_CONTAINER) --format='worker restart_count={{.RestartCount}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
	-docker inspect $(POSTGRES_CONTAINER) --format='postgres restart_count={{.RestartCount}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'

shell-api:
	docker exec -it $(BOT_API_CONTAINER) sh

shell-db:
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

prune:
	docker system prune -f
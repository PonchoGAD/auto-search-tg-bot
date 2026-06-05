README.md
# Auto Search Telegram Bot Stack

Production stack for Telegram bot, bot API, worker and PostgreSQL.

## Services

```text
postgres   PostgreSQL database
bot-api    FastAPI backend for Telegram bot
tg-bot     Telegram bot
worker     background alerts and subscription jobs
Architecture
Telegram User
    ↓
tg-bot
    ↓ X-Internal-API-Key
bot-api
    ↓ X-API-Key if enabled
search core
    ↓
PostgreSQL
Required env files

Before launch, fill these files:

apps/bot_api/.env
apps/bot/.env
apps/worker/.env

Minimum required values:

apps/bot_api/.env

APP_ENV=prod
DATABASE_URL=postgresql+psycopg2://auto:password@postgres:5432/auto_search
POSTGRES_DB=auto_search
POSTGRES_USER=auto
POSTGRES_PASSWORD=password
SEARCH_API_BASE_URL=http://host.docker.internal:8000
SEARCH_API_PREFIX=/api/v1
SEARCH_API_KEY=
TELEGRAM_BOT_TOKEN=telegram_bot_token
INTERNAL_API_KEY=same_secret_for_all_services
JWT_SECRET=long_random_secret_min_32_chars
ADMIN_TELEGRAM_IDS_RAW=123456789
apps/bot/.env

BOT_TOKEN=telegram_bot_token
BOT_API_BASE_URL=http://bot-api:8100
BOT_API_PREFIX=/api/v1
INTERNAL_API_KEY=same_secret_for_all_services
ADMIN_TELEGRAM_IDS_RAW=123456789
apps/worker/.env

BOT_API_BASE_URL=http://bot-api:8100
BOT_API_PREFIX=/api/v1
SEARCH_API_BASE_URL=http://host.docker.internal:8000
SEARCH_API_PREFIX=/api/v1
TELEGRAM_BOT_TOKEN=telegram_bot_token
INTERNAL_API_KEY=same_secret_for_all_services

Important:

INTERNAL_API_KEY must be identical in bot_api, bot and worker.
SEARCH_API_BASE_URL must not duplicate /api/v1 if SEARCH_API_PREFIX=/api/v1 is used.
Launch
make build
make up
make ps

Run migrations:

make migrate

Check health:

make health

Full diagnostics:

make diagnostics-full
Smoke checklist
1. Docker services
make ps

Expected:

auto-search-bot-postgres   healthy
auto-search-bot-api        healthy
auto-search-tg-bot         running or healthy
auto-search-worker         running or healthy
2. Bot API health
make health

Expected:

/api/v1/health        ok
/api/v1/health/live   alive
/api/v1/health/ready  ready or degraded with clear checks
/api/v1/health/full   full dependency diagnostics
3. Search core health through bot-api
make smoke-search-core

Expected:

status ok
search_core response exists

If this fails, check:

SEARCH_API_BASE_URL
SEARCH_API_PREFIX
SEARCH_API_KEY
search core container or VPS
nginx/proxy
4. Upsert Telegram user
make smoke-user INTERNAL_API_KEY=your_internal_key

Expected:

user object returned
telegram_user_id = TEST_TELEGRAM_USER_ID
5. Search proxy
make smoke-search INTERNAL_API_KEY=your_internal_key

Expected:

structuredQuery exists
results is an array
debug exists
pagination exists
6. Favorites
make smoke-favorites INTERNAL_API_KEY=your_internal_key

Expected:

favorites list returns items array
7. Saved searches
make smoke-saved-searches INTERNAL_API_KEY=your_internal_key

Expected:

saved searches list returns items array
8. Subscription
make smoke-subscription INTERNAL_API_KEY=your_internal_key

Expected:

subscription status returned
free user has free limits
9. Full smoke
make smoke-all INTERNAL_API_KEY=your_internal_key

This runs:

health
smoke-search-core
smoke-user
smoke-search
smoke-favorites
smoke-saved-searches
smoke-subscription
10. Telegram bot manual smoke

Open Telegram and run:

/start
/profile
BMW до 3 млн пробег до 50 тыс
/favorites
/saved
/subscription
/admin

Expected:

/start creates or updates user in bot_api
/profile shows user data
search returns formatted cards
favorites opens without User not found
saved searches opens without User not found
subscription opens free/premium state
/admin opens only for ADMIN_TELEGRAM_IDS_RAW
Monitoring and Diagnostics
Main diagnostics command
make diagnostics-full

It runs:

diagnostics-health
diagnostics-network
diagnostics-db
diagnostics-search-core
diagnostics-bot-api-from-bot
diagnostics-search-from-bot-api
diagnostics-logs
crashloop-check
Health endpoints

Direct bot-api:

curl http://localhost:8100/api/v1/health
curl http://localhost:8100/api/v1/health/live
curl http://localhost:8100/api/v1/health/ready
curl http://localhost:8100/api/v1/health/search-core
curl http://localhost:8100/api/v1/health/full

Through nginx:

curl http://localhost/health
curl http://localhost/bot-api-health
curl http://localhost/search-health

Meaning:

/health       basic app status
/live         process is alive
/ready        checks PostgreSQL
/search-core  checks search core through bot-api
/full         checks PostgreSQL and search core together
Docker status
make ps
docker compose -f infra/docker-compose.prod.yml ps
Logs
make logs
make logs-api
make logs-bot
make logs-worker
make logs-migrate
make diagnostics-logs
Crashloop check
make crashloop-check

Expected:

restart_count should not keep growing
status should be running
health should be healthy where healthcheck exists
Network diagnostics
make diagnostics-network

Checks:

docker compose ps
docker network ls
bot_internal network inspect
Check bot_api from tg-bot container
make diagnostics-bot-api-from-bot

This proves that tg-bot can reach bot-api inside Docker.

Check search core from bot-api container
make diagnostics-search-from-bot-api

This proves that bot-api can reach search core.

Check search core through bot-api
make diagnostics-search-core

This checks:

http://localhost:8100/api/v1/health/search-core
Database checks

Show tables:

make db-tables

Open psql:

make shell-db

Useful SQL:

select count(*) from users;
select count(*) from favorites;
select count(*) from saved_searches;
select count(*) from search_history;
select count(*) from subscriptions;
select count(*) from payments;
select count(*) from notifications;
Backup
make backup

Backup files are saved into:

infra/backups/
Restore
make restore FILE=infra/backups/auto_search_YYYYMMDD_HHMMSS.sql
Common errors
Error	Meaning	Fix
401 from bot_api	INTERNAL_API_KEY mismatch	Set same INTERNAL_API_KEY in bot_api, bot and worker
403 from nginx internal	Public access to internal API is blocked	This is correct. Use internal Docker network or bot_api direct port for admin/internal calls
404 User not found	User was not created	Run /start or make smoke-user
429 Too many requests	Rate limit triggered	Reduce request speed or adjust RATE_LIMIT settings
502 Search core unavailable	bot_api cannot reach search core	Check SEARCH_API_BASE_URL, SEARCH_API_PREFIX, VPS, nginx, search core health
504 Gateway timeout	Upstream service did not answer in time	Check search core latency, bot-api logs, nginx timeout
ready degraded	PostgreSQL or dependency check failed	Run make diagnostics-full
No search results	Search core has no data or filters too strict	Check Qdrant, indexing, source data, search core logs
Payment created but no URL	PAYMENT_PROVIDER=stub or provider not configured	Configure real provider or enable stub mode
tg-bot starts but commands fail	bot cannot reach bot-api or internal key mismatch	Run make diagnostics-bot-api-from-bot and check INTERNAL_API_KEY
worker sends no alerts	no active saved searches or first-run bootstrap	Check saved_searches, last_seen_listing_id and worker logs
Production notes

Do not expose internal endpoints publicly.

Blocked by nginx:

/internal/
/bot-api/internal/
/bot-api/api/v1/internal/

Allowed public diagnostics:

/health
/bot-api-health
/search-health

For production, set strong secrets:

INTERNAL_API_KEY
JWT_SECRET
PAYMENT_WEBHOOK_SECRET
POSTGRES_PASSWORD

Never commit .env files.
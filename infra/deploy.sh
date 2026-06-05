#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/infra/docker-compose.prod.yml"
NETWORK_NAME="auto-search-shared"

echo "=== auto-search-tg-bot deploy ==="
echo "Dir: $PROJECT_DIR"

# Проверяем что shared network существует (создаётся search core)
echo ""
echo "[1/4] Checking shared network '$NETWORK_NAME'..."
if ! docker network ls --format '{{.Name}}' | grep -qx "$NETWORK_NAME"; then
    echo "ERROR: Network '$NETWORK_NAME' not found!"
    echo "  Run auto-search-mvp first: cd /opt/auto-search-mvp && ./infra/deploy.sh"
    exit 1
fi
echo "  OK — network found"

# Собираем образы
echo ""
echo "[2/4] Building images..."
docker compose -f "$COMPOSE_FILE" build --no-cache

# Поднимаем стек
echo ""
echo "[3/4] Starting services..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# Ждём health bot-api (он запускает миграции)
echo ""
echo "[4/4] Waiting for bot-api to become healthy (max 90s)..."
for i in $(seq 1 30); do
    STATUS=$(docker inspect auto-search-bot-api --format='{{.State.Health.Status}}' 2>/dev/null || echo "starting")
    if [ "$STATUS" = "healthy" ]; then
        echo "  OK — bot-api is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        echo ""
        echo "ERROR: bot-api did not become healthy in 90s."
        echo "Migration logs:"
        docker logs auto-search-bot-api-migrate --tail 30 2>/dev/null || true
        echo ""
        echo "Bot-api logs:"
        docker logs auto-search-bot-api --tail 30
        exit 1
    fi
    printf "  %s/30 (status: %s)...\r" "$i" "$STATUS"
    sleep 3
done

echo ""
echo "=== All services status ==="
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "=== Done! ==="
echo "Useful commands:"
echo "  docker logs auto-search-tg-bot -f        # бот"
echo "  docker logs auto-search-bot-api -f       # api"
echo "  docker logs auto-search-worker -f        # worker"
echo "  curl http://localhost:8100/api/v1/health  # health check"

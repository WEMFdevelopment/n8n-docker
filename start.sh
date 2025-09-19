#!/bin/bash

DEBUG=${DEBUG:-false}
NGROK_PORT=5678
CHECK_INTERVAL=10

if [ "$DEBUG" = "true" ]; then
  export N8N_LOG_LEVEL=debug
  echo "⚡ Modo DEBUG activado"
fi

docker compose up -d
sleep 5

N8N_CONTAINER=$(docker ps --filter "ancestor=n8nio/n8n" --format "{{.Names}}" | head -n1)
if [ -z "$N8N_CONTAINER" ]; then
  echo "❌ No se encontró el contenedor de n8n"
  exit 1
fi

ngrok http $NGROK_PORT --log=stdout >/tmp/ngrok.log 2>&1 &
NGROK_PID=$!
echo "🚀 ngrok iniciado (PID: $NGROK_PID)"

get_ngrok_url() {
  grep -o "https://[a-z0-9]*\.ngrok.io" /tmp/ngrok.log | tail -n1
}

CURRENT_URL=""
NEW_URL=$(get_ngrok_url)

while [ -z "$NEW_URL" ]; do
  sleep 1
  NEW_URL=$(get_ngrok_url)
done
CURRENT_URL="$NEW_URL"
echo "🌐 URL pública inicial de ngrok: $CURRENT_URL"

docker exec "$N8N_CONTAINER" /bin/sh -c "export WEBHOOK_TUNNEL_URL=$CURRENT_URL"

docker compose restart n8n
sleep 5

docker logs -f "$N8N_CONTAINER" &

while true; do
  sleep $CHECK_INTERVAL
  NEW_URL=$(get_ngrok_url)
  if [ -n "$NEW_URL" ] && [ "$NEW_URL" != "$CURRENT_URL" ]; then
    echo "🔄 ngrok URL cambió: $NEW_URL"
    CURRENT_URL="$NEW_URL"
    docker exec "$N8N_CONTAINER" /bin/sh -c "export WEBHOOK_TUNNEL_URL=$CURRENT_URL"
    docker compose restart n8n
  fi
done
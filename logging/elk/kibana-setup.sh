#!/usr/bin/env bash
# Creates the Kibana data view for NEXVION logs once Kibana is reachable.
set -euo pipefail
KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"

for _ in $(seq 1 60); do
  curl -sf "$KIBANA_URL/api/status" >/dev/null && break
  sleep 5
done

curl -sf -X POST "$KIBANA_URL/api/data_views/data_view" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"data_view":{"id":"nexvion-logs","title":"nexvion-logs-*","name":"NEXVION logs","timeFieldName":"@timestamp"},"override":true}' \
  >/dev/null
echo "Kibana data view 'nexvion-logs-*' is ready: $KIBANA_URL/app/discover"

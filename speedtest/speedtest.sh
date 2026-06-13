#!/bin/bash

set -euo pipefail

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

OUTPUT_FILE="/var/www/html/newperformance/speedtest/speedtest_results_${HOSTNAME}.json"

echo "Running speedtest on: $HOSTNAME"
echo "Timestamp: $TIMESTAMP"
echo "Output file: $OUTPUT_FILE"
echo

# -----------------------------
# 1. Get server list
# -----------------------------
SERVER_LIST=$(speedtest --list 2>/dev/null || true)

if [[ -z "$SERVER_LIST" ]]; then
    echo "ERROR: Could not retrieve server list"
    exit 1
fi

# -----------------------------
# 2. Extract ONLY numeric IDs reliably
# -----------------------------
SERVER_IDS=$(echo "$SERVER_LIST" | grep -oE '^[[:space:]]*[0-9]+' | tr -d ' ')

if [[ -z "$SERVER_IDS" ]]; then
    echo "ERROR: No valid server IDs found"
    echo "DEBUG: Raw server list:"
    echo "$SERVER_LIST"
    exit 1
fi

# -----------------------------
# 3. Pick random server
# -----------------------------
SERVER_ID=$(echo "$SERVER_IDS" | shuf -n 1)

echo "Selected server ID: $SERVER_ID"

# -----------------------------
# 4. Run speedtest
# -----------------------------
RESULT=$(speedtest --secure --json --server "$SERVER_ID" 2>&1) || {
    echo "ERROR: Speedtest failed for server $SERVER_ID"
    echo "$RESULT"
    exit 1
}

# -----------------------------
# 5. Convert JSON safely
# -----------------------------
JSON=$(jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg hostname "$HOSTNAME" \
    --argjson raw "$RESULT" '
    {
        timestamp: $timestamp,
        hostname: $hostname,
        server_id: ($raw.server.id // null),
        server_name: ($raw.server.name // null),
        ping_ms: ($raw.ping.latency // null),

        download_mbps: (
            (($raw.download.bandwidth // 0) * 8 / 1000000)
            | (.*100 | floor / 100)
        ),

        upload_mbps: (
            (($raw.upload.bandwidth // 0) * 8 / 1000000)
            | (.*100 | floor / 100)
        )
    }
')

# -----------------------------
# 6. Append safely (no overwrite)
# -----------------------------
if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "[]" > "$OUTPUT_FILE"
fi

TMP=$(mktemp)

jq ". + [$JSON]" "$OUTPUT_FILE" > "$TMP" && mv "$TMP" "$OUTPUT_FILE"

echo "$JSON"

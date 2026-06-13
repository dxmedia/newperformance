#!/bin/bash

set -euo pipefail

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

OUTPUT_DIR="/var/www/html/newperformance/speedtest"
OUTPUT_FILE="${OUTPUT_DIR}/speedtest_results_${HOSTNAME}.json"

mkdir -p "$OUTPUT_DIR"

echo "Running speedtest on: $HOSTNAME"
echo "Timestamp: $TIMESTAMP"
echo "Output file: $OUTPUT_FILE"
echo

# Ensure file exists and is valid JSON array
if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "[]" > "$OUTPUT_FILE"
fi

# Run speedtest (Ookla CLI)
RESULT=$(speedtest --secure --json -single)

# Extract values (bits/sec in most versions)
DOWNLOAD_BPS=$(echo "$RESULT" | jq -r '.download // 0')
UPLOAD_BPS=$(echo "$RESULT"   | jq -r '.upload // 0')
PING_MS=$(echo "$RESULT"      | jq -r '.ping // 0')

# Convert to Mbps (2 decimal places)
DOWNLOAD_MBPS=$(awk "BEGIN {printf \"%.2f\", ($DOWNLOAD_BPS) / 1000000}")
UPLOAD_MBPS=$(awk "BEGIN {printf \"%.2f\", ($UPLOAD_BPS) / 1000000}")

# Build new entry
NEW_ENTRY=$(jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg host "$HOSTNAME" \
  --argjson download_mbps "$DOWNLOAD_MBPS" \
  --argjson upload_mbps "$UPLOAD_MBPS" \
  --argjson ping_ms "$PING_MS" \
  '{
    timestamp: $timestamp,
    host: $host,
    download_mbps: $download_mbps,
    upload_mbps: $upload_mbps,
    ping_ms: $ping_ms
  }'
)

# Append into JSON array safely
TMP_FILE=$(mktemp)

jq --argjson new "$NEW_ENTRY" '. += [$new]' "$OUTPUT_FILE" > "$TMP_FILE"

# preserve permissions by overwriting safely
cat "$TMP_FILE" > "$OUTPUT_FILE"
rm "$TMP_FILE"

# enforce correct permissions every run
chown www-data:www-data "$OUTPUT_FILE" 2>/dev/null || true
chmod 644 "$OUTPUT_FILE"
echo "Done."

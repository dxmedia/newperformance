#!/bin/bash

set -euo pipefail

INPUT_FILE="${1:-sites.txt}"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: Input file '$INPUT_FILE' not found"
    exit 1
fi

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

OUTPUT_DIR="/var/www/html/newperformance/dns"
OUTPUT_FILE="${OUTPUT_DIR}/dns_results_${HOSTNAME}.json"

mkdir -p "$OUTPUT_DIR"

echo "Running DNS lookups on: $HOSTNAME"
echo "Timestamp: $TIMESTAMP"
echo "Output file: $OUTPUT_FILE"

# Create file if it doesn't exist
if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "[]" > "$OUTPUT_FILE"
    chmod 644 "$OUTPUT_FILE"
fi

while IFS= read -r SITE || [[ -n "$SITE" ]]; do

    # Skip comments and blank lines
    [[ -z "$SITE" ]] && continue
    [[ "$SITE" =~ ^# ]] && continue

    echo "Looking up $SITE..."

    DIG_OUTPUT=$(dig "$SITE" A +stats 2>/dev/null || true)

    IPS=$(echo "$DIG_OUTPUT" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)

    QUERY_TIME=$(echo "$DIG_OUTPUT" | awk '/Query time:/ {print $4}')

    if [[ -z "$QUERY_TIME" ]]; then
        QUERY_TIME=0
    fi

    if [[ -n "$IPS" ]]; then
        STATUS="success"
        IP_JSON=$(printf '%s\n' "$IPS" | jq -R . | jq -s .)
    else
        STATUS="failed"
        IP_JSON="[]"
    fi

    NEW_ENTRY=$(jq -n \
        --arg timestamp "$TIMESTAMP" \
        --arg hostname "$HOSTNAME" \
        --arg site "$SITE" \
        --arg status "$STATUS" \
        --argjson lookup_time_ms "$QUERY_TIME" \
        --argjson ips "$IP_JSON" \
        '{
            timestamp: $timestamp,
            hostname: $hostname,
            site: $site,
            status: $status,
            lookup_time_ms: $lookup_time_ms,
            ips: $ips
        }')

    TMP_FILE=$(mktemp)

    jq --argjson new "$NEW_ENTRY" '. += [$new]' "$OUTPUT_FILE" > "$TMP_FILE"

    cat "$TMP_FILE" > "$OUTPUT_FILE"
    rm -f "$TMP_FILE"

done < "$INPUT_FILE"

echo
echo "Done."

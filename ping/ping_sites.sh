#!/bin/bash

set -euo pipefail

INPUT_FILE="/opt/newperformance/ping/sites.txt"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: Input file '$INPUT_FILE' not found"
    exit 1
fi

# Get WAN IP
WAN_IP=$(curl -s --max-time 5 https://api.ipify.org)

if [[ -z "$WAN_IP" ]]; then
    WAN_IP="unknown"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

OUTPUT_DIR="/var/www/html/newperformance/ping"
OUTPUT_FILE="${OUTPUT_DIR}/ping_results_${HOSTNAME}.json"

mkdir -p "$OUTPUT_DIR"

# Create JSON array if file doesn't exist
if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "[]" > "$OUTPUT_FILE"
fi

echo "Writing to: $OUTPUT_FILE"
echo "WAN IP: $WAN_IP"
echo "Timestamp: $TIMESTAMP"
echo

TEMP_RESULTS=$(mktemp)

echo "[]" > "$TEMP_RESULTS"

while IFS= read -r HOST || [[ -n "$HOST" ]]; do

    # Skip empty lines and comments
    [[ -z "$HOST" ]] && continue
    [[ "$HOST" =~ ^# ]] && continue

    echo "Pinging $HOST..."

    PING_OUTPUT=$(ping -c 10 "$HOST" 2>/dev/null || true)

    if echo "$PING_OUTPUT" | grep -q "packet loss"; then

        PACKET_LOSS=$(echo "$PING_OUTPUT" | \
            sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p')

        LATENCY_LINE=$(echo "$PING_OUTPUT" | grep -E "min/avg|max|round-trip" || true)

        LAT_VALUES=$(echo "$LATENCY_LINE" | awk -F'=' '{print $2}' | awk '{print $1}')

        MIN_LAT=$(echo "$LAT_VALUES" | cut -d'/' -f1)
        AVG_LAT=$(echo "$LAT_VALUES" | cut -d'/' -f2)
        MAX_LAT=$(echo "$LAT_VALUES" | cut -d'/' -f3)

        [[ "$PACKET_LOSS" =~ ^[0-9]+([.][0-9]+)?$ ]] || PACKET_LOSS=100
        [[ "$MIN_LAT" =~ ^[0-9]+([.][0-9]+)?$ ]] || MIN_LAT=null
        [[ "$AVG_LAT" =~ ^[0-9]+([.][0-9]+)?$ ]] || AVG_LAT=null
        [[ "$MAX_LAT" =~ ^[0-9]+([.][0-9]+)?$ ]] || MAX_LAT=null

        STATUS="success"
        [[ "$PACKET_LOSS" == "100" ]] && STATUS="failed"

    else
        STATUS="failed"
        PACKET_LOSS=100
        MIN_LAT=null
        AVG_LAT=null
        MAX_LAT=null
    fi

    jq \
        --arg timestamp "$TIMESTAMP" \
        --arg source_ip "$WAN_IP" \
        --arg host "$HOST" \
        --arg status "$STATUS" \
        --argjson packet_loss_pct "$PACKET_LOSS" \
        --argjson min_latency_ms "$MIN_LAT" \
        --argjson avg_latency_ms "$AVG_LAT" \
        --argjson max_latency_ms "$MAX_LAT" \
        '. += [{
            timestamp: $timestamp,
            source_ip: $source_ip,
            host: $host,
            status: $status,
            packet_loss_pct: $packet_loss_pct,
            min_latency_ms: $min_latency_ms,
            avg_latency_ms: $avg_latency_ms,
            max_latency_ms: $max_latency_ms
        }]' \
        "$TEMP_RESULTS" > "${TEMP_RESULTS}.new"

    mv "${TEMP_RESULTS}.new" "$TEMP_RESULTS"

done < "$INPUT_FILE"

# Append new results to existing JSON array
jq -s '.[0] + .[1]' "$OUTPUT_FILE" "$TEMP_RESULTS" > "${OUTPUT_FILE}.new"

mv "${OUTPUT_FILE}.new" "$OUTPUT_FILE"

rm -f "$TEMP_RESULTS"

echo
echo "Done."
echo "Results available at:"
echo "http://localhost/newperformance/ping/$(basename "$OUTPUT_FILE")"

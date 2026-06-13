#!/bin/bash

set -euo pipefail

SITES_FILE="${1:-sites.txt}"
DNS_SERVERS_FILE="${2:-dns_servers.txt}"

HOSTNAME_SHORT=$(hostname -s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

OUTPUT_DIR="/var/www/html/newperformance/dns"
OUTPUT_FILE="${OUTPUT_DIR}/dns_results_${HOSTNAME_SHORT}.json"

mkdir -p "$OUTPUT_DIR"

if [[ ! -f "$SITES_FILE" ]]; then
    echo "ERROR: Sites file '$SITES_FILE' not found"
    exit 1
fi

if [[ ! -f "$DNS_SERVERS_FILE" ]]; then
    echo "ERROR: DNS servers file '$DNS_SERVERS_FILE' not found"
    exit 1
fi

# Ensure JSON file exists and is valid JSON array
if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "[]" > "$OUTPUT_FILE"
fi

chown www-data:www-data "$OUTPUT_FILE" || true
chmod 644 "$OUTPUT_FILE" || true

echo "Running DNS checks on: $HOSTNAME_SHORT"
echo "Timestamp: $TIMESTAMP"
echo "Output file: $OUTPUT_FILE"
echo

while IFS= read -r SITE || [[ -n "$SITE" ]]; do
    [[ -z "$SITE" || "$SITE" =~ ^# ]] && continue

    echo "Testing site: $SITE"

    while IFS= read -r DNS_SERVER || [[ -n "$DNS_SERVER" ]]; do
        [[ -z "$DNS_SERVER" || "$DNS_SERVER" =~ ^# ]] && continue

        # Get IPs
        IPS_RAW=$(dig @"$DNS_SERVER" "$SITE" +short 2>/dev/null || true)

        # Get query time (more reliable separate call)
        DIG_STATS=$(dig @"$DNS_SERVER" "$SITE" +stats 2>/dev/null || true)
        QUERY_TIME=$(echo "$DIG_STATS" | awk '/Query time:/ {print $4}')

        [[ -z "$QUERY_TIME" ]] && QUERY_TIME=0

        # Parse IPs into JSON array
        IPS_JSON=$(echo "$IPS_RAW" | awk 'NF' | jq -R -s -c 'split("\n") | map(select(length>0))')

        # Determine status
        if [[ -n "$IPS_RAW" ]]; then
            STATUS="success"
        else
            STATUS="failed"
        fi

        # Append safely using jq (prevents corruption)
        TMP_FILE=$(mktemp)

        jq --arg timestamp "$TIMESTAMP" \
           --arg hostname "$HOSTNAME_SHORT" \
           --arg site "$SITE" \
           --arg dns_server "$DNS_SERVER" \
           --arg status "$STATUS" \
           --argjson lookup_time_ms "$QUERY_TIME" \
           --argjson ips "$IPS_JSON" \
        '. += [{
            timestamp: $timestamp,
            hostname: $hostname,
            site: $site,
            dns_server: $dns_server,
            status: $status,
            lookup_time_ms: $lookup_time_ms,
            ips: $ips
        }]' "$OUTPUT_FILE" > "$TMP_FILE"

        mv "$TMP_FILE" "$OUTPUT_FILE"

        echo "  $DNS_SERVER -> ${QUERY_TIME}ms ($STATUS)"

    done < "$DNS_SERVERS_FILE"

done < "$SITES_FILE"

echo
echo "Done."

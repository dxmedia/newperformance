#!/bin/bash

set -euo pipefail

INPUT_DIR="/opt/newperformance/dns"
SITES_FILE="${INPUT_DIR}/sites.txt}"
DNS_SERVERS_FILE="${INPUT_DIR}/dns_servers.txt}"

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

# Create file if missing
if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "[]" > "$OUTPUT_FILE"
fi

# FIX PERMISSIONS ONCE (important)
chown www-data:www-data "$OUTPUT_FILE" 2>/dev/null || true
chmod 644 "$OUTPUT_FILE" 2>/dev/null || true

echo "Running DNS checks on: $HOSTNAME_SHORT"
echo "Timestamp: $TIMESTAMP"
echo "Output file: $OUTPUT_FILE"
echo

while IFS= read -r SITE || [[ -n "$SITE" ]]; do
    [[ -z "$SITE" || "$SITE" =~ ^# ]] && continue

    echo "Testing site: $SITE"

    while IFS= read -r DNS_SERVER || [[ -n "$DNS_SERVER" ]]; do
        [[ -z "$DNS_SERVER" || "$DNS_SERVER" =~ ^# ]] && continue

        # DNS lookup results
        IPS_RAW=$(dig @"$DNS_SERVER" "$SITE" +short 2>/dev/null || true)

        # timing (IMPORTANT: correct field parsing)
        DIG_STATS=$(dig @"$DNS_SERVER" "$SITE" +stats 2>/dev/null || true)
        QUERY_TIME=$(echo "$DIG_STATS" | awk -F': ' '/Query time:/ {print $2}' | awk '{print $1}')

        [[ -z "$QUERY_TIME" ]] && QUERY_TIME=0

        # convert IPs to JSON array
        IPS_JSON=$(echo "$IPS_RAW" | awk 'NF' | jq -R -s -c 'split("\n") | map(select(length>0))')

        # status
        if [[ -n "$IPS_RAW" ]]; then
            STATUS="success"
        else
            STATUS="failed"
        fi

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

        # FIX PERMISSIONS AFTER WRITE (prevents breakage)
        chown www-data:www-data "$OUTPUT_FILE" 2>/dev/null || true
        chmod 644 "$OUTPUT_FILE" 2>/dev/null || true

        echo "  $DNS_SERVER -> ${QUERY_TIME}ms ($STATUS)"

    done < "$DNS_SERVERS_FILE"

done < "$SITES_FILE"

echo
echo "Done."

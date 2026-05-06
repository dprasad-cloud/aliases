#!/bin/bash

# Configuration
HEAVY_THRESHOLD=50
DATA_FILE="/tmp/cpu-data.txt"
SORT_COL=7
SORT_NAME="%_LIMIT"

# Parse options
while getopts "r" opt; do
  case $opt in
    r) SORT_COL=6; SORT_NAME="%_REQUEST" ;;
    *) echo "Usage: $0 [-r]"; exit 1 ;;
  esac
done

rm -f "$DATA_FILE"

# 1. Pre-fetching
echo "Pre-fetching and summing CPU resources..."
echo "NAMESPACE|POD|USAGE|REQUEST|LIMIT|%_REQ|%_LIMIT" > "$DATA_FILE"

declare -A cpu_data
while read -r ns pod req_sum lim_sum; do
    cpu_data["$ns/$pod"]="$req_sum|$lim_sum"
done < <(kubectl get pods -A -o json | jq -r '.items[] |
    .metadata.namespace + " " + .metadata.name + " " +
    ([.spec.containers[].resources.requests.cpu // "0m"] | map(if endswith("m") then .[:-1] | tonumber else . | tonumber * 1000 end) | add | tostring) + " " +
    ([.spec.containers[].resources.limits.cpu // "0m"] | map(if endswith("m") then .[:-1] | tonumber else . | tonumber * 1000 end) | add | tostring)')

# 2. Processing
while read -r ns pod usage_m rest; do
    usage=${usage_m%m}
    raw_data=${cpu_data["$ns/$pod"]}
    [ -z "$raw_data" ] && continue
    req_ms=$(echo "$raw_data" | cut -d'|' -f1)
    lim_ms=$(echo "$raw_data" | cut -d'|' -f2)

    echo "$ns $pod $usage $req_ms $lim_ms" | awk '
        {
            u=$3; r=$4; l=$5;
            p_req=(r>0)?(u/r)*100:0;
            p_lim=(l>0)?(u/l)*100:0;
            printf "%s|%s|%sm|%sm|%sm|%.1f%%|%.1f%%\n", $1, $2, u, r, l, p_req, p_lim
        }' >> "$DATA_FILE"
done < <(kubectl top pods -A --no-headers)

# 3. Print Table
echo -e "\n--- CPU Usage Table (Sorted by $SORT_NAME Ascending) ---"
{
    head -n 1 "$DATA_FILE"
    tail -n +2 "$DATA_FILE" | sort -t'|' -k${SORT_COL},${SORT_COL}n
} | column -t -s '|'

# 4. WATCHLIST (Regex Method)
echo -e "\n================================================================"
echo "⚠️  HIGH LOAD WATCHLIST (>$HEAVY_THRESHOLD% OF LIMIT)"
echo "================================================================"

# This logic reads the file BEFORE column -t touches it
HEAVY_COUNT=0
while IFS='|' read -r ns pod usage req lim preq plim; do
    # Skip header
    [[ "$ns" == "NAMESPACE" ]] && continue

    # Strip % and convert to float for comparison
    val=$(echo "$plim" | sed 's/%//g')

    if (( $(echo "$val > $HEAVY_THRESHOLD" | bc -l) )); then
        printf "%-15s %-45s %-10s / %-10s (%s)\n" "$ns" "$pod" "$usage" "$lim" "$plim"
        ((HEAVY_COUNT++))
    fi
done < "$DATA_FILE"

if [ "$HEAVY_COUNT" -eq 0 ]; then
    echo "  (No pods are currently exceeding $HEAVY_THRESHOLD% of their CPU limit)"
fi

# 5. Summary
echo -e "\n--- CLUSTER CPU SUMMARY ---"
awk -F'|' '
    function to_ms(v) { gsub(/[^0-9.]/, "", v); return v + 0 }
    NR > 1 { u += to_ms($3); r += to_ms($4); l += to_ms($5) }
    END {
        if (r == 0) exit;
        printf "Total Requested: %.2f cores\n", r/1000;
        printf "Total Used:      %.2f cores\n", u/1000;
        printf "Waste:           %.2f cores\n", (r-u)/1000;
        printf "Efficiency:      %.2f%% (Usage vs Request)\n", (u/r)*100;
        if (l > 0) printf "Utilization:     %.2f%% (Usage vs Limit)\n", (u/l)*100;
    }' "$DATA_FILE"

rm "$DATA_FILE"
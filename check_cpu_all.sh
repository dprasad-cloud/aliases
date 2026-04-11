#!/bin/bash

HEAVY_THRESHOLD=0.50

# 1. Fetching SUM of all container requests/limits per pod
echo "Pre-fetching and summing container resources..."

declare -A cpu_data
while read -r ns pod req_sum lim_sum; do
    cpu_data["$ns/$pod"]="$req_sum|$lim_sum"
done < <(kubectl get pods -A -o json | jq -r '.items[] |
    .metadata.namespace + " " + .metadata.name + " " +
    ([.spec.containers[].resources.requests.cpu // "0m"] | map(if endswith("m") then .[:-1] | tonumber else . | tonumber * 1000 end) | add | tostring) + " " +
    ([.spec.containers[].resources.limits.cpu // "0m"] | map(if endswith("m") then .[:-1] | tonumber else . | tonumber * 1000 end) | add | tostring)')

# 2. Main Processing
TOTAL_U=0
TOTAL_R=0
HEAVY_COUNT=0

echo -e "\nScanning for High Load Pods (> 50% Limit)..."

while read -r ns pod usage_m mem; do
    usage=${usage_m%m}
    raw_data=${cpu_data["$ns/$pod"]}

    req_ms=$(echo "$raw_data" | cut -d'|' -f1)
    lim_ms=$(echo "$raw_data" | cut -d'|' -f2)

    TOTAL_U=$((TOTAL_U + usage))
    TOTAL_R=$((TOTAL_R + req_ms))

    # Heavy Load Check
    if [ "$lim_ms" -gt 0 ]; then
        is_heavy=$(awk "BEGIN {if ($usage/$lim_ms > $HEAVY_THRESHOLD) print 1; else print 0}")
        if [ "$is_heavy" -eq 1 ]; then
            lim_pct=$(awk "BEGIN {printf \"%.2f\", ($usage/$lim_ms)*100}")
            echo "  [!] HEAVY LOAD: $ns/$pod ($usage_m used of ${lim_ms}m limit - $lim_pct%)"
            ((HEAVY_COUNT++))
        fi
    fi
done < <(kubectl top pods -A --no-headers)

# 3. Handle Empty Heavy Load List
if [ "$HEAVY_COUNT" -eq 0 ]; then
    echo "  (No pods are currently exceeding 50% of their CPU limit)"
fi

# 4. Final Summary
if [ "$TOTAL_R" -gt 0 ]; then
    WASTE=$((TOTAL_R - TOTAL_U))
    EFFICIENCY=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_U / $TOTAL_R) * 100}")

    echo -e "\n--- CLUSTER SUMMARY ---"
    printf "Total Requested: %.2f cores\n" $(awk "BEGIN {print $TOTAL_R/1000}")
    printf "Total Used:      %.2f cores\n" $(awk "BEGIN {print $TOTAL_U/1000}")
    printf "Waste:           %.2f cores\n" $(awk "BEGIN {print $WASTE/1000}")
    printf "Efficiency:      %s%%\n" "$EFFICIENCY"
else
    echo -e "\nNo valid CPU request data found. Check if pods have 'requests' defined."
fi
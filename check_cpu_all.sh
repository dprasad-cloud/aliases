#!/bin/bash

HEAVY_THRESHOLD=0.50

# 1. Local Hash Map for speed
declare -A cpu_data
while read -r ns pod req lim; do
    [[ -z "$req" ]] && req="0m"
    [[ -z "$lim" ]] && lim="0m"
    cpu_data["$ns/$pod"]="$req|$lim"
done < <(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[0].resources.requests.cpu}{" "}{.spec.containers[0].resources.limits.cpu}{"\n"}{end}')

# Helper function for unit conversion
to_ms() {
    local val=$1
    if [[ "$val" == *m ]]; then echo "${val%m}"; elif [[ "$val" == "0" || -z "$val" ]]; then echo "0"; else echo "$((val * 1000))"; fi
}

# Temporary storage for summary math
TOTAL_U=0
TOTAL_R=0

echo "Analyzing cluster CPU usage..."

# 2. Main Processing Loop
while read -r ns pod usage_m mem; do

    usage=${usage_m%m}
    raw_data=${cpu_data["$ns/$pod"]}

    request=$(echo "$raw_data" | cut -d'|' -f1)
    limit=$(echo "$raw_data" | cut -d'|' -f2)

    req_ms=$(to_ms "$request")
    lim_ms=$(to_ms "$limit")

    # Add to totals for the final summary
    TOTAL_U=$((TOTAL_U + usage))
    TOTAL_R=$((TOTAL_R + req_ms))

    # Check for High Load (> 50% of Limit)
    if [ "$lim_ms" -gt 0 ]; then
        is_heavy=$(awk "BEGIN {if ($usage/$lim_ms > $HEAVY_THRESHOLD) print 1; else print 0}")
        if [ "$is_heavy" -eq 1 ]; then
            lim_pct=$(awk "BEGIN {printf \"%.2f\", ($usage/$lim_ms)*100}")
            echo "HEAVY LOAD: $ns/$pod ($usage_m used of $limit limit - $lim_pct%)"
        fi
    fi
done < <(kubectl top pods -A --no-headers)

# 3. Final Summary
if [ "$TOTAL_R" -gt 0 ]; then
    WASTE=$((TOTAL_R - TOTAL_U))
    EFFICIENCY=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_U / $TOTAL_R) * 100}")

    echo ""
    printf "Total Requested: %.2f cores\n" $(awk "BEGIN {print $TOTAL_R/1000}")
    printf "Total Used:      %.2f cores\n" $(awk "BEGIN {print $TOTAL_U/1000}")
    printf "Waste:           %.2f cores\n" $(awk "BEGIN {print $WASTE/1000}")
    printf "Efficiency:      %s%%\n" "$EFFICIENCY"
else
    echo "No requested CPU data found."
fi
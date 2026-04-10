#!/bin/bash

# Configuration
THRESHOLD=70
DATA_FILE="/tmp/mem-data.txt"
rm -f $DATA_FILE

echo "Scanning all namespaces for Memory Usage..."
echo "NAMESPACE|POD|USAGE|REQUEST|LIMIT|%_REQ|%_LIMIT" > "$DATA_FILE"

# Pre-fetch all resources to speed up execution
RESOURCES=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[0].resources.requests.memory}{" "}{.spec.containers[0].resources.limits.memory}{"\n"}{end}')

kubectl top pods -A --no-headers | while read -r ns pod cpu usage_raw; do
    # Extract the specific line for this pod from our pre-fetched list
    res=$(echo "$RESOURCES" | awk -v n="$ns" -v p="$pod" '$1==n && $2==p {print $3, $4}')

    if [ -z "$res" ]; then continue; fi

    echo "$ns $pod $usage_raw $res" | awk '
        function to_mi(val) {
            if (val == "" || val == "0" || val == "<none>") return 0
            # Matches G, Gi, g, gi
            if (val ~ /[Gg]i?/) { sub(/[Gg]i?/, "", val); return val * 1024 }
            # Matches M, Mi, m, mi
            if (val ~ /[Mm]i?/) { sub(/[Mm]i?/, "", val); return val }
            # Matches K, Ki, k, ki
            if (val ~ /[Kk]i?/) { sub(/[Kk]i?/, "", val); return val / 1024 }
            return val + 0
        }
        {
            u = to_mi($3); r = to_mi($4); l = to_mi($5);
            p_req = (r > 0) ? (u / r) * 100 : 0;
            p_lim = (l > 0) ? (u / l) * 100 : 0;
            printf "%s|%s|%s|%s|%s|%.1f%%|%.1f%%\n", $1, $2, $3, $4, $5, p_req, p_lim
        }' >> "$DATA_FILE"
done

# Print full aligned table
column -t -s '|' "$DATA_FILE"

echo -e "\n================================================================"
echo "⚠️  HIGH USAGE WATCHLIST (>$THRESHOLD% OF LIMIT)"
echo "================================================================"

awk -v limit="$THRESHOLD" -F'|' '
    NR > 1 {
        split($7, a, "%");
        if (a[1] > limit) {
            printf "%-15s %-45s %-10s / %-10s (%s)\n", $1, $2, $3, $5, $7
        }
    }' "$DATA_FILE"

echo -e "\n--- Global Memory Summary ---"
awk -F'|' '
    function to_mi(val) {
        if (val ~ /[Gg]i?/) { sub(/[Gg]i?/, "", val); return val * 1024 }
        if (val ~ /[Mm]i?/) { sub(/[Mm]i?/, "", val); return val }
        return val + 0
    }
    NR > 1 {
        total_usage += to_mi($3);
        total_req   += to_mi($4);
        total_lim   += to_mi($5);
    }
    END {
        if (total_lim == 0) exit;
        printf "Total Usage:     %.2f GiB\n", total_usage/1024;
        printf "Total Requested: %.2f GiB\n", total_req/1024;
        printf "Total Limited:   %.2f GiB\n", total_lim/1024;
        if (total_req > 0) printf "Efficiency:      %.2f%% (Usage vs Request)\n", (total_usage / total_req) * 100;
        printf "Utilization:     %.2f%% (Usage vs Limit)\n", (total_usage / total_lim) * 100;
    }' "$DATA_FILE"

# Cleanup
rm "$DATA_FILE"
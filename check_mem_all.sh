#!/bin/bash

# Configuration
THRESHOLD=70
DATA_FILE="/tmp/mem-data.txt"
SORT_COL=7  # Default to %_LIMIT (column 7)
SORT_NAME="%_LIMIT"

# Parse options
while getopts "r" opt; do
  case $opt in
    r)
      SORT_COL=6
      SORT_NAME="%_REQUEST"
      ;;
    *)
      echo "Usage: $0 [-r]"
      echo "  -r: Sort by %_REQUEST (Default is %_LIMIT)"
      exit 1
      ;;
  esac
done

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
            if (val ~ /[Gg]i?/) { sub(/[Gg]i?/, "", val); return val * 1024 }
            if (val ~ /[Mm]i?/) { sub(/[Mm]i?/, "", val); return val }
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

# Print full aligned table - Sorted by chosen column ascending
echo -e "\n--- Memory Usage Table (Sorted by $SORT_NAME Ascending) ---"
{
    head -n 1 "$DATA_FILE"
    tail -n +2 "$DATA_FILE" | sort -t'|' -k${SORT_COL},${SORT_COL}n
} | column -t -s '|'

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
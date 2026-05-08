#!/bin/bash

# Configuration
THRESHOLD=70
DATA_FILE=$(mktemp /tmp/mem-scan.XXXXXX)
trap 'rm -f "$DATA_FILE"' EXIT

SORT_COL=7  # Default to %_LIMIT
SORT_NAME="%_LIMIT"

while getopts "r" opt; do
  case $opt in
    r) SORT_COL=6; SORT_NAME="%_REQUEST" ;;
    *) echo "Usage: $0 [-r]"; exit 1 ;;
  esac
done

echo "Scanning Cluster Memory (Summing all containers)..."
echo "NAMESPACE|POD|USAGE|REQUEST|LIMIT|%_REQ|%_LIMIT" > "$DATA_FILE"

# 1. Capture top and pod data into variables
TOP_DATA=$(kubectl top pods -A --no-headers)
POD_DATA=$(kubectl get pods -A -o json | jq -r '.items[] | select(.status.phase == "Running") |
      def parse_mi: tostring | {
         num: (match("[0-9.]+").string // "0" | tonumber),
         unit: (match("[A-Za-z]+").string // "")
      } | if .unit == "Ki" then .num / 1024 elif .unit == "Gi" or .unit == "G" then .num * 1024 else .num end;
      [
         .metadata.namespace,
         .metadata.name,
         ([.spec.containers[].resources.requests.memory // "0"] | map(parse_mi) | add | tostring + "Mi"),
         ([.spec.containers[].resources.limits.memory // "0"] | map(parse_mi) | add | tostring + "Mi")
      ] | @tsv')

# 2. Join the data using AWK
awk -F '\t' -v top_input="$TOP_DATA" '
BEGIN {
    OFS="|"
    n = split(top_input, lines, "\n")
    for (i=1; i<=n; i++) {
        split(lines[i], cols, /[[:space:]]+/)
        # cols[1]=NS, cols[2]=Pod, cols[4]=Memory Usage
        u_mem[cols[1]cols[2]] = cols[4]
    }
}

function clean_mi(val) {
    v = val; gsub(/[A-Za-z]/, "", v);
    if (val ~ /[Gg]i?/) return v * 1024;
    if (val ~ /[Kk]i?/) return v / 1024;
    return v + 0;
}

{
    key = $1$2
    if (key in u_mem) {
        usage_raw = u_mem[key]
        u_val = clean_mi(usage_raw)
        r_val = clean_mi($3)
        l_val = clean_mi($4)

        p_req = (r_val > 0) ? (u_val / r_val) * 100 : 0
        p_lim = (l_val > 0) ? (u_val / l_val) * 100 : 0

        printf "%s|%s|%s|%s|%s|%.1f%%|%.1f%%\n", $1, $2, usage_raw, $3, $4, p_req, p_lim
    }
}' <<< "$POD_DATA" >> "$DATA_FILE"

# 3. Print Table
echo -e "\n--- Memory Usage Table (Sorted by $SORT_NAME Ascending) ---"
if [ $(wc -l < "$DATA_FILE") -le 1 ]; then
    echo "No running pods with metrics found."
else
    { head -n 1 "$DATA_FILE"; tail -n +2 "$DATA_FILE" | sort -t'|' -k${SORT_COL},${SORT_COL}n; } | column -t -s '|'
fi

# 4. WATCHLIST
echo -e "\n================================================================"
echo "⚠️  HIGH USAGE WATCHLIST (>$THRESHOLD% OF LIMIT)"
echo "================================================================"
awk -v threshold="$THRESHOLD" -F'|' '
    NR > 1 {
        plim = $7; gsub(/%/,"",plim)
        if (plim+0 > threshold) {
            printf "%-15s %-45s %-10s / %-10s (%s)\n", $1, $2, $3, $5, $7
            count++
        }
    }
    END { if (count==0) print "  (No pods exceeding threshold)" }
' "$DATA_FILE"

# 5. Summary
echo -e "\n--- CLUSTER MEMORY SUMMARY ---"
awk -F'|' '
    function to_mi(val) {
        v = val; gsub(/[^0-9.]/, "", v);
        if (val ~ /[Gg]i?/) return v * 1024;
        return v + 0
    }
    NR > 1 {
        total_u += to_mi($3); total_r += to_mi($4); total_l += to_mi($5);
    }
    END {
        if (NR <= 1) { print "No data available"; exit }
        printf "Total Usage:     %.2f GiB\n", total_u/1024;
        printf "Total Requested: %.2f GiB\n", total_r/1024;
        printf "Total Limited:   %.2f GiB\n", total_l/1024;
        if (total_r > 0) printf "Efficiency:      %.2f%% (Usage vs Request)\n", (total_u / total_r) * 100;
        if (total_l > 0) printf "Utilization:     %.2f%% (Usage vs Limit)\n", (total_u / total_l) * 100;
    }' "$DATA_FILE"
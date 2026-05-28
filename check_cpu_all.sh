#!/bin/bash

# Configuration
HEAVY_THRESHOLD=50
DATA_FILE=$(mktemp /tmp/cpu-scan.XXXXXX)
trap 'rm -f "$DATA_FILE"' EXIT

SORT_COL=7
SORT_NAME="%_LIMIT"

while getopts "r" opt; do
  case $opt in
    r) SORT_COL=6; SORT_NAME="%_REQUEST" ;;
    *) echo "Usage: $0 [-r]"; exit 1 ;;
  esac
done

echo "Scanning Cluster CPU (Summing all containers)..."
echo "NAMESPACE|POD|USAGE|REQUEST|LIMIT|%_REQ|%_LIMIT" > "$DATA_FILE"

# 1. Get pod resource requests/limits and stream with top output to awk for joining
awk '
# NR==FNR processes the first "file" (from kubectl top)
NR==FNR {
    # $1=NS, $2=Pod, $3=Usage
    # Use a single-character separator to avoid issues with pod names containing spaces
    u_cpu[$1 FS $2] = $3
    next
}
# The second block processes the second "file" (from kubectl get pods)
{
    # Set FS for tab-separated input from POD_RESOURCES
    FS="\t"; OFS="|"
    # $1=NS, $2=Pod, $3=Request, $4=Limit
    key = $1 " " $2
    if (key in u_cpu) {
        usage_raw = u_cpu[key]
        u_val = usage_raw; gsub(/m/,"",u_val)
        r_val = $3; gsub(/m/,"",r_val)
        l_val = $4; gsub(/m/,"",l_val)

        p_req = (r_val > 0) ? (u_val / r_val) * 100 : 0
        p_lim = (l_val > 0) ? (u_val / l_val) * 100 : 0

        printf "%s|%s|%s|%s|%s|%.1f%%|%.1f%%\n", $1, $2, usage_raw, $3, $4, p_req, p_lim
    }
}' <(kubectl top pods -A --no-headers) \
   <(kubectl get pods -A -o json | jq -r '.items[] | select(.status.phase == "Running") |
      def parse_cpu: tostring | {
         num: (match("[0-9.]+").string // "0" | tonumber),
         unit: (match("[A-Za-z]+").string // "")
      } | if .unit == "m" then .num elif .num < 50 then .num * 1000 else .num end;
      [
         .metadata.namespace,
         .metadata.name,
         ([.spec.containers[].resources.requests.cpu // "0"] | map(parse_cpu) | add | tostring + "m"),
         ([.spec.containers[].resources.limits.cpu // "0"] | map(parse_cpu) | add | tostring + "m")
      ] | @tsv') >> "$DATA_FILE"


# 3. Print Table
echo -e "\n--- CPU Usage Table (Sorted by $SORT_NAME Ascending) ---"
if [ $(wc -l < "$DATA_FILE") -le 1 ]; then
    echo "No running pods with metrics found."
else
    { head -n 1 "$DATA_FILE"; tail -n +2 "$DATA_FILE" | sort -t'|' -k${SORT_COL},${SORT_COL}n; } | column -t -s '|'
fi

# 4. WATCHLIST
echo -e "\n================================================================"
echo "⚠️  HIGH USAGE WATCHLIST (>$HEAVY_THRESHOLD% OF LIMIT)"
echo "================================================================"
awk -v threshold="$HEAVY_THRESHOLD" -F'|' '
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
echo -e "\n--- CLUSTER CPU SUMMARY ---"
awk -F'|' '
    NR > 1 {
        u = $3; gsub(/m/,"",u); total_u += u
        r = $4; gsub(/m/,"",r); total_r += r
        l = $5; gsub(/m/,"",l); total_l += l
    }
    END {
        if (NR <= 1) { print "No data available"; exit }
        printf "Total Requested: %.2f cores\n", total_r/1000
        printf "Total Used:      %.2f cores\n", total_u/1000
        printf "Waste:           %.2f cores\n", (total_r - total_u)/1000
        if (total_r > 0) printf "Efficiency:      %.2f%% (Usage vs Request)\n", (total_u / total_r) * 100
        if (total_l > 0) printf "Utilization:     %.2f%% (Usage vs Limit)\n", (total_u / total_l) * 100
    }' "$DATA_FILE"
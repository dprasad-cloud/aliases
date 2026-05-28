#!/bin/bash

# Configuration
THRESHOLD=70
DATA_FILE=$(mktemp /tmp/mem-scan.XXXXXX)
TOP_FILE=$(mktemp /tmp/top-data.XXXXXX)
trap 'rm -f "$DATA_FILE" "$TOP_FILE"' EXIT

SORT_COL=7
SORT_NAME="%_LIMIT"

while getopts "r" opt; do
  case $opt in
    r) SORT_COL=6; SORT_NAME="%_REQUEST" ;;
    *) echo "Usage: $0 [-r]"; exit 1 ;;
  esac
done

echo "Scanning Cluster Memory (Summing all containers)..."

if ! kubectl top pods -A --no-headers > "$TOP_FILE" 2>/dev/null || [ ! -s "$TOP_FILE" ]; then
    echo "ERROR: 'kubectl top pods -A' returned no data."
    exit 1
fi

echo "NAMESPACE|POD|USAGE|REQUEST|LIMIT|%_REQ|%_LIMIT" > "$DATA_FILE"

awk '
    function clean_mi(val) {
        v = val; gsub(/[^0-9.]/, "", v);
        if (val ~ /[Gg]i/) return v * 1024;
        if (val ~ /[Kk]i/) return v / 1024;
        return v + 0;
    }
    NR==FNR {
        line = $0; gsub(/\x1b\[[0-9;]*m/, "", line);
        split(line, f, /[[:space:]]+/);
        u_mem[f[1] "||" f[2]] = f[4];
        next
    }
    BEGIN { FS="\t" }
    {
        key = $1 "||" $2
        if (key in u_mem) {
            usage_raw = u_mem[key]
            u_val = clean_mi(usage_raw)
            r_val = clean_mi($3)
            l_val = clean_mi($4)
            p_req = (r_val > 0) ? (u_val / r_val) * 100 : 0
            p_lim = (l_val > 0) ? (u_val / l_val) * 100 : 0
            printf "%s|%s|%s|%s|%s|%.1f%%|%.1f%%\n", $1, $2, usage_raw, $3, $4, p_req, p_lim
        }
    }
' "$TOP_FILE" <(kubectl get pods -A -o json | jq -r '.items[] | select(.status.phase == "Running") |
      def parse_mi: tostring | {
         num: (match("[0-9.]+").string // "0" | tonumber),
         unit: (match("[A-Za-z]+").string // "")
      } | if .unit == "Ki" then .num / 1024 elif .unit == "Gi" or .unit == "G" then .num * 1024 else .num end;
      [.metadata.namespace, .metadata.name,
      ([.spec.containers[].resources.requests.memory // "0"] | map(parse_mi) | add | tostring + "Mi"),
      ([.spec.containers[].resources.limits.memory // "0"] | map(parse_mi) | add | tostring + "Mi")] | @tsv') >> "$DATA_FILE"

echo "NAMESPACE|POD|USAGE|REQUEST|LIMIT|%_REQ|%_LIMIT" > header.tmp
cat header.tmp "$DATA_FILE" > final.tmp && mv final.tmp "$DATA_FILE"
rm header.tmp

echo -e "\n--- Memory Usage Table (Sorted by $SORT_NAME Ascending) ---"
{ head -n 1 "$DATA_FILE"; tail -n +2 "$DATA_FILE" | sort -t'|' -k${SORT_COL},${SORT_COL}n; } | column -t -s '|'

echo -e "\n================================================================"
echo "⚠️  HIGH USAGE WATCHLIST (>$THRESHOLD% OF LIMIT)"
echo "================================================================"
awk -v threshold="$THRESHOLD" -F'|' 'NR>1 { plim=$7; gsub(/%/,"",plim); if(plim+0 > threshold) printf "%-15s %-45s %-10s / %-10s (%s)\n", $1, $2, $3, $5, $7 }' "$DATA_FILE"

echo -e "\n--- CLUSTER MEMORY SUMMARY ---"
awk -F'|' '
    function to_mi(v) { gsub(/[^0-9.]/,"",v); return v+0 }
    NR>1 { u+=to_mi($3); r+=to_mi($4); l+=to_mi($5) }
    END {
        printf "Total Usage:     %.2f GiB\n", u/1024;
        printf "Total Requested: %.2f GiB\n", r/1024;
        printf "Total Limited:   %.2f GiB\n", l/1024;
        printf "Efficiency:      %.2f%% (Usage vs Request)\n", (r>0 ? (u/r)*100 : 0);
        printf "Utilization:     %.2f%% (Usage vs Limit)\n", (l>0 ? (u/l)*100 : 0);
    }' "$DATA_FILE"
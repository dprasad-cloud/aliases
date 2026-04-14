FILTER=$1
NOW=$(date +%s)

# Handle "all" or empty filter
if [[ "$FILTER" == "all" || "$FILTER" == "ALL" || -z "$FILTER" ]]; then
    GREP_CMD="cat"
else
    GREP_CMD="grep $FILTER"
fi

awk -v now="$NOW" 'BEGIN {FS="\t"; OFS=" | "}
function to_mi(val) {
   if (val ~ /[Gg]i?/) { sub(/[Gg]i?/, "", val); return val * 1024 }
   if (val ~ /[Mm]i?/) { sub(/[Mm]i?/, "", val); return val }
   if (val ~ /[Kk]i?/) { sub(/[Kk]i?/, "", val); return val / 1024 }
   return val + 0
}
function to_m(val) {
   if (val ~ /m/) { sub(/m/, "", val); return val + 0 }
   if (val == "" || val == " ") return 0;
   return val * 1000
}
function how_long_ago(ts) {
    if (ts == "" || ts == "-" || ts == " " || ts == "Never") return "";
    gsub(/[:TZ-]/, " ", ts);
    t = mktime(ts);
    diff = now - t;
    if (diff < 0) return "0s ago";
    if (diff < 60) return diff "s ago";
    if (diff < 3600) return int(diff/60) "m ago";
    if (diff < 86400) return int(diff/3600) "h ago";
    return int(diff/86400) "d ago";
}

# 1. Map top data
NR==FNR {u_cpu[$1$2]=$3; u_mem[$1$2]=$4; next}

# 2. Process and Format
($1$2) in u_cpu {
   uc = to_m(u_cpu[$1$2]);
   um = to_mi(u_mem[$1$2]);

   # Kubernetes Get Pods Fields:
   # $3=CPU Limit, $4=Mem Request, $5=Mem Limit
   lc_val = to_m($3);
   mr_val = to_mi($4);
   ml_val = to_mi($5);

   # CPU Percentage (Usage vs Limit)
   cp_lim = (lc_val > 0) ? (uc / lc_val) * 100 : 0;

   # Mem Percentages (Usage vs Request and Usage vs Limit)
   mp_req = (mr_val > 0) ? (um / mr_val) * 100 : 0;
   mp_lim = (ml_val > 0) ? (um / ml_val) * 100 : 0;

   # Trim Pod Name to 40
   p_name = $2;
   gsub(/[[:space:]]/, "", p_name);
   display_pod = (length(p_name) > 40) ? substr(p_name, 1, 37)"..." : p_name;

   # Restart Info
   restarts=$6; raw_ts=$7;
   restart_info = (restarts > 0) ? how_long_ago(raw_ts) "(" restarts ")" : "";

   # TARGET FORMAT:
   # common | pod-name | C: 858m R/L 0/2 (0% / 42%) | M: 6088Mi | R/L: 6Gi / 12Gi (100% / 49%)
   # Note: Since k8s "get pods" doesnt natively show CPU Request in basic jsonpath,
   # we show 0 or "n/a" for the Request part of CPU unless you customize the jsonpath further.

   printf "%-10s | %-40.40s | C: %-5s R/L 0/%-4s (%3d%% / %3d%%) | M: %-7s | R/L: %-5s / %-5s (%3d%% / %3d%%) | %s\n",
          $1, display_pod, u_cpu[$1$2], $3, 0, cp_lim, u_mem[$1$2], $4, $5, mp_req, mp_lim, restart_info
}' <(kubectl top pods -A --no-headers | $GREP_CMD | awk '{print $1"\t"$2"\t"$3"\t"$4}') \
   <(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[0].resources.limits.cpu}{"\t"}{.spec.containers[0].resources.requests.memory}{"\t"}{.spec.containers[0].resources.limits.memory}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.status.containerStatuses[0].lastState.terminated.finishedAt}{"\n"}{end}' | $GREP_CMD) \
| column -t -s '|'
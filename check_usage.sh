FILTER=$1
NOW=$(date +%s)

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

NR==FNR {u_cpu[$1$2]=$3; u_mem[$1$2]=$4; next}

($1$2) in u_cpu {
   uc = to_m(u_cpu[$1$2]);
   um = to_mi(u_mem[$1$2]);
   rc_val = to_m($3); lc_val = to_m($4);
   mr_val = to_mi($5); ml_val = to_mi($6);

   cp_req = (rc_val > 0) ? (uc / rc_val) * 100 : 0;
   cp_lim = (lc_val > 0) ? (uc / lc_val) * 100 : 0;
   mp_req = (mr_val > 0) ? (um / mr_val) * 100 : 0;
   mp_lim = (ml_val > 0) ? (um / ml_val) * 100 : 0;

   p_name = $2; gsub(/[[:space:]]/, "", p_name);
   display_pod = (length(p_name) > 40) ? substr(p_name, 1, 37)"..." : p_name;

   restarts=$7; raw_ts=$8;
   restart_info = (restarts > 0) ? how_long_ago(raw_ts) "(" restarts ")" : "";

   cpu_rl = $3 "/" $4;
   mem_rl = $5 "/" $6;
   cpu_perc = sprintf("(%3d%% / %3d%%)", cp_req, cp_lim);
   mem_perc = sprintf("(%3d%% / %3d%%)", mp_req, mp_lim);

   # ADDED: uc (raw CPU millicores) as the first field for sorting
   printf "%d | %-10s | %-40.40s | C: %-5s %-10s %-15s | M: %-7s | %-12s %-15s | %s\n",
          uc, $1, display_pod, u_cpu[$1$2], cpu_rl, cpu_perc, u_mem[$1$2], mem_rl, mem_perc, restart_info
}' <(kubectl top pods -A --no-headers | $GREP_CMD | awk '{print $1"\t"$2"\t"$3"\t"$4}') \
   <(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[0].resources.requests.cpu}{"\t"}{.spec.containers[0].resources.limits.cpu}{"\t"}{.spec.containers[0].resources.requests.memory}{"\t"}{.spec.containers[0].resources.limits.memory}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.status.containerStatuses[0].lastState.terminated.finishedAt}{"\n"}{end}' | $GREP_CMD) \
| sort -rn | cut -d '|' -f 2- | column -t -s '|'
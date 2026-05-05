#!/bin/bash
FILTER=$1
NOW=$(date +%s)

# Handle empty or 'all' filter
if [[ "$FILTER" == "all" || "$FILTER" == "ALL" || -z "$FILTER" ]]; then
    PATTERN="."
else
    PATTERN="$FILTER"
fi

awk -v now="$NOW" -v pattern="$PATTERN" -F '\t' 'BEGIN { OFS="|" }

function to_mi(val) {
   if (val ~ /[Gg]i?/) { sub(/[Gg]i?/, "", val); return val * 1024 }
   if (val ~ /[Mm]i?/) { sub(/[Mm]i?/, "", val); return val }
   if (val ~ /[Kk]i?/) { sub(/[Kk]i?/, "", val); return val / 1024 }
   return val + 0
}
function to_m(val) {
   if (val ~ /m/) { sub(/m/, "", val); return val + 0 }
   if (val == "" || val == " " || val == "0") return 0;
   return val * 1000
}
function how_long_ago(ts) {
    if (ts == "" || ts == "-" || ts == " " || ts == "<nil>" || ts == "Never" || ts == "0") return "";
    gsub(/[:TZ-]/, " ", ts);
    t = mktime(ts);
    if (t <= 0) return "";
    diff = now - t;
    if (diff < 0) return "0s ago";
    if (diff < 60) return diff "s ago";
    if (diff < 3600) return int(diff/60) "m ago";
    if (diff < 86400) return int(diff/3600) "h ago";
    return int(diff/86400) "d ago";
}

# --- Internal Filtering ---
(pattern != "." && $0 !~ pattern) { next }

# Source 1: kubectl top
NR==FNR {
    split($0, a, /[[:space:]]+/);
    u_cpu[a[1]a[2]]=a[3]; u_mem[a[1]a[2]]=a[4];
    next
}

# Source 2: kubectl get
($1$2) in u_cpu {
   uc = to_m(u_cpu[$1$2]);
   um = to_mi(u_mem[$1$2]);
   rc_val = to_m($3); lc_val = to_m($4);
   mr_val = to_mi($5); ml_val = to_mi($6);

   cp_req = (rc_val > 0) ? (uc / rc_val) * 100 : 0;
   cp_lim = (lc_val > 0) ? (uc / lc_val) * 100 : 0;
   mp_req = (mr_val > 0) ? (um / mr_val) * 100 : 0;
   mp_lim = (ml_val > 0) ? (um / ml_val) * 100 : 0;

   total_restarts = $7;
   latest_ts = $8;

   p_name = $2;
   display_pod = (length(p_name) > 27) ? substr(p_name, 1, 20) ".*" substr(p_name, length(p_name) - 4) : p_name;

   time_ago = how_long_ago(latest_ts);
   if (total_restarts > 0) {
       restart_info = (time_ago != "") ? time_ago " (" total_restarts ")" : "(" total_restarts ")";
   } else {
       restart_info = "-";
   }

   cpu_rl = $3 "/" $4;
   mem_rl = $5 "/" $6;
   cpu_perc = sprintf("(%3d%% / %3d%%)", cp_req, cp_lim);
   mem_perc = sprintf("(%3d%% / %3d%%)", mp_req, mp_lim);

   # Sorting by CPU Limit % (cp_lim)
   printf "%03d|%-12s|%-27.27s|C: %-5s %-10s %-15s|M: %-7s %-12s %-15s|%s\n",
          cp_lim, $1, display_pod, u_cpu[$1$2], cpu_rl, cpu_perc, u_mem[$1$2], mem_rl, mem_perc, restart_info
}' <(kubectl top pods -A --no-headers) \
   <(kubectl get pods -A -o json | jq -r '.items[] | [
      .metadata.namespace,
      .metadata.name,
      .spec.containers[0].resources.requests.cpu // "-",
      .spec.containers[0].resources.limits.cpu // "-",
      .spec.containers[0].resources.requests.memory // "-",
      .spec.containers[0].resources.limits.memory // "-",
      .status.containerStatuses[0].restartCount // "0",
      .status.containerStatuses[0].lastState.terminated.finishedAt // "0"
   ] | @tsv') \
| sort -rn | cut -d '|' -f 2- | column -t -s '|' -o ' | '

#!/bin/bash

FILTER=$1
NOW=$(date +%s)

if [[ "$FILTER" == "all" || "$FILTER" == "ALL" || -z "$FILTER" ]]; then
    pattern="."
else
    pattern="${FILTER// /[[:space:]]+}"
fi

awk -v now="$NOW" -v pattern="$pattern" -F '\t' 'BEGIN { OFS="|" }

function to_mi(val) {
   if (val ~ /[Gg]i?/) { sub(/[Gg]i?/, "", val); return val * 1024 }
   if (val ~ /[Mm]i?/) { sub(/[Mm]i?/, "", val); return val }
   if (val ~ /[Kk]i?/) { sub(/[Kk]i?/, "", val); return val / 1024 }
   return val + 0
}

function to_m(val) {
   v = val "";
   if (v == "" || v == "0" || v == "-" || v == "<nil>") return 0;
   # If it has an "m", just strip it and return the number
   if (v ~ /m/) { sub(/m/, "", v); return v + 0 }
   # If no "m", it is either a whole number (2) or decimal (0.5).
   # Both represent Cores and need to be multiplied by 1000.
   return v * 1000
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

# Source 1: kubectl top
NR==FNR {
    split($0, a, /[[:space:]]+/);
    u_cpu[a[1]a[2]]=a[3]; u_mem[a[1]a[2]]=a[4];
    next
}

# Internal Filtering
(pattern != "." && $0 !~ pattern) { next }

# Source 2: kubectl get
($1$2) in u_cpu {
   uc = to_m(u_cpu[$1$2]);
   um = to_mi(u_mem[$1$2]);

   rc_val = to_m($3);
   lc_val = to_m($4);
   mr_val = to_mi($5);
   ml_val = to_mi($6);

   total_restarts = $7;
   latest_ts = $8;

   p_name = $2;
   display_pod = (length(p_name) > 27) ? substr(p_name, 1, 20) ".*" substr(p_name, length(p_name) - 4) : p_name;

   time_ago = how_long_ago(latest_ts);
   restart_info = (total_restarts > 0) ? ((time_ago != "") ? time_ago " (" total_restarts ")" : "(" total_restarts ")") : "-";

   # Calculate Percentages
   cp_req = (rc_val > 0) ? int((uc / rc_val) * 100) : 0;
   cp_lim = (lc_val > 0) ? int((uc / lc_val) * 100) : 0;
   mp_req = (mr_val > 0) ? int((um / mr_val) * 100) : 0;
   mp_lim = (ml_val > 0) ? int((um / ml_val) * 100) : 0;

   printf "%03d|%-12s|%-27s|C: %-6s %-12s %-15s|M: %-7s %-12s %-15s|%s\n",
          mp_lim, $1, display_pod, u_cpu[$1$2], $3"/"$4, sprintf("(%3d%%/%3d%%)", cp_req, cp_lim),
          u_mem[$1$2], $5"/"$6, sprintf("(%3d%%/%3d%%)", mp_req, mp_lim "%"), restart_info
}' <(kubectl top pods -A --no-headers) \
   <(kubectl get pods -A -o json | jq -r '.items[] | [
      .metadata.namespace,
      .metadata.name,
      (.spec.containers[0].resources.requests.cpu // "0" | tostring),
      (.spec.containers[0].resources.limits.cpu // "0" | tostring),
      (.spec.containers[0].resources.requests.memory // "0" | tostring),
      (.spec.containers[0].resources.limits.memory // "0" | tostring),
      (.status.containerStatuses[0].restartCount // "0" | tostring),
      (.status.containerStatuses[0].lastState.terminated.finishedAt // "0" | tostring)
   ] | @tsv') \
| sort -rn | cut -d '|' -f 2- | column -t -s '|' -o ' | '
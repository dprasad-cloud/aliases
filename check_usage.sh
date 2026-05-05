#!/bin/bash

FILTER=$1
NOW=$(date +%s)

if [[ "$FILTER" == "all" || "$FILTER" == "ALL" || -z "$FILTER" ]]; then
    pattern="."
else
    pattern="$FILTER"
fi

awk -v now="$NOW" -v pattern="$pattern" -F '[[:space:]]+' 'BEGIN { OFS=" | " }

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

# Source 1: kubectl top
NR==FNR {
    u_cpu[$1$2]=$3; u_mem[$1$2]=$4;
    next
}

# Internal Filtering
(pattern != "." && $0 !~ pattern) { next }

# Source 2: kubectl get
($1$2) in u_cpu {
   uc = to_m(u_cpu[$1$2]); um = to_mi(u_mem[$1$2]);
   rc_val = to_m($3); lc_val = to_m($4);
   mr_val = to_mi($5); ml_val = to_mi($6);

   split($7, restarts_arr, ",");
   split($8, times_arr, ",");

   total_restarts = 0;
   latest_ts = "0";

   for (i in restarts_arr) { total_restarts += restarts_arr[i] }
   for (j in times_arr) {
       if (times_arr[j] != "<nil>" && times_arr[j] != "0" && times_arr[j] > latest_ts) {
           latest_ts = times_arr[j];
       }
   }

   p_name = $2;
   display_pod = (length(p_name) > 27) ? substr(p_name, 1, 24)"..." : p_name;

   time_ago = how_long_ago(latest_ts);
   if (total_restarts > 0) {
       restart_info = (time_ago != "") ? time_ago " (" total_restarts ")" : "(" total_restarts ")";
   } else {
       restart_info = "-";
   }

   # Calculate Mem % for sorting
   mp_lim = (ml_val > 0) ? int((um / ml_val) * 100) : 0;

   # We print mp_lim as the first field so sort -rn works, then cut it out
   printf "%03d | %-12s | %-27s | C: %-5s %-10s %-15s | M: %-7s | %-12s %-15s | %s\n",
          mp_lim, $1, display_pod, u_cpu[$1$2], $3"/"$4, sprintf("(%3d%% / %3d%%)", (rc_val>0?uc/rc_val*100:0), (lc_val>0?uc/lc_val*100:0)),
          u_mem[$1$2], $5"/"$6, sprintf("(%3d%% / %3d%%)", (mr_val>0?um/mr_val*100:0), mp_lim "%"), restart_info
}' <(kubectl top pods -A --no-headers) \
   <(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[0].resources.requests.cpu}{" "}{.spec.containers[0].resources.limits.cpu}{" "}{.spec.containers[0].resources.requests.memory}{" "}{.spec.containers[0].resources.limits.memory}{" "}{range .status.containerStatuses[*]}{.restartCount}{","}{end}{" "}{range .status.containerStatuses[*]}{.lastState.terminated.finishedAt}{","}{end}{"\n"}{end}') \
| sort -rn | cut -d '|' -f 2- | column -t -s '|'
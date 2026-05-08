#!/bin/bash
FILTER=$1
NOW=$(date +%s)

if [[ "$FILTER" == "all" || "$FILTER" == "ALL" || -z "$FILTER" ]]; then
    PATTERN="."
else
    PATTERN="${FILTER// /[[:space:]]+}"
fi

awk -v now="$NOW" -v pattern="$PATTERN" -F '\t' 'BEGIN { OFS="|" }

function to_mi(val) {
   v = val "";
   if (v ~ /[Gg]i?/) { sub(/[Gg]i?/, "", v); return v * 1024 }
   if (v ~ /[Mm]i?/) { sub(/[Mm]i?/, "", v); return v }
   if (v ~ /[Kk]i?/) { sub(/[Kk]i?/, "", v); return v / 1024 }
   return v + 0
}

function to_m(val) {
   v = val "";
   if (v == "" || v == "0" || v == "-" || v == "<nil>") return 0;
   if (v ~ /m/) { sub(/m/, "", v); return v + 0 }
   if (v + 0 < 50) { return v * 1000 }
   return v + 0
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

NR==FNR {
    split($0, a, /[[:space:]]+/);
    u_cpu[a[1]a[2]]=a[3]; u_mem[a[1]a[2]]=a[4];
    next
}

(pattern != "." && $0 !~ pattern) { next }

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
   restart_info = (total_restarts > 0) ? ((time_ago != "") ? time_ago " (" total_restarts ")" : "(" total_restarts ")") : "-";

   cpu_rl = $3 "/" $4;
   mem_rl = $5 "/" $6;

   cpu_perc = sprintf("(%3.1f%% / %3.1f%%)", cp_req, cp_lim);
   mem_perc = sprintf("(%3.1f%% / %3.1f%%)", mp_req, mp_lim);

   # Sort key is now cp_req (Requested CPU %)
   printf "%10.2f|%-12s|%-27.27s|C: %-6s %-12s %-18s|M: %-7s %-12s %-18s|%s\n",
          cp_req, $1, display_pod, u_cpu[$1$2], cpu_rl, cpu_perc, u_mem[$1$2], mem_rl, mem_perc, restart_info
}' <(kubectl top pods -A --no-headers) \
   <(kubectl get pods -A -o json | jq -r '.items[] | select(.status.phase == "Running") |
      def to_ms: if . == null then 0 elif (tostring | endswith("m")) then (tostring[:-1] | tonumber) else (tostring | tonumber * 1000) end;
      def to_mib: if . == null then 0 elif (tostring | endswith("Ki")) then (tostring[:-2] | tonumber / 1024) elif (tostring | endswith("Mi")) then (tostring[:-2] | tonumber) elif (tostring | endswith("Gi")) then (tostring[:-2] | tonumber * 1024) else (tostring | tonumber / 1024 / 1024) end;
      [
         .metadata.namespace,
         .metadata.name,
         ([.spec.containers[].resources.requests.cpu // "0m"] | map(to_ms) | add | tostring + "m"),
         ([.spec.containers[].resources.limits.cpu // "0m"] | map(to_ms) | add | tostring + "m"),
         ([.spec.containers[].resources.requests.memory // "0Mi"] | map(to_mib) | add | tostring + "Mi"),
         ([.spec.containers[].resources.limits.memory // "0Mi"] | map(to_mib) | add | tostring + "Mi"),
         ([.status.containerStatuses[].restartCount // 0] | add | tostring),
         ([.status.containerStatuses[].lastState.terminated.finishedAt // "0"] | sort | last | tostring)
      ] | @tsv') \
| sort -t'|' -k1,1rn | cut -d '|' -f 2- | column -t -s '|' -o ' | '
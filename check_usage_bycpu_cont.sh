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
    if (diff < 0) return "0s";
    if (diff < 60) return diff "s";
    if (diff < 3600) return int(diff/60) "m";
    if (diff < 86400) return int(diff/3600) "h";
    return int(diff/86400) "d";
}

# Match cleanly based on explicit tabs across both inputs
NR==FNR {
    u_cpu[$1$2$3]=$4; u_mem[$1$2$3]=$5;
    next
}

(pattern != "." && $0 !~ pattern) { next }

($1$2$3) in u_cpu {
   uc = to_m(u_cpu[$1$2$3]);
   um = to_mi(u_mem[$1$2$3]);
   rc_val = to_m($4); lc_val = to_m($5);
   mr_val = to_mi($6); ml_val = to_mi($7);

   cp_req = (rc_val > 0) ? (uc / rc_val) * 100 : 0;
   cp_lim = (lc_val > 0) ? (uc / lc_val) * 100 : 0;
   mp_req = (mr_val > 0) ? (um / mr_val) * 100 : 0;
   mp_lim = (ml_val > 0) ? (um / ml_val) * 100 : 0;

   pod_part = $2;
   con_part = $3;

   if (length(pod_part) + length(con_part) + 1 <= 33) {
       display_name = pod_part "/" con_part
   } else {
       p_trim = substr(pod_part, 1, 21);
       c_len = length(con_part);
       if (c_len > 10) {
           c_trim = substr(con_part, c_len - 9);
       } else {
           c_trim = con_part;
       }
       display_name = p_trim ".*" c_trim;
   }

   time_ago = how_long_ago($9);
   raw_restart = ($8 > 0) ? ((time_ago != "") ? time_ago "(" $8 ")" : "(" $8 ")") : "-";
   restart_info = substr(raw_restart, 1, 6);

   cpu_res = sprintf("%-11s", $4"/"$5);
   mem_res = sprintf("%-16s", $6"/"$7);

   printf "%10.2f|%-9.9s| %-33.33s| C: %-5s %-12s (%5.1f%% / %5.1f%%) | M: %-7s %-16s (%5.1f%% / %5.1f%%) | %-6s\n",
          cp_req, $1, display_name, u_cpu[$1$2$3], cpu_res, cp_req, cp_lim, u_mem[$1$2$3], mem_res, mp_req, mp_lim, restart_info
}' <(kubectl top pods -A --containers --no-headers | awk '{print $1"\t"$2"\t"$3"\t"$4"\t"$5}') \
   <(kubectl get pods -A -o json | jq -r '
      def to_ms: tostring | if endswith("m") then .[:-1] | tonumber elif contains(".") or (gsub("[^0-9.]"; "") | tonumber < 50) then (gsub("[^0-9.]"; "") | tonumber * 1000) else (gsub("[^0-9.]"; "") | tonumber) end;
      def to_mib: tostring |
        if endswith("Ki") then (sub("Ki";"") | tonumber / 1024)
        elif endswith("Mi") then (sub("Mi";"") | tonumber)
        elif endswith("Gi") then (sub("Gi";"") | tonumber * 1024)
        elif endswith("G") then (sub("G";"") | tonumber * 1024)
        else (tonumber? // 0 / 1024 / 1024) end;
      .items[] | select(.status.phase == "Running") |
      .metadata.namespace as $ns |
      .metadata.name as $pod |
      (.status.containerStatuses // [] | map({key: .name, value: .}) | from_entries) as $statuses |
      .spec.containers[] |
      .name as $cname |
      $statuses[$cname] as $status |
      [
         $ns,
         $pod,
         $cname,
         (.resources.requests.cpu // "0" | to_ms | tostring | . + "m"),
         (.resources.limits.cpu // "0" | to_ms | tostring | . + "m"),
         (.resources.requests.memory // "0" | to_mib | tostring | . + "Mi"),
         (.resources.limits.memory // "0" | to_mib | tostring | . + "Mi"),
         ($status.restartCount // 0 | tostring),
         ($status.lastState.terminated.finishedAt // "0" | tostring)
      ] | @tsv') \
| sort -t'|' -k1,1rn | cut -d '|' -f 2- | sed 's/|/ /g'
#!/bin/bash
FILTER=$1
MODE=$2  # 'first' or 'all'
NOW=$(date +%s)

if [[ "$FILTER" == "all" || "$FILTER" == "ALL" || -z "$FILTER" ]]; then
    pattern="."
else
    pattern="${FILTER// /[[:space:]]+}"
fi

# Determine JQ index: 0 for first, empty string for all
if [[ "$MODE" == "first" ]]; then
    idx="0"
else
    idx=":" # jq slice [:] means all
fi

awk -v now="$NOW" -v pattern="$pattern" -F '\t' 'BEGIN { OFS="|" }

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

   p_name = $2;
   display_pod = (length(p_name) > 27) ? substr(p_name, 1, 20) ".*" substr(p_name, length(p_name) - 4) : p_name;

   time_ago = how_long_ago($8);
   raw_restart = ($7 > 0) ? ((time_ago != "") ? time_ago "(" $7 ")" : "(" $7 ")") : "-";
   restart_info = substr(raw_restart, 1, 6);

   printf "%10.2f|%-9.9s | %-27.27s | C: %-5s %-12s (%5.1f%% / %5.1f%%) | M: %-7s %-16s (%5.1f%% / %5.1f%%) | %-6s\n",
          mp_req, $1, display_pod, u_cpu[$1$2], $3"/"$4, cp_req, cp_lim, u_mem[$1$2], $5"/"$6, mp_req, mp_lim, restart_info
}' <(kubectl top pods -A --no-headers) \
   <(kubectl get pods -A -o json | jq -r --arg i "$idx" '.items[] | select(.status.phase == "Running") |
      def to_ms: tostring | if endswith("m") then .[:-1] | tonumber elif contains(".") or (gsub("[^0-9.]"; "") | tonumber < 50) then (gsub("[^0-9.]"; "") | tonumber * 1000) else (gsub("[^0-9.]"; "") | tonumber) end;
      def to_mib: tostring | if endswith("Ki") then .[:-2] | tonumber / 1024 elif endswith("Mi") then .[:-2] | tonumber elif endswith("Gi") then .[:-2] | tonumber * 1024 else (gsub("[^0-9.]"; "") | tonumber / 1024 / 1024) end;
      (.spec.containers | if $i == "0" then .[0:1] else . end) as $cs |
      (.status.containerStatuses | if $i == "0" then .[0:1] else . end) as $ss |
      [
         .metadata.namespace,
         .metadata.name,
         ([$cs[].resources.requests.cpu // "0"] | map(to_ms) | add | tostring + "m"),
         ([$cs[].resources.limits.cpu // "0"] | map(to_ms) | add | tostring + "m"),
         ([$cs[].resources.requests.memory // "0"] | map(to_mib) | add | tostring + "Mi"),
         ([$cs[].resources.limits.memory // "0"] | map(to_mib) | add | tostring + "Mi"),
         ([$ss[].restartCount // 0] | add | tostring),
         ([$ss[].lastState.terminated.finishedAt // "0"] | sort | last | tostring)
      ] | @tsv') \
| sort -t'|' -k1,1rn | cut -d '|' -f 2- | sed 's/|/ /g'
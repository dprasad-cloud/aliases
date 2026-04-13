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

# 2. Process and Force 40-char Trim
($1$2) in u_cpu {
   uc=to_m(u_cpu[$1$2]); lc=to_m($3);
   um=to_mi(u_mem[$1$2]); rm=to_mi($4); lm=to_mi($5);

   p_name = $2;
   gsub(/[[:space:]]/, "", p_name);

   # Hard trim to 40
   if (length(p_name) > 40) {
       display_pod = substr(p_name, 1, 37)"..."
   } else {
       display_pod = p_name
   }

   restarts=$6;
   raw_ts=$7;

   restart_info = "";
   if (restarts > 0) {
       time_ago = how_long_ago(raw_ts);
       restart_info = time_ago "(" restarts ")";
   }

   cp=(lc>0)?(uc/lc)*100:0;
   rp=(rm>0)?(um/rm)*100:0;
   lp=(lm>0)?(um/lm)*100:0;

   # %-40.40s enforces the strict 40 character limit
   printf "%-10s | %-40.40s | C: %-5s/%-5s (%3d%%) | M: %-7s | R: %-5s (%3d%%) | L: %-5s (%3d%%) | %s\n",
          $1, display_pod, u_cpu[$1$2], $3, cp, u_mem[$1$2], $4, rp, $5, lp, restart_info
}' <(kubectl top pods -A --no-headers | $GREP_CMD | awk '{print $1"\t"$2"\t"$3"\t"$4}') \
   <(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[0].resources.limits.cpu}{"\t"}{.spec.containers[0].resources.requests.memory}{"\t"}{.spec.containers[0].resources.limits.memory}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.status.containerStatuses[0].lastState.terminated.finishedAt}{"\n"}{end}' | $GREP_CMD) \
| column -t -s '|'
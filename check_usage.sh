FILTER=$1
awk 'BEGIN {OFS=" | "}
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
NR==FNR {u_cpu[$1$2]=$3; u_mem[$1$2]=$4; next}
($1$2) in u_cpu {
   uc=to_m(u_cpu[$1$2]); lc=to_m($3);
   um=to_mi(u_mem[$1$2]); rm=to_mi($4); lm=to_mi($5);
   cp=(lc>0)?(uc/lc)*100:0;
   rp=(rm>0)?(um/rm)*100:0;
   lp=(lm>0)?(um/lm)*100:0;
   printf "%-10s | %-35s | C: %-5s / %-5s (%3d%%) | M: %-7s | R: %-5s (%3d%%) | L: %-5s (%3d%%)\n", $1, $2, u_cpu[$1$2], $3, cp, u_mem[$1$2], $4, rp, $5, lp
}' <(kubectl top pods -A --no-headers | grep "$FILTER") <(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[0].resources.limits.cpu}{" "}{.spec.containers[0].resources.requests.memory}{" "}{.spec.containers[0].resources.limits.memory}{"\n"}{end}' | grep "$FILTER") | column -t -s '|'

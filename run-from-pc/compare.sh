#!/bin/bash

# Set these inputs before running: (or export them in the environment)
# TB1="ws3"; NS1="common"; TB2="xcp8"; NS2="commongdc"; export TB1 TB2 NS1 NS2
# NS1=A for all namespaces in TB1, NS2=A for all namespaces in TB2. Otherwise specify a single namespace for each.

# Internal temp files
TMP1="/tmp/tb1_res.txt"
TMP2="/tmp/tb2_res.txt"

# --- DATA COLLECTION ---
for i in 1 2; do
    if [ $i -eq 1 ]; then
        SSH_TARGET="dprasad@${TB1}-console.qa.xcloudiq.com"
        CURRENT_NS="$NS1"; OUTPUT_FILE="$TMP1"
    else
        SSH_TARGET="dprasad@${TB2}-console.qa.xcloudiq.com"
        CURRENT_NS="$NS2"; OUTPUT_FILE="$TMP2"
    fi

    [[ "$CURRENT_NS" == "A" ]] && NS_FLAG="--all-namespaces" || NS_FLAG="-n $CURRENT_NS"

    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_TARGET" \
    "sudo su - -c \"kubectl get pods $NS_FLAG --field-selector=status.phase=Running --v=0 -o jsonpath='{range .items[*]}{.metadata.name}{\\\"\\\\t\\\"}{range .spec.containers[*]}{.resources.requests.cpu}{\\\" \\\"}{.resources.limits.cpu}{\\\" \\\"}{.resources.requests.memory}{\\\" \\\"}{.resources.limits.memory}{\\\"\\\\n\\\"}{end}{end}' 2>/dev/null\"" | \
    awk '
    function to_num(val) {
        if (val == "" || val == " ") return 0;
        if (val ~ /Gi$/) return substr(val, 1, length(val)-2) * 1024;
        if (val ~ /Mi$/) return substr(val, 1, length(val)-2);
        if (val ~ /m$/) return substr(val, 1, length(val)-1);
        if (val ~ /^[0-9.]+$/) return val * 1000;
        return 0;
    }
    {
        if ($1 ~ /^[0-9]+/ || $1 == "") next;
        g = $1; gsub(/\r/, "", g);
        if (g !~ /-[0-9]+$/) sub(/-[^-]+-[^-]+$/, "", g);
        while (g ~ /-[0-9]+$/) sub(/-[0-9]+$/, "", g);

        # TRIM to 60 chars
        g = substr(g, 1, 60);

        cpu_req[g] += to_num($2); cpu_lim[g] += to_num($3);
        mem_req[g] += to_num($4); mem_lim[g] += to_num($5);
        count[g]++;
    }
    END { for (k in cpu_req) print k"\t"cpu_req[k]"\t"cpu_lim[k]"\t"mem_req[k]"\t"mem_lim[k]"\t"count[k] }' > "$OUTPUT_FILE"
done

# --- COMPARISON ---
export TB1 TB2
awk '
BEGIN {
    s1 = toupper(ENVIRON["TB1"]); s2 = toupper(ENVIRON["TB2"]);

    printf "\n%-60s | %-26s | %-26s | %-26s | %-26s\n", "GROUP (Trimmed)", "CPU REQUEST (m)", "CPU LIMIT (m)", "MEM REQUEST (Mi)", "MEM LIMIT (Mi)";
    printf "%-60s | %-12s %-12s | %-12s %-12s | %-12s %-12s | %-12s %-12s\n",
           "------------------------------------------------------------", s1 " (R)", s2 " (R)", s1 " (R)", s2 " (R)", s1 " (R)", s2 " (R)", s1 " (R)", s2 " (R)";
}
NR==FNR {
    cr1[$1]=$2; cl1[$1]=$3; mr1[$1]=$4; ml1[$1]=$5; rep1[$1]=$6; keys[$1]=1; next
}
{
    cr2[$1]=$2; cl2[$1]=$3; mr2[$1]=$4; ml2[$1]=$5; rep2[$1]=$6; keys[$1]=1;
}
END {
    n = asorti(keys, sorted_keys);
    for (i = 1; i <= n; i++) {
        k = sorted_keys[i];
        v1_cr = sprintf("%d (%d)", cr1[k], rep1[k]); v2_cr = sprintf("%d (%d)", cr2[k], rep2[k]);
        v1_cl = sprintf("%d (%d)", cl1[k], rep1[k]); v2_cl = sprintf("%d (%d)", cl2[k], rep2[k]);
        v1_mr = sprintf("%d (%d)", mr1[k], rep1[k]); v2_mr = sprintf("%d (%d)", mr2[k], rep2[k]);
        v1_ml = sprintf("%d (%d)", ml1[k], rep1[k]); v2_ml = sprintf("%d (%d)", ml2[k], rep2[k]);

        printf "%-60s | %-12s %-12s | %-12s %-12s | %-12s %-12s | %-12s %-12s\n",
               k, v1_cr, v2_cr, v1_cl, v2_cl, v1_mr, v2_mr, v1_ml, v2_ml;
    }
    printf "\n"
}' "$TMP1" "$TMP2"

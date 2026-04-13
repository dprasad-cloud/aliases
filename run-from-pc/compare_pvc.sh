#!/bin/bash

# Set these inputs before running: (or export them in the environment)
# TB1="ws3"; NS1="common"; TB2="xcp8"; NS2="commongdc"; export TB1 TB2 NS1 NS2
# NS1=A for all namespaces in TB1, NS2=A for all namespaces in TB2. Otherwise specify a single namespace for each.

# Internal temp files
TMP1="/tmp/tb1_pvc_res.txt"
TMP2="/tmp/tb2_pvc_res.txt"

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
    "sudo su - -c \"kubectl get pvc $NS_FLAG --v=0 -o jsonpath='{range .items[*]}{.metadata.name}{\\\"\\\\t\\\"}{.spec.resources.requests.storage}{\\\"\\\\n\\\"}{end}' 2>/dev/null\"" | \
    awk '
    function to_gb(val) {
        if (val ~ /Gi$/) return substr(val, 1, length(val)-2);
        if (val ~ /Mi$/) return substr(val, 1, length(val)-2) / 1024;
        if (val ~ /Ti$/) return substr(val, 1, length(val)-2) * 1024;
        if (val ~ /^[0-9.]+$/) return val;
        return 0;
    }
    {
        g = $1; gsub(/\r/, "", g);
        if (g !~ /-[0-9]+$/) sub(/-[^-]+-[^-]+$/, "", g);
        while (g ~ /-[0-9]+$/) sub(/-[0-9]+$/, "", g);

        # TRIM to 60 chars
        g = substr(g, 1, 60);

        storage[g] += to_gb($2);
        count[g]++;
    }
    END { for (k in storage) print k"\t"storage[k]"\t"count[k] }' > "$OUTPUT_FILE"
done

# --- COMPARISON ---
export TB1 TB2
awk '
BEGIN {
    s1 = toupper(ENVIRON["TB1"]); s2 = toupper(ENVIRON["TB2"]);

    printf "\n%-60s | %-22s | %-22s | %-10s\n", "PVC GROUP (Trimmed)", s1 " STORAGE (Gi)", s2 " STORAGE (Gi)", "DIFF (Gi)";
    printf "%-60s | %-10s %-11s | %-10s %-11s | %-10s\n",
           "------------------------------------------------------------", "Total", "(Qty)", "Total", "(Qty)", "----------";
}
NR==FNR {
    st1[$1]=$2; qty1[$1]=$3; keys[$1]=1; next
}
{
    st2[$1]=$2; qty2[$1]=$3; keys[$1]=1;
}
END {
    n = asorti(keys, sorted_keys);
    for (i = 1; i <= n; i++) {
        k = sorted_keys[i];
        v1_disp = sprintf("%7.1f  x%-3d", st1[k], qty1[k]);
        v2_disp = sprintf("%7.1f  x%-3d", st2[k], qty2[k]);
        diff = st2[k] - st1[k];

        printf "%-60s | %-22s | %-22s | %-10.1f\n",
               k, v1_disp, v2_disp, diff;
    }
    printf "\n"
}' "$TMP1" "$TMP2"

#!/bin/bash

# If an argument is provided, use the alias logic
if [ -n "$1" ]; then
    shopt -s expand_aliases
    alias fpod='/root/aliases-main/findpod.sh'
    eval "fpod \"$1\"" | "$0"
    exit 0
fi

# Parse input pods safely into namespace/pod format
if [ -t 0 ] && [ ! -p /dev/stdin ]; then
    POD_LIST=$(kubectl get pods -A --no-headers -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}')
else
    POD_LIST=$(awk '{if ($1 && $2 && $1 != "NAMESPACE") print $1"/"$2}')
fi

# Process pods with a hard Linux-level timeout
echo "$POD_LIST" | xargs -I {} -P 5 bash -c '
    ns_pod="{}"
    ns="${ns_pod%/*}"
    pod="${ns_pod#*/}"

    # Use the Linux "timeout" utility to forcefully kill kubectl after 4 seconds if it freezes
    disk_info=$(timeout 4s kubectl exec "$pod" -n "$ns" -- df -h 2>/dev/null | grep -iE "kafka|data|/dev/sd|/dev/nvme" | grep -v "Filesystem")

    if [ -n "$disk_info" ]; then
        echo "$disk_info" | awk -v ns="$ns" -v pod="$pod" '\''BEGIN{OFS="\t"} {print ns, pod, $1, $2, $3, $4, $5, $6}'\''
    fi
' | sort -t$'\t' -k7,7n 2>/dev/null | column -t -s $'\t'
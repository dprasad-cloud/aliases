#!/bin/bash

# If an argument is provided, use the alias logic
if [ -n "$1" ]; then
    shopt -s expand_aliases
    alias fpod='/root/aliases-main/findpod.sh'
    eval "fpod \"$1\"" | "$0"
    exit 0
fi

# Detect if stdin is empty (not piped)
if [ -t 0 ]; then
    # No pipe detected; list all pods as default
    exec kubectl get pods -A --no-headers | "$0"
fi

last_pod=""

# We wrap the output loop in a block so we can pipe the whole thing to 'column'
{
    # Print the header (tab-separated for the column command)
    echo -e "NAMESPACE\tPOD\tFILESYSTEM\tSIZE\tUSED\tAVAIL\tUSE%\tMOUNTED_ON"

    while read -r ns pod rest; do
        [[ "$ns" == "NAMESPACE" || \
           "$ns" == "command(s):" || \
           "$ns" == "kubectl" || \
           -z "$ns" || \
           -z "$pod" || \
           "$rest" == *"Completed"* ]] && continue

        disk_info=$(kubectl exec "$pod" -n "$ns" -- df -h 2>/dev/null | \
                    grep -iE 'kafka|data|/dev/sd|/dev/nvme' | \
                    grep -v "Filesystem")

        if [[ -n "$disk_info" ]]; then
            # If the pod changes, we can insert a visual indicator line
            if [[ -n "$last_pod" && "$pod" != "$last_pod" ]]; then
                # Repeating tabs tells 'column' to leave this row empty or draw a separator
                echo -e "-\t-\t-\t-\t-\t-\t-\t-"
            fi
            last_pod="$pod"

            # Pass fields separated by tabs
            echo "$disk_info" | awk -v ns="$ns" -v pod="$pod" 'BEGIN{OFS="\t"} {
                print ns, pod, $1, $2, $3, $4, $5, $6
            }'
        fi
    done
} | column -t -s $'\t'
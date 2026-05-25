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

# Print the header immediately
printf "\n%-12s %-35s %-20s %-7s %-7s %-7s %-5s %-20s\n" \
    "NAMESPACE" "POD" "FILESYSTEM" "SIZE" "USED" "AVAIL" "USE%" "MOUNTED_ON"
echo "------------------------------------------------------------------------------------------------------------------------"

last_pod=""

while read -r ns pod rest; do
    # Skip headers, empty lines, or completed pods
    [[ "$ns" == "NAMESPACE" || -z "$ns" || -z "$pod" || "$rest" == *"Completed"* ]] && continue

    # Capture disk info
    disk_info=$(kubectl exec "$pod" -n "$ns" -- df -h 2>/dev/null | \
                grep -iE 'kafka|data|/dev/sd|/dev/nvme' | \
                grep -v "Filesystem")

    if [[ -n "$disk_info" ]]; then
        # Print separator if pod changed
        if [[ -n "$last_pod" && "$pod" != "$last_pod" ]]; then
            echo "------------------------------------------------------------------------------------------------------------------------"
        fi
        last_pod="$pod"

        # Print formatted rows
        echo "$disk_info" | awk -v ns="$ns" -v pod="$pod" '{
            printf "%-12s %-35s %-20s %-7s %-7s %-7s %-5s %-20s\n", \
            ns, substr(pod,1,45), $1, $2, $3, $4, $5, $6
        }'
    fi
done

echo "  "
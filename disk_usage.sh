#!/bin/bash

# 1. IMPORTANT: Enable alias expansion inside this script
shopt -s expand_aliases

disk_usage() {
    # If an argument is provided, execute findpod and pipe it back
    if [ -n "$1" ]; then
        eval "findpod \"$1\"" | disk_usage
        return
    fi

    # Print the header immediately for "live" feel
    printf "\n%-12s %-45s %-20s %-7s %-7s %-7s %-5s %-20s\n" \
        "NAMESPACE" "POD" "FILESYSTEM" "SIZE" "USED" "AVAIL" "USE%" "MOUNTED_ON"
    echo "------------------------------------------------------------------------------------------------------------------------"

    local last_pod=""

    while read -r ns pod rest; do
        # Skip headers, empty lines, or completed pods
        [[ "$ns" == "NAMESPACE" || -z "$ns" || -z "$pod" || "$rest" == *"Completed"* ]] && continue

        # Capture disk info first to see if pod has relevant storage
        local disk_info=$(kubectl exec "$pod" -n "$ns" -- df -h 2>/dev/null | \
                         grep -iE 'kafka|data|/dev/sd|/dev/nvme' | \
                         grep -v "Filesystem")

        if [[ -n "$disk_info" ]]; then
            # Print separator if pod changed
            if [[ -n "$last_pod" && "$pod" != "$last_pod" ]]; then
                echo "------------------------------------------------------------------------------------------------------------------------"
            fi
            last_pod="$pod"

            # Print formatted rows immediately
            echo "$disk_info" | awk -v ns="$ns" -v pod="$pod" '{
                printf "%-12s %-45s %-20s %-7s %-7s %-7s %-5s %-20s\n", \
                ns, substr(pod,1,45), $1, $2, $3, $4, $5, $6
            }'
        fi
    done
}
#!/bin/bash

# If an argument is provided, use the alias logic
if [ -n "$1" ]; then
    shopt -s expand_aliases
    alias fpod='/root/aliases-main/findpod.sh'
    eval "fpod \"$*\"" | "$0"
    exit 0
fi

# Parse input pods safely into namespace/pod format
if [ -t 0 ] && [ ! -p /dev/stdin ]; then
    POD_LIST=$(kubectl get pods -A --no-headers -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}')
else
    POD_LIST=$(awk '{
        if ($1 ~ /\//) { print $1 }
        else if ($1 && $2 && $1 != "NAMESPACE") { print $1"/"$2 }
    }')
fi

if [ -z "$POD_LIST" ]; then
    echo "DEBUG: POD_LIST is empty. The input parser failed to read from fpod."
    exit 1
fi

# Process pods and show all filesystems without any filtering
echo "$POD_LIST" | xargs -I {} -P 5 bash -c '
    ns_pod="{}"
    ns="${ns_pod%/*}"
    pod="${ns_pod#*/}"

    # Fetch running containers
    running_containers=$(timeout 5s kubectl get pod "$pod" -n "$ns" -o jsonpath="{range .status.containerStatuses[?(@.state.running)]}{.name}{\"\n\"}{end}" 2>/dev/null)

    if [ -z "$running_containers" ]; then
        echo "DEBUG: Could not fetch running containers for pod $ns/$pod"
    fi

    for container in $running_containers; do
        [ -z "$container" ] && continue

        # DIAGNOSTIC: Removed 2>/dev/null and removed the pattern matching grep completely
        disk_info=$(timeout 5s kubectl exec "$pod" -n "$ns" -c "$container" -- df -h 2>&1 | grep -v "Filesystem")

        if [ -n "$disk_info" ]; then
            echo "$disk_info" | awk -v ns="$ns" -v pod="$pod" -v container="$container" '\''
                BEGIN { OFS="\t" }
                {
                    # --- Truncate Pod Name (Max 33) ---
                    display_pod = pod
                    if (length(pod) > 33) {
                        suffix_pod = substr(pod, length(pod) - 4)
                        prefix_pod = substr(pod, 1, 26)
                        if (substr(prefix_pod, length(prefix_pod)) == "-") {
                            prefix_pod = substr(prefix_pod, 1, 25)
                        }
                        display_pod = prefix_pod ".*" suffix_pod
                    }

                    # --- Truncate Container Name (Max 27) ---
                    display_container = container
                    if (length(container) > 27) {
                        suffix_con = substr(container, length(container) - 4)
                        prefix_con = substr(container, 1, 20)
                        if (substr(prefix_con, length(prefix_con)) == "-") {
                            prefix_con = substr(prefix_con, 1, 19)
                        }
                        display_container = prefix_con ".*" suffix_con
                    }

                    print ns, display_pod, display_container, $0
                }
        	'\''
        fi
    done
' | sort -t$'\t' -k8,8n 2>/dev/null | column -t -s $'\t'
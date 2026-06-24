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
    # Clean out "kubectl", "get", and headers from pipeline input
    POD_LIST=$(awk '$1 && $2 && $1 != "NAMESPACE" && $1 !~ /kubectl|get/ {
        if ($1 ~ /\//) { print $1 }
        else { print $1"/"$2 }
    }')
fi

if [ -z "$POD_LIST" ]; then
    exit 0
fi

# Count total pods to evaluate execution delay warning
TOTAL_PODS=$(echo "$POD_LIST" | grep -c '^')

if [ "$TOTAL_PODS" -gt 20 ]; then
    echo "# !!! Running checkdisk on more apps can take up to 40 sec"
fi

# Process pods cleanly
echo "$POD_LIST" | xargs -I {} -P 5 bash -c '
    ns_pod="{}"
    ns="${ns_pod%/*}"
    pod="${ns_pod#*/}"

    # Get only the names of containers that are currently in a "running" state
    running_containers=$(timeout 3s kubectl get pod "$pod" -n "$ns" -o jsonpath="{range .status.containerStatuses[?(@.state.running)]}{.name}{\"\n\"}{end}" 2>/dev/null)

    if [ -z "$running_containers" ]; then
        echo -e "${ns}\t${pod}\t---\t[DEBUG: Unable to fetch running containers or pod not ready]"
        exit 0
    fi

    for container in $running_containers; do
        [ -z "$container" ] && continue

        # Capture raw execution output including errors
        exec_output=$(timeout 4s kubectl exec "$pod" -n "$ns" -c "$container" -- df -h 2>&1)
        exec_status=$?

        # Handle errors or timeouts explicitly
        if [ $exec_status -ne 0 ] || [ -z "$exec_output" ]; then
            error_msg=$(echo "$exec_output" | tr "\n" " " | cut -c1-50)
            [ -z "$error_msg" ] && error_msg="Timeout or empty response"
            echo -e "${ns}\t${pod}\t${container}\t[DEBUG Exec Failed: ${error_msg}]"
            continue
        fi

        # Filter out system paths and headers from successful execution
        disk_info=$(echo "$exec_output" | grep -iE "kafka|data|redis|helm|/dev/sd|/dev/nvme|overlay" | grep -vE "Filesystem|/proc|/sys|/etc|termination-log")

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

                    print ns, display_pod, display_container, $1, $2, $3, $4, $5, $6
                }
        	'\''
        fi
    done
' | sort -t$'\t' -k8,8n 2>/dev/null | column -t -s $'\t'
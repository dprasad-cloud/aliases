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

    # Fetch all container names for the pod
    containers=$(timeout 5s kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[*].name}" 2>/dev/null)

    if [ -z "$containers" ]; then
        echo -e "${ns}\t${pod}\t---\t[ERR: Pod specs/API timeout]\t-\t-\t-\t-\t-"
        exit 0
    fi

    for container in $containers; do
        [ -z "$container" ] && continue

        # Capture raw execution output
        exec_output=$(timeout 5s kubectl exec "$pod" -n "$ns" -c "$container" -- df -h 2>&1)

        # FIXED: Only fail if output is completely empty or explicitly contains a runtime error
        if [ -z "$exec_output" ] || echo "$exec_output" | grep -qE "executable file not found|OCI runtime|Permission denied|Error from server"; then
            error_msg=$(echo "$exec_output" | tr "\n" " " | sed "s/  */ /g")
            [ -z "$error_msg" ] && error_msg="Timeout/Empty response"
            error_msg=$(echo "$error_msg" | awk '\''{print substr($0, 1, 30)}'\'')

            echo -e "${ns}\t${pod}\t${container}\t[ERR: ${error_msg}]\t-\t-\t-\t-\t-"
            continue
        fi

        # Filter out system paths and headers from execution
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
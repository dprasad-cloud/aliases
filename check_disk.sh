#!/bin/bash

# If an argument is provided, use the alias logic
if [ -n "$1" ]; then
    shopt -s expand_aliases
    alias fpod='/root/aliases-main/findpod.sh'
    eval "fpod \"$*\"" | "$0"
    exit 0
fi

# Parse input pods safely into namespace/pod/containers format
if [ -t 0 ] && [ ! -p /dev/stdin ]; then
    # Single optimized API call pulling Namespace, Pod Name, and all Containers space-separated
    POD_LIST=$(kubectl get pods -A --no-headers -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"/"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}')
else
    # Incoming pipeline data from fpod (space-separated output)
    # Filter out internal "kubectl/get" loop lines
    RAW_INPUT=$(awk '$1 && $2 && $1 != "NAMESPACE" && $1 !~ /kubectl|get/ {
        if ($1 ~ /\//) { print $1 }
        else { print $1"/"$2 }
    }')

    # Resolve containers for piped pods using a single bulk query to avoid throttling
    if [ -n "$RAW_INPUT" ]; then
        POD_LIST=$(kubectl get pods -A --no-headers -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"/"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}' | grep -Ff <(echo "$RAW_INPUT"))
    fi
fi

if [ -z "$POD_LIST" ]; then
    exit 0
fi

# Count total target items
TOTAL_PODS=$(echo "$POD_LIST" | grep -c '^')

if [ "$TOTAL_PODS" -gt 20 ]; then
    echo "# !!! Running checkdisk on more apps can take up to 40 sec"
fi

# Process pods cleanly without hitting metadata API bottlenecks inside the loop
echo "$POD_LIST" | xargs -I {} -P 5 bash -c '
    line="{}"
    ns_pod="${line%/*}"
    ns="${ns_pod%/*}"
    pod="${ns_pod#*/}"
    containers="${line##*/}"

    for container in $containers; do
        [ -z "$container" ] && continue

        # Capture raw execution output with a safe 6-second threshold
        exec_output=$(timeout 6s kubectl exec "$pod" -n "$ns" -c "$container" -- df -h 2>&1)

        # Handle explicit connectivity errors or empty responses
        if [ -z "$exec_output" ] || echo "$exec_output" | grep -qE "executable file not found|OCI runtime|Permission denied|Error from server"; then
            error_msg=$(echo "$exec_output" | tr "\n" " " | sed "s/  */ /g")
            [ -z "$error_msg" ] && error_msg="Timeout/Empty response"
            error_msg=$(echo "$error_msg" | awk '\''{print substr($0, 1, 30)}'\'')

            echo -e "${ns}\t${pod}\t${container}\t[ERR: ${error_msg}]\t-\t-\t-\t-\t-"
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
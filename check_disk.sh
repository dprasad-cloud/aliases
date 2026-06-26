#!/bin/bash

# If an argument is provided, use the alias logic
if [ -n "$1" ]; then
    shopt -s expand_aliases
    alias fpod='/root/aliases-main/findpod.sh'
    eval "fpod \"$*\"" | "$0"
    exit 0
fi

# Parse input pods safely into namespace/pod/containers format (Running only)
if [ -t 0 ] && [ ! -p /dev/stdin ]; then
    POD_LIST=$(kubectl get pods -A --field-selector=status.phase=Running --no-headers -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"/"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}')
else
    # Incoming pipeline data from fpod (space-separated output)
    RAW_INPUT=$(awk '$1 && $2 && $1 != "NAMESPACE" && $1 !~ /kubectl|get/ {
        if ($1 ~ /\//) { print $1 }
        else { print $1"/"$2 }
    }')

    # Resolve containers for piped pods using a single bulk query (Running only)
    if [ -n "$RAW_INPUT" ]; then
        POD_LIST=$(kubectl get pods -A --field-selector=status.phase=Running --no-headers -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"/"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}' | grep -Ff <(echo "$RAW_INPUT"))
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

# Process pods cleanly with high-tolerance parallel processing thresholds
echo "$POD_LIST" | xargs -I {} -P 5 bash -c '
    line="{}"
    ns_pod="${line%/*}"
    ns="${ns_pod%/*}"
    pod="${ns_pod#*/}"
    containers="${line##*/}"

    for container in $containers; do
        [ -z "$container" ] && continue

        # INCREASED TIMEOUT: Raised to 15 seconds to completely eliminate cluster/API latency drops
        exec_output=$(timeout 15s kubectl exec "$pod" -n "$ns" -c "$container" -- df -h 2>&1)
        exit_code=$?

        # --- Truncate Pod Name (Max 35) ---
        display_pod="$pod"
        if [ ${#pod} -gt 35 ]; then
            suffix_pod="${pod: -4}"
            prefix_pod="${pod:0:28}"
            [[ "${prefix_pod: -1}" == "-" ]] && prefix_pod="${pod:0:27}"
            display_pod="${prefix_pod}.*${suffix_pod}"
        fi

        if [ $exit_code -eq 0 ]; then
            # Filter out system paths and headers from execution
            disk_info=$(echo "$exec_output" | grep -iE "kafka|data|redis|helm|/dev/sd|/dev/nvme" | grep -vE "Filesystem|/proc|/sys|/etc|termination-log")

            if [ -n "$disk_info" ]; then
                echo "$disk_info" | awk -v ns="$ns" -v pod="$display_pod" -v container="$container" '\''
                    BEGIN { OFS="\t" }
                    {
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

                        print ns, pod, display_container, $1, $2, $3, $4, $5, $6
                    }
                '\''
            else
                # Command succeeded, but matches were ignored by grep filters (Clamped to 35 chars)
                msg="[No matching disks]"
                echo -e "${ns}\t${display_pod}\t${container}\t${msg:0:35}\t-\t-\t-\t-\t-"
            fi
        else
            # True execution failure (Timeout or API drops)
            if [ $exit_code -eq 124 ]; then
                error_msg="[ERR: Execution Timeout (15s)]"
            else
                clean_err=$(echo "$exec_output" | tr "\n" " " | sed "s/  */ /g")
                [ -z "$clean_err" ] && clean_err="Unknown Exec Error"
                error_msg="[ERR: ${clean_err}]"
            fi

            # Clamp error text layout strictly to 35 characters
            echo -e "${ns}\t${display_pod}\t${container}\t${error_msg:0:35}\t-\t-\t-\t-\t-"
        fi
    done
' | sort -t$'\t' -k8,8n 2>/dev/null | column -t -s $'\t'
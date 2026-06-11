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

    # Get only the names of containers that are currently in a "running" state
    running_containers=$(timeout 3s kubectl get pod "$pod" -n "$ns" -o jsonpath="{range .status.containerStatuses[?(@.state.running)]}{.name}{\"\n\"}{end}" 2>/dev/null)

    for container in $running_containers; do
        [ -z "$container" ] && continue

        # Execute df -h explicitly specifying the container via "-c"
        disk_info=$(timeout 4s kubectl exec "$pod" -n "$ns" -c "$container" -- df -h 2>/dev/null | grep -iE "kafka|data|/dev/sd|/dev/nvme|helm" | grep -v "Filesystem")

        if [ -n "$disk_info" ]; then
            echo "$disk_info" | awk -v ns="$ns" -v pod="$pod" -v container="$container" '\''BEGIN{OFS="\t"} {print ns, pod, container, $1, $2, $3, $4, $5, $6}'\''
        fi
    done
' | sort -t$'\t' -k8,8n 2>/dev/null | column -t -s $'\t'
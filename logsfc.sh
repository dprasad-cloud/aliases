#!/bin/bash

# Generic Pod Logs Display Script (container-aware)
# Finds the first pod matching the search term and streams logs from a specific container.

SEARCH_TERM="$1"
CONTAINER_NAME="$2"

if [ -z "$SEARCH_TERM" ] || [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: logsf_container <search_term> <container_name>"
    exit 1
fi

echo "--- Searching for the FIRST pod containing '$SEARCH_TERM' ---"

# List all pods in all namespaces and pick the first matching line.
POD_INFO=$(kubectl get pod -A | grep "$SEARCH_TERM" | head -n 1)

if [ -z "$POD_INFO" ]; then
    echo "ERROR: No pod found matching '$SEARCH_TERM'."
    exit 1
fi

# Extract namespace and pod name from the selected row.
NAMESPACE=$(echo "$POD_INFO" | awk '{print $1}')
POD_NAME=$(echo "$POD_INFO" | awk '{print $2}')
LOG_CMD="kubectl logs -f $POD_NAME -n $NAMESPACE -c $CONTAINER_NAME"

# Validate that the container exists in the selected pod.
CONTAINERS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{range .spec.initContainers[*]}{.name}{\"\\n\"}{end}{range .spec.containers[*]}{.name}{\"\\n\"}{end}')
if ! echo "$CONTAINERS" | grep -Fxq "$CONTAINER_NAME"; then
    echo "ERROR: Container '$CONTAINER_NAME' not found in pod '$POD_NAME'."
    echo "Available containers:"
    echo "$CONTAINERS" | sed '/^$/d' | sed 's/^/  - /'
    exit 1
fi

echo "--------------------------------------------------------"
echo "SELECTED POD: $POD_NAME"
echo "NAMESPACE: $NAMESPACE"
echo "CONTAINER: $CONTAINER_NAME"
echo "--------------------------------------------------------"
echo "command(s): $LOG_CMD"
echo "--------------------------------------------------------"

sleep 1

print_log_command() {
    echo
    echo "--- Pod container logs displayed ---"
    echo
    echo "command(s):"
    echo "    $LOG_CMD"
    echo
}

on_interrupt() {
    echo
    echo "--- log streaming interrupted (Ctrl+C) ---"
    print_log_command
    exit 130
}

trap on_interrupt INT

# Stream logs from the selected container.
kubectl logs -f "$POD_NAME" -n "$NAMESPACE" -c "$CONTAINER_NAME"

trap - INT
print_log_command


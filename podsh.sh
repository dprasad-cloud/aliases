#!/bin/bash

# Generic Pod Bash Access Script
# This script finds the first RUNNING pod matching the search term,
# displays its details, and opens an interactive bash session.

# $1 is the search term (e.g., 'teconfig')
SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: podbash <search_term>"
    exit 1
fi

echo "--- Searching for the FIRST RUNNING pod containing '$SEARCH_TERM' ---"

# Use 'kubectl get pod -A' to list all pods across all namespaces.
# Filter by the search term, then filter again to ensure it is 'Running',
# and finally use 'head -n 1' to select only the first result.
POD_INFO=$(kubectl get pod -A | grep "$SEARCH_TERM" | grep 'Running' | head -n 1)

if [ -z "$POD_INFO" ]; then
    echo "ERROR: No RUNNING pod found matching '$SEARCH_TERM'."
    exit 1
fi

# Use awk to safely extract the Namespace (column 1) and Pod Name (column 2)
NAMESPACE=$(echo "$POD_INFO" | awk '{print $1}')
POD_NAME=$(echo "$POD_INFO" | awk '{print $2}')

echo "--------------------------------------------------------"
echo "SELECTED POD: $POD_NAME"
echo "NAMESPACE: $NAMESPACE"
echo "STATUS: Running"
echo "--------------------------------------------------------"
echo "Executing: kubectl exec -it $POD_NAME -n $NAMESPACE -- sh"
echo "--------------------------------------------------------"

# Introduce a 1-second pause for confirmation
sleep 1

# Execute the kubectl exec command
kubectl exec -it "$POD_NAME" -n "$NAMESPACE" -- bash

echo "--- Pod bash session terminated ---"
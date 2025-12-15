#!/bin/bash

# Generic Pod Logs Display Script
# This script finds the first pod matching the search term
# and prints its standard logs (kubectl logs).

# $1 is the search term (e.g., 'teconfig')
SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: podlogs <search_term>"
    exit 1
fi

echo "--- Searching for the FIRST pod containing '$SEARCH_TERM' ---"

# Use 'kubectl get pod -A' to list all pods across all namespaces.
# Filter by the search term
# and finally use 'head -n 1' to select only the first result.
POD_INFO=$(kubectl get pod -A | grep "$SEARCH_TERM" | head -n 1)

if [ -z "$POD_INFO" ]; then
    echo "ERROR: No pod found matching '$SEARCH_TERM'."
    exit 1
fi

# Use awk to safely extract the Namespace (column 1) and Pod Name (column 2)
NAMESPACE=$(echo "$POD_INFO" | awk '{print $1}')
POD_NAME=$(echo "$POD_INFO" | awk '{print $2}')

# --- Logic: Calculate the base application name by conditionally stripping IDs ---
# This three-part pipe handles all common Kubernetes suffixes:
# 1. Strips the 5-char unique pod ID (e.g., -pkrkp)
# 2. Strips the 9-10 char ReplicaSet hash (e.g., -64cfcb79f)
# 3. Strips a final numerical index (e.g., -0 for StatefulSets)
BASE_NAME=$(echo "$POD_NAME" | sed -E 's/-[a-z0-9]{5}$//' | sed -E 's/-[a-f0-9]{9,10}$//' | sed -E 's/-[0-9]+$//')

echo "--------------------------------------------------------"
echo "SELECTED POD: $POD_NAME"
echo "BASE APPLICATION: $BASE_NAME"
echo "NAMESPACE: $NAMESPACE"
echo "--------------------------------------------------------"
echo "Executing: kubectl logs $POD_NAME -n $NAMESPACE"
echo "--------------------------------------------------------"

# Introduce a 1-second pause for confirmation
sleep 1

# Execute the kubectl logs command
kubectl logs "$POD_NAME" -n "$NAMESPACE"

echo -e "\n--- Pod logs displayed ---"
echo -e "\n Executed: kubectl logs $POD_NAME -n $NAMESPACE"
echo -e "\n"

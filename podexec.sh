#!/bin/bash

# Generic Pod Execute Command Script
# This script finds the first RUNNING pod matching the search term
# and executes an arbitrary command inside it (kubectl exec).

# $1 is the search term (e.g., 'temon')
SEARCH_TERM="$1"

# --- FIX: Use 'shift' to robustly capture all remaining arguments as the command ---
# 1. Check if SEARCH_TERM is provided.
if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: podexec <search_term> <command>"
    echo "Example: podexec temon ls -l /var/log"
    exit 1
fi

# 2. Shift positionals: Discard $1 (the SEARCH_TERM). Arguments $2, $3, etc. become $1, $2, etc.
shift

# 3. Capture all remaining arguments (now $@) into the COMMAND variable.
# The double-quotes here ensure spaces are preserved, resulting in a single string.
COMMAND="$@"

if [ -z "$COMMAND" ]; then
    echo "Usage: podexec <search_term> <command>"
    echo "Example: podexec temon ls -l /var/log"
    echo "Example: podexec teconfig cat /etc/config/app.conf"
    exit 1
fi
# ----------------------------------------------------------------------------------

echo "--- Searching for the FIRST RUNNING pod containing '$SEARCH_TERM' (Case-Insensitive Regex) ---"

# Use 'kubectl get pod -A' to list all pods across all namespaces.
# Filter case-insensitively by the search term, then filter again to ensure it is 'Running',
# and finally use 'head -n 1' to select only the first result.
POD_INFO=$(kubectl get pod -A | grep -i "$SEARCH_TERM" | grep 'Running' | head -n 1)

if [ -z "$POD_INFO" ]; then
    echo "ERROR: No RUNNING pod found matching '$SEARCH_TERM'."
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
echo "STATUS: Running"
echo "--------------------------------------------------------"
# The execution line is now fixed to use double quotes around $COMMAND
echo "Executing: kubectl exec -it $POD_NAME -n $NAMESPACE -- $COMMAND"
echo "--------------------------------------------------------"

# Introduce a 1-second pause for confirmation
sleep 1

# Execute the kubectl exec command
# FIX: $COMMAND MUST be double-quoted here to prevent word splitting by the host shell.
kubectl exec -it "$POD_NAME" -n "$NAMESPACE" -- $COMMAND


echo -e "\n--- Pod execute command finished ---"
echo -e " Executed: kubectl exec -it $POD_NAME -n $NAMESPACE -- $COMMAND"
echo -e "\n"
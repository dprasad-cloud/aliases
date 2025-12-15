#!/bin/bash

# Generic Pod Description Script (Single Pod Mode)
# This script finds the first pod matching the search term, displays its name,
# pauses for one second, and then runs 'kubectl describe pod' for that single result.

# $1 is the search term (e.g., 'network')
SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: desc <search_term>"
    exit 1
fi

echo "--- Searching for the pod containing '$SEARCH_TERM' ---"

# 1. Use 'kubectl' and 'grep' to find the pod line.
# 2. Use 'head -n 1' to get only the first result (excluding the header).
POD_LINE=$(kubectl get pod -A | grep "$SEARCH_TERM" | grep -v 'NAME' | head -n 1)

if [ -z "$POD_LINE" ]; then
    echo "Error: No pod found matching '$SEARCH_TERM'."
    exit 1
fi

# 2. Extract Namespace and Pod Name using 'awk' from the selected line
NAMESPACE=$(echo "$POD_LINE" | awk '{print $1}')
POD_NAME=$(echo "$POD_LINE" | awk '{print $2}')

# 3. Construct the final execution command
EXEC_COMMAND="kubectl describe pod $POD_NAME -n $NAMESPACE"

# Print Selection Info
echo "--------------------------------------------------------"
echo "SELECTED POD: $POD_NAME"
echo "NAMESPACE: $NAMESPACE"
echo "--------------------------------------------------------"
echo "Starting kubectl describe in 1 second..."

# Introduce a 1-second pause
sleep 1

# 4. Execute the command
eval "$EXEC_COMMAND"

# Print Summary at the end
echo -e "\n--- Description complete ---"
echo -e "\n Executed: $EXEC_COMMAND"
echo -e "\n"
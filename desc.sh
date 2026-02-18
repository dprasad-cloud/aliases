#!/bin/bash

# Generic Pod Description Script (Multi-Pod Mode)
# This script finds ALL pods matching the search term and runs 'kubectl describe pod' for each.

# $1 is the search term (e.g., 'network')
SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: desc <search_term>"
    exit 1
fi

echo "--- Searching for ALL pods containing '$SEARCH_TERM' ---"

# Variable to store ALL command(s) for printing at the end
ALL_EXEC_COMMANDS=""
PODS_FOUND=0

# Use Process Substitution to feed the output to the while loop
# This ensures the loop runs in the current shell, preserving variable scope.
while read NAMESPACE POD_NAME REST; do

    # Skip empty lines or the header row
    if [ -z "$POD_NAME" ] || [ "$POD_NAME" = "NAME" ]; then
        continue
    fi

    PODS_FOUND=$((PODS_FOUND + 1))

    # 1. Construct the final execution command
    CURRENT_EXEC_COMMAND="kubectl describe pod $POD_NAME -n $NAMESPACE"

    # 2. Append the current command to the list, followed by a newline
    ALL_EXEC_COMMANDS+="$CURRENT_EXEC_COMMAND"$'\n'

    # Print Selection Info
    echo -e "\n========================================================"
    echo "PROCESSING POD #$PODS_FOUND: $POD_NAME"
    echo "NAMESPACE: $NAMESPACE"
    echo "========================================================"
    echo "Starting kubectl describe in 1 second..."

    # Introduce a 1-second pause before each describe
    sleep 1

    # 3. Execute the command
    eval "$CURRENT_EXEC_COMMAND"

done < <(kubectl get pod -A | grep "$SEARCH_TERM" | grep -v 'NAME')

# Print Summary at the end
echo -e "\n--- Description complete ($PODS_FOUND pods processed) ---"

if [ -n "$ALL_EXEC_COMMANDS" ]; then
    echo -e "\ncommand(s):"
    # Print the concatenated commands.
    echo "$ALL_EXEC_COMMANDS"
else
    echo -e "\nNo pods were found matching '$SEARCH_TERM'."
fi
echo -e "\n"
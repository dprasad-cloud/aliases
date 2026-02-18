#!/bin/bash

# Generic Ingress Description Script
# This script finds ALL ingresses matching the search term and runs 'kubectl describe ing' for each.

SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: desc-ing <search_term>"
    exit 1
fi

echo "--- Searching for ALL ingresses containing '$SEARCH_TERM' ---"

ALL_EXEC_COMMANDS=""
ING_FOUND=0

# Fetching all ingresses across namespaces
# The format for 'kubectl get ing -A' is: NAMESPACE NAME CLASS HOSTS ADDRESS PORTS AGE
while read -r NAMESPACE ING_NAME REST; do

    # Skip header row or empty lines
    if [ -z "$ING_NAME" ] || [ "$ING_NAME" = "NAME" ] || [ "$NAMESPACE" = "NAMESPACE" ]; then
        continue
    fi

    ING_FOUND=$((ING_FOUND + 1))

    # 1. Construct the command
    CURRENT_EXEC_COMMAND="kubectl describe ing $ING_NAME -n $NAMESPACE"

    # 2. Append to summary list
    ALL_EXEC_COMMANDS+="$CURRENT_EXEC_COMMAND"$'\n'

    # Print Selection Info
    echo -e "\n========================================================"
    echo "PROCESSING INGRESS #$ING_FOUND: $ING_NAME"
    echo "NAMESPACE: $NAMESPACE"
    echo "========================================================"

    sleep 1

    # 3. Execute the command
    eval "$CURRENT_EXEC_COMMAND"

done < <(kubectl get ing -A | grep "$SEARCH_TERM")

# Print Summary
echo -e "\n--- Description complete ($ING_FOUND ingresses processed) ---"

if [ -n "$ALL_EXEC_COMMANDS" ]; then
    echo -e "\nCommand(s) executed:"
    echo "$ALL_EXEC_COMMANDS"
else
    echo -e "\nNo ingresses were found matching '$SEARCH_TERM'."
fi
echo -e "\n"
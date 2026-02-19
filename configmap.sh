#!/bin/bash

# Generic ConfigMap Description Script (Multiple Results)
# This script searches for all ConfigMaps matching the search term,
# and displays their properties.

# $1 is the search term (e.g., 'tereport')
SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: configmap <search_term>"
    exit 1
fi

echo "--- Strip unwanted strings at the end of search string"
# Remove common hash/number suffixes from the search term
SEARCH_TERM_CLEANED=$(echo "$SEARCH_TERM" | sed -E 's/-[a-z0-9]{8,10}(-[a-z0-9]{5})?$//; s/-[0-9]+$//')

echo "--- Searching for ConfigMaps containing '$SEARCH_TERM' and displaying properties ---"

# Variable to store ALL command(s) for printing at the end
# Must be defined in the main shell environment
ALL_EXEC_COMMANDS=""

# Go Template to extract key=value pairs from the .data section
GO_TEMPLATE='{{range $k, $v := .data}}{{printf "%s=%s\n" $k $v}}{{end}}'

# Use Process Substitution to feed the output to the while loop
# This ensures the loop runs in the current shell, preserving variable scope.
while read NAMESPACE CONFIGMAP_NAME REST; do

    # Skip empty lines or the header row
    if [ -z "$CONFIGMAP_NAME" ] || [ "$CONFIGMAP_NAME" = "NAME" ]; then
        continue
    fi

    # 1. Construct the final execution command
    CURRENT_EXEC_COMMAND="kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o go-template='$GO_TEMPLATE'"

    # 2. Append the current command to the list, followed by a newline
    ALL_EXEC_COMMANDS+="$CURRENT_EXEC_COMMAND"$'\n'

    # Print Selection Info
    echo -e "\n========================================================"
    echo "PROPERTIES FOR: $CONFIGMAP_NAME"
    echo "NAMESPACE: $NAMESPACE"
    echo "========================================================"

    # 3. Execute the command
    eval "$CURRENT_EXEC_COMMAND"

done < <(kubectl get cm -A | grep "$SEARCH_TERM")

# Print Summary at the end
echo -e "\n--- Description complete ---"
if [ -n "$ALL_EXEC_COMMANDS" ]; then
    echo -e "\ncommand(s):"
    # Print the concatenated commands.
    echo "$ALL_EXEC_COMMANDS"
else
    echo -e "\nNo ConfigMaps were found or processed."
fi
echo -e "\n"
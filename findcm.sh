#!/bin/bash

# Script name: find_cm.sh
# Description: Searches for Kubernetes ConfigMaps, automatically stripping common
#              auto-generated suffixes from the search term before grepping.

# Define the function to perform the search logic
SEARCH_TERM="$1"

# Check if a search term was provided
if [ -z "$SEARCH_TERM" ]; then
    echo "Error: Please provide a search term."
    echo "Usage: $0 <search_term>"
    exit 1
fi

echo -e "\n"

# Process the search term to strip common random suffixes
SEARCH_TERM_CLEANED=$(echo "$SEARCH_TERM" | \
    sed -E 's/-[a-z0-9]{5}$//' | \
    sed -E 's/-[a-f0-9]{9,10}$//' | \
    sed -E 's/-[0-9]+$//')

# Execute the kubectl command with the stripped search term
# The '-i' flag ensures case-insensitive search
kubectl get cm -A | grep -iE "$SEARCH_TERM_CLEANED"

# Execute the function with the script's arguments
echo -e "\n Executed:\n\t kubectl get cm -A | grep -iE \"$SEARCH_TERM_CLEANED\""
echo -e "\n"

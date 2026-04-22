#!/bin/bash

# Generic Multi-Pod Deletion Script
# Finds all pods matching the search term and deletes them after confirmation.

SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: delpod <search_term>"
    exit 1
fi

echo "--- Searching for pods containing '$SEARCH_TERM' ---"

# Get all matching pods (Namespace and Name)
# We store them in a variable to check if any were found
MATCHES=$(kubectl get pod -A | grep -iE "$SEARCH_TERM" | awk '{print $1 " " $2}')

if [ -z "$MATCHES" ]; then
    echo "ERROR: No pods found matching '$SEARCH_TERM'."
    exit 1
fi

echo "--------------------------------------------------------"
echo "THE FOLLOWING PODS WILL BE DELETED:"
echo "$MATCHES" | awk '{printf "  - Namespace: %-15s Pod: %s\n", $1, $2}'
echo "--------------------------------------------------------"
echo ""

# Single confirmation for the entire list
read -p "Delete all listed pods? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# Iterate through the list and delete
echo "$MATCHES" | while read -r NS POD; do
    echo "Deleting $POD in $NS..."
    kubectl delete pod "$POD" -n "$NS" --now
done

echo "--------------------------------------------------------"
echo ""
echo "Cleanup complete."
echo ""
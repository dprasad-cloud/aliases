#!/bin/bash

# Generic Multi-Pod Deletion Script
# Finds all pods matching the search term (case-insensitive), shows status, and deletes after confirmation.

SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: delpod <search_term>"
    exit 1
fi

echo "--- Searching for pods matching '$SEARCH_TERM' ---"

# Get matching pods: Namespace ($1), Name ($2), and Status ($4)
# Added -i for case-insensitivity and -E for extended regex support as per your edit
MATCHES=$(kubectl get pod -A | grep -iE "$SEARCH_TERM" | awk '{print $1 " " $2 " " $4}')

if [ -z "$MATCHES" ]; then
    echo "ERROR: No pods found matching '$SEARCH_TERM'."
    exit 1
fi

echo "--------------------------------------------------------------------------------"
echo "THE FOLLOWING PODS WILL BE DELETED:"
printf "  %-20s %-45s %s\n" "NAMESPACE" "POD NAME" "STATUS"
echo "--------------------------------------------------------------------------------"
echo "$MATCHES" | awk '{printf "  %-20s %-45s %s\n", $1, $2, $3}'
echo "--------------------------------------------------------------------------------"
echo ""

# Single confirmation for the entire list
read -p "Confirm deletion of all pods listed above? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo ""
    echo "Deletion cancelled."
    echo ""
    exit 0
fi

# Iterate through the list and delete
echo "$MATCHES" | while read -r NS POD STATUS; do
    echo "Deleting $POD in $NS (Current Status: $STATUS)..."
    echo "Command: kubectl delete pod $POD -n $NS --now"
    kubectl delete pod "$POD" -n "$NS" --now
done

echo "--------------------------------------------------------------------------------"
echo ""
echo "Cleanup complete."
echo ""
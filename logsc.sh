#!/bin/bash

# Generic Pod Logs Display Script (container-specific)
# Finds the first pod matching the search term, then prints logs
# for the specified container.

SEARCH_TERM="$1"
CONTAINER_NAME="$2"

if [ -z "$SEARCH_TERM" ] || [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: logsc <search_term> <container_name>"
    exit 1
fi

echo "--- Searching for the FIRST pod containing '$SEARCH_TERM' ---"

POD_INFO=$(kubectl get pod -A | grep "$SEARCH_TERM" | head -n 1)

if [ -z "$POD_INFO" ]; then
    echo "ERROR: No pod found matching '$SEARCH_TERM'."
    exit 1
fi

NAMESPACE=$(echo "$POD_INFO" | awk '{print $1}')
POD_NAME=$(echo "$POD_INFO" | awk '{print $2}')

BASE_NAME=$(echo "$POD_NAME" | sed -E 's/-[a-z0-9]{5}$//' | sed -E 's/-[a-f0-9]{9,10}$//' | sed -E 's/-[0-9]+$//')

echo "--------------------------------------------------------"
echo "SELECTED POD: $POD_NAME"
echo "BASE APPLICATION: $BASE_NAME"
echo "NAMESPACE: $NAMESPACE"
echo "CONTAINER: $CONTAINER_NAME"
echo "--------------------------------------------------------"
echo "command(s):"
echo "kubectl logs $POD_NAME -n $NAMESPACE -c $CONTAINER_NAME"
echo "--------------------------------------------------------"

sleep 1

if ! kubectl logs "$POD_NAME" -n "$NAMESPACE" -c "$CONTAINER_NAME"; then
    echo ""
    echo "ERROR: Failed to fetch logs for container '$CONTAINER_NAME' in pod '$POD_NAME'."
    echo "Available containers in this pod:"
    kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}'
    echo ""
    exit 1
fi

echo -e "\n--- Pod container logs displayed ---"
echo -e "\n \ncommand(s):\n\t kubectl logs $POD_NAME -n $NAMESPACE -c $CONTAINER_NAME"
echo -e "\n"


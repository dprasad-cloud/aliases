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

echo "--- Searching for the FIRST pod containing '$SEARCH_TERM' ---"

# Use 'kubectl get pod -A' to list all pods across all namespaces.
# Pipe to 'grep' for the search term.
# Pipe to 'head -n 1' to select only the first data line (excluding the header).
kubectl get pod -A | grep "$SEARCH_TERM" | head -n 1 | awk '
{
    namespace = $1;
    pod_name = $2;

    # Check if the line is not the header line
    if (pod_name != "NAME") {
        print "--------------------------------------------------------"
        print "SELECTED POD: " pod_name
        print "NAMESPACE: " namespace
        print "--------------------------------------------------------"
        print "Starting kubectl describe in 1 second..."

        # Introduce a 1-second pause
        system("sleep 1")

        # Execute the kubectl describe command
        system("kubectl describe pod " pod_name " -n " namespace)
    }
}
'

echo "--- Description complete ---"
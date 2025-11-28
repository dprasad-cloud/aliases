#!/bin/bash

# Generic ConfigMap Description Script (Multiple Results)
# This script searches for all ConfigMaps matching the search term,
# and runs 'kubectl describe configmap' for each one found.

# $1 is the search term (e.g., 'tereport')
SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: configmap <search_term>"
    exit 1
fi

echo "--- Searching for ConfigMaps containing '$SEARCH_TERM' and describing all matches ---"

# Use 'kubectl get cm -A' to list all ConfigMaps across all namespaces.
# Pipe to 'grep' for the search term.
# Pipe to 'awk' to parse the output and execute the describe command for each result.
kubectl get cm -A | grep "$SEARCH_TERM" | awk '
{
    namespace = $1;
    configmap_name = $2;

    # Skip the header row if it matches the search term
    if (configmap_name != "NAME") {
        print "\n========================================================"
        print "Describing ConfigMap: " configmap_name
        print "NAMESPACE: " namespace
        print "========================================================"

        # Execute the kubectl describe command
        system("kubectl describe cm " configmap_name " -n " namespace)
    }
}
'

echo "--- Description complete ---"
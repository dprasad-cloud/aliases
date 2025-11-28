#!/bin/bash

# Generic ConfigMap Description Script (Multiple Results)
# This script searches for all ConfigMaps matching the search term,
# and runs 'kubectl get' with a Go template to display properties (key=value)
# for each one found.

# $1 is the search term (e.g., 'tereport')
SEARCH_TERM="$1"

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: configmap <search_term>"
    exit 1
fi

echo "--- Searching for ConfigMaps containing '$SEARCH_TERM' and displaying properties ---"
SEARCH_TERM=$(echo "$SEARCH_TERM" | sed -E 's/-[a-z0-9]{5}$//' | sed -E 's/-[a-f0-9]{9,10}$//' | sed -E 's/-[0-9]+$//')

# Use 'kubectl get cm -A' to list all ConfigMaps across all namespaces.
# Pipe to 'grep' for the search term.
# Pipe to 'awk' to parse the output and execute the new command for each result.
kubectl get cm -A | grep "$SEARCH_TERM" | awk '
{
    namespace = $1;
    configmap_name = $2;

    # Skip the header row if it matches the search term
    if (configmap_name != "NAME") {
        print "\n========================================================"
        print "PROPERTIES FOR: " configmap_name
        print "NAMESPACE: " namespace
        print "========================================================"

        # Execute the kubectl get command with the Go template to show key=value pairs
        system("kubectl get configmap " configmap_name " -n " namespace " -o go-template=\047{{range $k, $v := .data}}{{printf \"%s=%s\\n\" $k $v}}{{end}}\047")
        # NOTE: The template is escaped with '\\x27' (single quote) to ensure AWK passes it correctly.
    }
}
'

echo "--- Description complete ---"
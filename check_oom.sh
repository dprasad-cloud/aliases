kubectl get pods -A -o json \
| jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $pod | (.status.containerStatuses // [])[] |
  select(.lastState.terminated.reason == "OOMKilled" or .lastState.terminated.exitCode == 137) |
  [$ns, $pod, .name, (.restartCount|tostring), (.lastState.terminated.finishedAt // "-")] | @tsv' \
| awk -F'\t' 'BEGIN{OFS="\t"} {key=$1"\t"$2"\t"$3; c[key]++; r[key]=$4; t[key]=$5} END{for(k in c){print k, c[k], r[k], t[k]}}' \
| sort -t$'\t' -k5,5nr -k4,4nr \
| { printf "NAMESPACE\tPOD\tCONTAINER\tOOM_MATCH_COUNT\tRESTART_COUNT\tLAST_OOM_FINISHED_AT\n"; cat; } \
| column -t -s$'\t'
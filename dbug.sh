kubectl get pods -A -o json \
| jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $pod | (.status.containerStatuses // [])[] |
  select(.lastState.terminated) |
  .lastState.terminated as $t |
  # Determine type: "oom" if explicitly OOMKilled, "137" if exitCode 137 but not OOMKilled, "other" otherwise
  (if $t.reason == "OOMKilled" then "oom" elif $t.exitCode == 137 then "137" else "other" end) as $type |
  [$ns, $pod, $type, (.restartCount|tostring), ($t.finishedAt // "-")] | @tsv' \
| awk -F'\t' 'BEGIN{OFS="\t"} {
    key=$1"\t"$2;
    r[key]=$4;
    t[key]=$5;
    if ($3 == "oom") oom[key]++;
    else if ($3 == "137") c137[key]++;
    else other[key]++;
  }
  END {
    for(k in r) {
      print k, (oom[k]?oom[k]:0), (c137[k]?c137[k]:0), (other[k]?other[k]:0), r[k], t[k]
    }
  }' \
| sort -t$'\t' -k6,6r \
| { printf "NAMESPACE\tPOD\tOOM_COUNT\tSIGKILL_137_COUNT\tOTHER_COUNT\tRESTART_COUNT\tLAST_TERMINATED_AT\n"; cat; } \
| column -t -s$'\t'
#!/bin/bash
source /root/aliases-main/cloudv2.txt
klag() {
    local pod_pattern="${pod:-default-kafka-0}"
    local my_bs
    my_bs=$(get_bs)
    if khelp "$1"; then return 0; fi

    local kafkalist="unset JMX_PORT; bin/kafka-consumer-groups.sh --bootstrap-server $my_bs --describe --all-groups"

    podexec "$pod_pattern" "$kafkalist" | awk '
        BEGIN { print "GROUP", "TOPIC", "LAG" }
        # Match numeric lag > 0 in column 6 (or adjust $6 to matching column)
        $6 ~ /^[0-9]+$/ && $6 > 0 { print $1, $2, $6 }
    ' | column -t
}
klag

Usually the aliases work automatically after running the script.

But in case any service is still in the process of migration...
(example assets service is still not moved to common namespace)
Then use below command to use cdos aliases.

source /root/aliases-main/cloud-old.txt

Note that other aliases (like ccs cdc) may stop working with above change.
aliases related to default namespace will always work irrespective of the changes.



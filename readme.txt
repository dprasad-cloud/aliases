
Usually the aliases work automatically after running the script.

But in case any service is still in the process of migration
(example assets service is still not moved to common namespace)

Then use below commands based on the current namespace of the service
If the service is still in the default namespace use cloud-old.txt

source /root/aliases-main/cloud-old.txt

Note that other aliases may stop working with above change.



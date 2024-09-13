
Usually the aliases work automatically after running the script.
Just type prefix and press tab to see full list of aliases available:
ccs
cdos
cdc
hmweb
hac

But in case any service is still in the process of migration...
(example assets service is still not moved to common namespace)
Then use below command to use cdos aliases.

source /root/aliases-main/cloud-old.txt

Note that other aliases (like ccs cdc) may stop working with above change.
aliases related to default namespace will always work irrespective of the changes.



if alias kc >/dev/null 2>&1; then file=cloud.txt; elif alias k >/dev/null 2>&1; then file=cloud.txt; else file=aio.txt; fi  ; wget -O /root/main.zip https://github.com/dprasad-cloud/aliases/archive/refs/heads/main.zip ; unzip -o /root/main.zip -d /root; source /root/aliases-main/$file



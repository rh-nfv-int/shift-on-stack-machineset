# shift-on-stack-machineset

```
ansible-playbook play.yaml -i inventory.yaml -e additional_network_names="vhostuser1,vhostuser2" -e cluster_metadata_path=~/sos-fdp/build/metadata.json -vv
oc apply -f build/<ms_file>.yaml
```

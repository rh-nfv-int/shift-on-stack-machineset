#!/bin/bash

#set -e

PATCH_FILE="./patch.yaml"
PODNAME="introspect"

usage() {
    prog=$(basename "$0")
    cat <<-EOM
    Generate patch to apply to the Network.operator cluster to include HostDevice
      for ovs-dpdk additional networks. 

    Usage:
        $prog [-h] [-m MachineSet] infraID namespace net1[ net2 net3,...]
            infraID          -- ID generated by openshift-install

            net1[,net2,net3,...] -- Networks to include in the Network Cluster path
            MachineSet       -- Name of the MachineSet that defines the worker nodes.
                                Defaults to <infraID>-worker
            Namespace        -- Namespace where the additional networks will reside
            deploy cluster   -- Deploy cluster.  Runs the following steps
                                create_deploy, prepare_openstack, manage_cluster "deploy"
           
    Options
            -h  -- Print this usage and exit.
            -m MachineSet -- Name of the MachineSet that defines the worker nodes.
                             Defaults to <infraID>-worker
    ENVIRONEMENT VARIABLES
            none

EOM
    exit 0
}

declare -A mac_map

query_mac_by_network() {
    net="$1"

    if ! readarray -t macs < <(openstack port list --network "$net" -c Name -c "Mac Address" -f value); then
        printf "Network %s does not exist!\n" "$net"
        return 1
    fi

    regex="^(.+)\s+(.+)"
    for ele in "${macs[@]}"; do
        if [[ $ele =~ $regex ]]; then
            mac_address="${BASH_REMATCH[2]}"
            # shellcheck disable=SC2034
            mac_map[$mac_address]="$net"
        fi
    done
}

emit_additional_network() {
    namespace="$1"
    intf="$2"

    if [[ $intf =~ .*devices\/pci[^\/]+\/([^\/]+)\/virtio[^\/]+\/net\/([^_]+)_(.*) ]]; then
        pci_address="${BASH_REMATCH[1]}"
        mac="${BASH_REMATCH[3]}"
        if [[ -n ${mac_map[$mac]} ]]; then
            {
                printf "    - name: %s\n" "${mac_map[$mac]}"
                printf "      namespace: %s\n" "$namespace"
                printf "      type: Raw\n"
                printf "      rawCNIConfig: '{\n"
                printf "        \"cniVersion\": \"0.3.1\",\n"
                printf "        \"name\": \"hostonly\",\n"
                printf "        \"type\": \"host-device\",\n"
                printf "        \"pciBusId\": \"%s\",\n" "$pci_address"
                printf "        \"ipam\": { }\n"
                printf "      }'\n"
            } >>$PATCH_FILE
        fi
    fi
}

VERBOSE="false"
export VERBOSE

while getopts "hm:" opt; do
    case ${opt} in
    h)
        usage
        exit 0
        ;;
    m)
        machineSet=$OPTARG
        ;;

    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Three required arguments
# infraID and namespace
# and at least one netwrok
if [ "$#" -lt 3 ]; then
    usage
fi

infraID="$1"
shift

namespace="$1"
shift

if ! oc get namespace "$namespace" >/dev/null 2>&1; then
  printf "Namespace %s does not exists!\n" "$namespace"
  exit 1
fi

printf "Generate patch.yaml for cluster: %s and namespace: %s\n" "$infraID" "$namespace"

# Check for at least one network
if [ "$#" -eq 0 ]; then
    printf "No network(s) specified!\n"

    usage
fi

networks=("$@")

for net in "${networks[@]}"; do
    if ! query_mac_by_network "$net"; then
      exit 1
    fi
done

if [ -z "$machineSet" ]; then
    machineSet="$infraID-worker"
fi

printf "Using MachineSet %s...\n" "$machineSet"

if ! tools_sha=$(oc adm release info --image-for='tools'); then
    echo "Unable to locate system tools container..."
    exit 1
fi

if ! nodeName=$(oc get machine -l "machine.openshift.io/cluster-api-machineset=$machineSet" -n openshift-machine-api -ojson | jq '.items[0].status.nodeRef.name' | sed 's/"//g'); then
    printf "Failed to find MachineSet %s or MachineSet has no valid Nodes...\n" "$machineSet"
    exit 1
fi

printf "Inspecting proxy Node %s to determing mapping..." "$nodeName"

read -r -d '' VAR <<EOF
{
 "spec": {
    "hostPID": true,
    "hostNetwork": true,
    "nodeSelector": { "kubernetes.io/hostname": "${nodeName:?}" },
    "containers": [
        {
            "command": [
                "find",
                "/sys/class/net",
                "-mindepth",
                "1",
                "-maxdepth",
                "1",
                "!",
                "-name",
                "veth*",
                "-printf",
                "%l_",
                "-execdir",
                "cat",
                "{}/address",
                ";"
            ],
            "securityContext": {
              "privileged": true,
              "runAsUser": 0
            },
            "stdin": true,
            "image": "${tools_sha}",
            "name": "fdp",
            "volumeMounts": [{
            "mountPath": "/host",
                "name": "host"
            }]
        }
    ],        
    "volumes": [
        {
            "name": "host",
            "hostPath": {
                "path": "/",
                "type": "Directory"
            }
        }
    ]
 }
}
EOF

patch=${VAR//[$'\n\t ']/}

oc delete pod/"$PODNAME" >/dev/null 2>&1

readarray -t interfaces < <(oc run "$PODNAME" --privileged=true --quiet=true --rm=true --restart='Never' -it --overrides="$patch" --image="$tools_sha")

{
    printf "\nspec:\n"
    printf "  additionalNetworks:\n"
} >$PATCH_FILE

for intf in "${interfaces[@]}"; do
    emit_additional_network "$namespace" "$intf" 
done

printf "\nGenerate patch file: %s\n" $PATCH_FILE
printf "Apply the patch using...\n"
printf "  oc patch network.operator cluster --patch \"\$(cat %s)\" --type=merge\n" $PATCH_FILE
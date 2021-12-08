#!/bin/bash

set -e

oc apply -f ./pao-namespace.yaml

oc apply -f ./pao-operatorgroup.yaml

OC_CHANNEL=$(oc get packagemanifest performance-addon-operator -n openshift-marketplace -o jsonpath='{.status.defaultChannel}')

# shellcheck disable=SC2016
sed 's/${OC_CHANNEL}/'"$OC_CHANNEL"'/' pao-subscriptions.yaml | oc apply -f -


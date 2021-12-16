#!/bin/bash

oc patch network.operator cluster --patch "$(cat example-cnf-patch.yaml)" --type=merge
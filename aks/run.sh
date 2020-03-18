#!/usr/bin/env bash

set -e

echo "$(terraform output kube_config)" > ./azurek8s
export KUBECONFIG=./azurek8s

# TODO
echo $K8S_NAME
echo $K8S_RG
# kubectl get pods
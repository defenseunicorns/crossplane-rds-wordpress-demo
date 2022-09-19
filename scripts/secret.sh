#!/bin/bash

# prep
unset KUBECONFIG
sudo rm -rvf admin.conf

# capture secet
SECRET=$(kubectl get secret -A -o name | grep ^secret/kubeconfig)
kubectl get $SECRET -n crossplane-system -o jsonpath="{.data.kubeconfig}" | base64 -d > admin.conf

# configure
chmod 0400 admin.conf
export KUBECONFIG=$(pwd)/admin.conf

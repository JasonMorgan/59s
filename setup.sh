#!/usr/bin/env bash

k3d cluster create gitops -p "8080:80@loadbalancer" -p "8443:443@loadbalancer"  --k3s-arg '--disable=traefik@server:0'
flux install
kubectl apply -f 59s/repo.yaml
kubectl create ns linkerd
kubectl create ns linkerd-buoyant
kubectl apply -f secrets/buoyant.yaml
kubectl create secret tls linkerd-trust-anchor \
  --cert=secrets/ca.test.crt \
  --key=secrets/ca.test.key \
  --namespace=linkerd
kubectl apply -f clusters/production/cluster.test.yaml
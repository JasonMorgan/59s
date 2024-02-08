#!/usr/bin/env bash
set -e

if [ -z "${2}" ]
then
  clusters=(test dev prod1)
else
  clusters=("${@:2}")
fi

case "${1}" in
  start)
    if [ -z "${KUBECONFIG}" ]
    then
      export KUBECONFIG=~/.kube/config
    fi

    ## Begin our creationloop
    for c in "${clusters[@]}"
    {
      ## Is it a Prod cluster?
      if [[ "${c}" == "prod"* ]]
      then
        size=g4s.kube.large
        number=5
        env=civo
        # linkerd_install+=(-f manifests/linkerd/overrides.yaml)

      ## Is it local?
      elif [[ "${c}" == "local"* ]]
      then
        env=local

      ## Whatever else it may be
      else
        size=g4s.kube.large
        number=1
        env=civo
      fi

      ## Cluster creation
      case "${env}" in
        civo)
          kubectl ctx -u
          kubectl config delete-context "${c}" || true
          kubectl config delete-cluster "${c}" || true
          kubectl config delete-user "${c}" || true
          civo k8s create "${c}" -n $number -s "${size}" -r Traefik-v2-nodeport -w # || true
          civo k8s config -sy "${c}" || true
          # sleep 60
          ;;
        local)
          k3d cluster delete local > /dev/null 2>&1 || true
          k3d cluster create local -s 3
          ;;
        *)
          echo "something got fucked up in the env"
          exit 1
        ;;
      esac
    }

    PROVISION=1
  ;;
  stop)
    for c in "${clusters[@]}"
    {
      civo k8s delete "${c}" -y
      kubectl config delete-context "${c}" || true
      kubectl config delete-cluster "${c}" || true
      kubectl config delete-user "${c}" || true
    }
  ;;
  provision)
    PROVISION=1
  ;;
  *)
    echo "missing required argument: start|stop|provision"
    echo "./bootstrap start|stop [cluster names]"
    exit 1
  ;;
esac

if [[ $PROVISION == 1 ]]
then
  ## Begin our provisioning loop
  for c in "${clusters[@]}"
  {
    ## Set context
    civo k8s config "${c}" -sy
    kubectl ctx "${c}"
    kubectl ns default

    ## Ready helm repos
    helm repo update > /dev/null
    
    # Prep cluster
    flux install
    kubectl apply -f repo.yaml
    kubectl create ns linkerd
    kubectl create ns linkerd-buoyant
    kubectl apply -f secrets/buoyant.yaml
    case "${c}" in
      prod*)
        kubectl create secret tls linkerd-trust-anchor \
          --cert=secrets/ca.prod.crt \
          --key=secrets/ca.prod.key \
          --namespace=linkerd || true
        kubectl apply -f clusters/production/cluster.prod.yaml
        ;;
      dev)
        kubectl create secret tls linkerd-trust-anchor \
          --cert=secrets/ca.dev.crt \
          --key=secrets/ca.dev.key \
          --namespace=linkerd || true
        kubectl apply -f clusters/dev/cluster.dev.yaml
        ;;
      *)
        kubectl create secret tls linkerd-trust-anchor \
          --cert=secrets/ca.test.crt \
          --key=secrets/ca.test.key \
          --namespace=linkerd || true
        kubectl apply -f clusters/test/cluster.test.yaml
        ;;
    esac
  }
fi
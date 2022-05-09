#!/bin/bash
echo "$@"

if [ $# != 11 ]; then
  echo "Usage: install_k3s_master.sh node_os dns install_mode k3s_version cluster_type public_ip datastore_endpoint server_flags rhel_username rhel_password channel"
  exit 1
fi

node_os="$1"
dns="$2"
install_mode="$3"
k3s_version="$4"
cluster_type="$5"
public_ip="$6"
datastore_endpoint="$7"
server_flags="$8"
rhel_username="$9"
rhel_password="${10}"
channel="${11}"

mkdir -p /etc/rancher/k3s
mkdir -p /var/lib/rancher/k3s/server/logs
token=$(openssl rand -base64 21)
cat << EOF > /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - $dns
token: ${token}
EOF

if [[ -n "$server_flags" ]] && [[ "$server_flags" == *":"* ]]
then
   echo "$"
   echo -e "$8" >> /etc/rancher/k3s/config.yaml
   cat /etc/rancher/k3s/config.yaml
fi

if [[ -n "$server_flags" ]] && [[ "$server_flags" == *"protect-kernel-defaults"* ]]
then
  cat /tmp/cis_masterconfig.yaml >> /etc/rancher/k3s/config.yaml
  cat <<-EOF > /etc/sysctl.d/90-kubelet.conf
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
EOF
  sysctl -p /etc/sysctl.d/90-kubelet.conf
  systemctl restart systemd-sysctl
  mkdir -p /var/lib/rancher/k3s/server/manifests
  cat /tmp/policy.yaml > /var/lib/rancher/k3s/server/manifests/policy.yaml

  if [[ "$k3s_version" == *"v1.18"* ]] || [[ "$k3s_version" == *"v1.19"* ]] || [[ "$k3s_version" == *"v1.20"* ]]
  then
    cat /tmp/v120ingresspolicy.yaml > /var/lib/rancher/k3s/server/manifests/v120ingresspolicy.yaml
  else
    cat /tmp/v121ingresspolicy.yaml > /var/lib/rancher/k3s/server/manifests/v121ingresspolicy.yaml
  fi
fi


if [[ "$server_flags" == *"traefik"* ]]
then
   mkdir -p /var/lib/rancher/k3s/server/manifests
   cat /tmp/nginx-ingress.yaml > /var/lib/rancher/k3s/server/manifests/nginx-ingress.yaml
fi

if [ "$node_os" = "rhel" ]
then
   subscription-manager register --auto-attach --username="$rhel_username" --password="$rhel_password"
   subscription-manager repos --enable=rhel-7-server-extras-rpms
fi

export "$install_mode"="$k3s_version"

if [ "$cluster_type" = "etcd" ]
then
   echo "CLUSTER TYPE  is etcd"
   if [[ "$k3s_version" == *"v1.18"* ]] || [[ "$k3s_version" == *"v1.17"* ]] && [[ -n "$server_flags" ]]
   then
       curl -sfL https://get.k3s.io | INSTALL_K3S_TYPE='server' sh -s - server --cluster-init --node-external-ip="$public_ip" "$server_flags" --tls-san "$dns" --write-kubeconfig-mode "0644"
   else
       if [ "$channel" != "null" ]
       then
           curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="$channel" INSTALL_K3S_TYPE='server' sh -s - server --cluster-init --node-external-ip="$public_ip"
       else
           curl -sfL https://get.k3s.io | INSTALL_K3S_TYPE='server' sh -s - server --cluster-init --node-external-ip="$public_ip"
       fi
   fi
else
  echo "CLUSTER TYPE is external db"
  if [[ "$k3s_version" == *"v1.18"* ]] || [[ "$k3s_version" == *"v1.17"* ]] && [[ -n "$server_flags" ]]
  then
      curl -sfL https://get.k3s.io | sh -s - server --node-external-ip="$public_ip" --datastore-endpoint="$datastore_endpoint" "$server_flags" --tls-san "$dns" --write-kubeconfig-mode "0644"
  else
      if [ "$channel" != "null" ]
      then
          curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="$channel" sh -s - server --node-external-ip="$public_ip" --datastore-endpoint="$datastore_endpoint"
      else
          curl -sfL https://get.k3s.io | sh -s - server --node-external-ip="$public_ip" --datastore-endpoint="$datastore_endpoint"
      fi
  fi
fi

export PATH=$PATH:/usr/local/bin
timeElapsed=0
kGetNodes="kubectl get nodes > /dev/null 2>&1"
while ! eval "$kGetNodes" && [[ "$timeElapsed" -lt 300 ]]
do
   sleep 5
   timeElapsed=$(("$timeElapsed" + 5))
done

IFS=$'\n'
timeElapsed=0
sleep 10
kGetNodes="kubectl get nodes"
while [[ "$timeElapsed" -lt 420 ]]
do
   notready=false
   for rec in eval "$kGetNodes"
   do
      if [[ "$rec" == *"NotReady"* ]]
      then
         notready=true
      fi
  done
  if [[ $notready == false ]]
  then
     break
  fi
  sleep 20
  timeElapsed+=20
done

IFS=$'\n'
timeElapsed=0
kGetPods="kubectl get pods -A --no-headers"
while [[ $timeElapsed -lt 420 ]]
do
   helmPodsNR=false
   systemPodsNR=false
   for rec in eval "$kGetPods"
   do
      if [[ "$rec" == *"helm-install"* ]] && [[ "$rec" != *"Completed"* ]]
      then
         helmPodsNR=true
      elif [[ "$rec" != *"helm-install"* ]] && [[ "$rec" != *"Running"* ]]
      then
         systemPodsNR=true
      else
         echo ""
      fi
   done

   if [[ $systemPodsNR == false ]] && [[ $helmPodsNR == false ]]
   then
      break
   fi
   sleep 20
   timeElapsed+=20
done
cat /etc/rancher/k3s/config.yaml> /tmp/joinflags
cat /var/lib/rancher/k3s/server/node-token >/tmp/nodetoken
cat /etc/rancher/k3s/k3s.yaml >/tmp/config
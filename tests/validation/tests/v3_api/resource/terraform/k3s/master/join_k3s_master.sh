#!/bin/bash
# This script is used to join one or more nodes as masters
echo "$@"

if [ $# != 11 ]; then
  echo "Usage: join_k3s_master.sh node_os dns install_mode k3s_version cluster_type public_ip bootstrap_node_ip token datastore_endpoint server_flags rhel_username rhel_password channel"
  exit 1
fi

node_os="$1"
dns="$2"
install_mode="$3"
k3s_version="$4"
cluster_type="$5"
public_ip="$6"
bootstrap_node_ip="$7"
token="$8"
datastore_endpoint="$9"
server_flags="${10}"
rhel_username="${11}"
rhel_password="${12}"
channel="${13}"

mkdir -p /etc/rancher/k3s
mkdir -p /var/lib/rancher/k3s/server/logs
cat <<EOF > /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - $dns
token: $token
EOF

if [[ -n "$server_flags" ]] && [[ "$server_flags" == *":"* ]]
then
   echo -e "$server_flags" >> /etc/rancher/k3s/config.yaml
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

if [ "$node_os" = "rhel" ]
then
   subscription-manager register --auto-attach --username="$rhel_username" --password="$rhel_password"
   subscription-manager repos --enable=rhel-7-server-extras-rpms
fi
export "$install_mode"="$k3s_version"
if [ "$cluster_type" = "etcd" ]
then
    if [[ "$k3s_version" == *"v1.18"* ]] || [[ "$k3s_version" == *"v1.17"* ]] && [[ -n "$server_flags" ]]
    then
        curl -sfL https://get.k3s.io | INSTALL_K3S_TYPE='server' sh -s - server --server https://"$bootstrap_node_ip":6443 --token "$token" --node-external-ip="$public_ip" --tls-san "$dns" --write-kubeconfig-mode "0644"
    else
        if [ "$channel" != "null" ]
        then
          curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=$channel INSTALL_K3S_TYPE='server' sh -s - server --server https://"$bootstrap_node_ip":6443 --node-external-ip="$public_ip"
        else
          curl -sfL https://get.k3s.io | INSTALL_K3S_TYPE='server' sh -s - server --server https://"$bootstrap_node_ip":6443 --node-external-ip="$public_ip"
        fi
    fi
else
   if [[ "$k3s_version" == *"v1.18"* ]] || [[ "$k3s_version" == *"v1.17"* ]] && [[ -n "$server_flags" ]]
    then
        curl -sfL https://get.k3s.io | INSTALL_K3S_TYPE='server' sh -s - server --node-external-ip="$public_ip" --datastore-endpoint="$datastore_endpoint" --tls-san "$dns" --write-kubeconfig-mode "0644"
    else
        if [ "$channel" != "null" ]
        then
          curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=$channel INSTALL_K3S_TYPE='server' sh -s - server --node-external-ip="$public_ip" --datastore-endpoint="$datastore_endpoint"
        else
          curl -sfL https://get.k3s.io | INSTALL_K3S_TYPE='server' sh -s - server --node-external-ip="$public_ip" --datastore-endpoint="$datastore_endpoint"
        fi
    fi
fi
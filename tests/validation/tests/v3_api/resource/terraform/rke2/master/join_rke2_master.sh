#!/bin/bash
# This script is used to join one or more nodes as masters to the first master
echo $@

if [ $# != 11 ]; then
  echo "Usage: join_rke2_master.sh node_os dns install_mode rke2_version cluster_type public_ip bootstrap_node_ip token datastore_endpoint server_flags rhel_username rhel_password channel"
  exit 1
fi

node_os="$1"
dns="$2"
install_mode="$3"
rke2_version="$4"
cluster_type="$5"
public_ip="$6"
bootstrap_node_ip="$7"
token="$8"
datastore_endpoint="$9"
server_flags="${10}"
rhel_username="${11}"
rhel_password="${12}"
channel="${13}"

hostname=`hostname -f`
mkdir -p /etc/rancher/rke2
cat <<EOF >>/etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - $dns
server: https://${3}:9345
token:  "${4}"
node-name: "${hostname}"
EOF

if [ ! -z "${9}" ] && [[ "${9}" == *":"* ]]
then
   echo "${9}"
   echo -e "${9}" >> /etc/rancher/rke2/config.yaml
   if [[ "${9}" != *"cloud-provider-name"* ]]
   then
     echo -e "node-external-ip: ${6}" >> /etc/rancher/rke2/config.yaml
   fi
   cat /etc/rancher/rke2/config.yaml
else
  echo -e "node-external-ip: ${6}" >> /etc/rancher/rke2/config.yaml
fi

if [[ $node_os = "rhel" ]]
then
   subscription-manager register --auto-attach --username=${11} --password=${12}
   subscription-manager repos --enable=rhel-7-server-extras-rpms
fi

if [ $node_os = "centos8" ] || [ ${1} = "rhel8" ]
then
  yum install tar -y
  yum install iptables -y
  workaround="[keyfile]\nunmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:flannel*"
  if [ ! -e /etc/NetworkManager/conf.d/canal.conf ]; then
    echo -e $workaround > /etc/NetworkManager/conf.d/canal.conf
  else
    echo -e $workaround >> /etc/NetworkManager/conf.d/canal.conf
  fi
  sudo systemctl reload NetworkManager
fi

export "${10}"="${5}"
if [ ! -z "${13}" ]
then
  export INSTALL_RKE2_METHOD="${13}"
fi

if [ ${8} = "rke2" ]
then
   if [ ${7} != "null" ]
   then
       curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=${7} sh -
   else
       curl -sfL https://get.rke2.io | sh -
   fi
   sleep 10
   if [ ! -z "${9}" ] && [[ "${9}" == *"cis"* ]]
   then
       if [[ ${1} == *"rhel"* ]] || [[ ${1} == *"centos"* ]]
       then
           cp -f /usr/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
       else
           cp -f /usr/local/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
       fi
       systemctl restart systemd-sysctl
       useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U
   fi
   sudo systemctl enable rke2-server
   sudo systemctl start rke2-server
else
   curl -sfL https://get.rancher.io | INSTALL_RANCHERD_VERSION=${5} sh -
   sudo systemctl enable rancherd-server
   sudo systemctl start rancherd-server
fi

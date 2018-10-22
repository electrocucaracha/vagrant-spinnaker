#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2018
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o errexit
set -o pipefail

# _install_pip() - Install Python Package Manager
function _install_pip {
    if $(pip --version &>/dev/null); then
        return
    fi
    apt-get install -y python-dev
    curl -sL https://bootstrap.pypa.io/get-pip.py | python
    pip install --upgrade pip
}

# _install_ansible() - Install and Configure Ansible program
function _install_ansible {
    mkdir -p /etc/ansible/
    if $(ansible --version &>/dev/null); then
        return
    fi
    _install_pip
    pip install ansible
}

# install_k8s() - Install Kubernetes using kubespray tool
function install_k8s {
    echo "Deploying kubernetes"
    local dest_folder=/opt
    local version=2.7.0
    local tarball=v$version.tar.gz

    apt-get install -y sshpass
    _install_ansible
    wget https://github.com/kubernetes-incubator/kubespray/archive/$tarball
    tar -C $dest_folder -xzf $tarball
    mv $dest_folder/kubespray-$version/ansible.cfg /etc/ansible/ansible.cfg
    rm $tarball

    pip install -r $dest_folder/kubespray-$version/requirements.txt
    rm -f $krd_inventory_folder/group_vars/all.yml
    if [[ -n "${verbose}" ]]; then
        echo "kube_log_level: 5" | tee $krd_inventory_folder/group_vars/all.yml
    else
        echo "kube_log_level: 2" | tee $krd_inventory_folder/group_vars/all.yml
    fi
    if [[ -n "${http_proxy}" ]]; then
        echo "http_proxy: \"$http_proxy\"" | tee --append $krd_inventory_folder/group_vars/all.yml
    fi
    if [[ -n "${https_proxy}" ]]; then
        echo "https_proxy: \"$https_proxy\"" | tee --append $krd_inventory_folder/group_vars/all.yml
    fi
    ansible-playbook $verbose -i $krd_inventory $dest_folder/kubespray-$version/cluster.yml -b | tee $log_folder/setup-kubernetes.log

    # Configure environment
    mkdir -p $HOME/.kube
    mv $krd_inventory_folder/artifacts/admin.conf $HOME/.kube/config
}

# install_spinnaker() -
function install_spinnaker {
    export HAL_USER=$USER
    wget -q -O - https://raw.githubusercontent.com/spinnaker/halyard/master/install/debian/InstallHalyard.sh | sudo -E bash
}

# _print_kubernetes_info() - Prints the login Kubernetes information
function _print_kubernetes_info {
    if ! $(kubectl version &>/dev/null); then
        return
    fi
    # Expose Dashboard using NodePort
    node_port=30080
    KUBE_EDITOR="sed -i \"s|type\: ClusterIP|type\: NodePort|g\"" kubectl -n kube-system edit service kubernetes-dashboard
    KUBE_EDITOR="sed -i \"s|nodePort\: .*|nodePort\: $node_port|g\"" kubectl -n kube-system edit service kubernetes-dashboard

    master_ip=$(kubectl cluster-info | grep "Kubernetes master" | awk -F ":" '{print $2}')

    printf "Kubernetes Info\n===============\n" > $k8s_info_file
    echo "Dashboard URL: https:$master_ip:$node_port" >> $k8s_info_file
    echo "Admin user: kube" >> $k8s_info_file
    echo "Admin password: secret" >> $k8s_info_file
}

if [[ -n "${KRD_DEBUG}" ]]; then
    set -o xtrace
    verbose="-vvv"
fi

# Configuration values
log_folder=/var/log/krd
krd_folder=$(pwd)
krd_inventory_folder=$krd_folder/inventory
krd_inventory=$krd_inventory_folder/hosts.ini
k8s_info_file=$krd_folder/k8s_info.log

mkdir -p $log_folder

# Setup proxy variables
if [ -f $krd_folder/sources.list ]; then
    mv /etc/apt/sources.list /etc/apt/sources.list.backup
    cp $krd_folder/sources.list /etc/apt/sources.list
fi
apt-get update
install_k8s
install_spinnaker
_print_kubernetes_info

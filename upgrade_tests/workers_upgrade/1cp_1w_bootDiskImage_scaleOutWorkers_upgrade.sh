#!/bin/bash

source ../common.sh

echo '' > ~/.ssh/known_hosts

# Old name does not matter
export new_wr_metal3MachineTemplate_name="test1-new-workers-image"

# TODO: cleanup
set_number_of_node_replicas 1
set_number_of_master_node_replicas 1
set_number_of_worker_node_replicas 1

# provision a controlplane node
provision_controlplane_node
wait_for_ctrlplane_provisioning_start

CP_NODE=$(kubectl get bmh -n metal3 | grep control | grep -v ready | cut -f1 -d' ')
echo "BareMetalHost ${CP_NODE} is in provisioning or provisioned state"
CP_NODE_IP=$(sudo virsh net-dhcp-leases baremetal | grep "${CP_NODE}"  | awk '{{print $5}}' | cut -f1 -d\/)
wait_for_ctrlplane_provisioning_complete ${CP_NODE} ${CP_NODE_IP} "original controlplane node"

# apply CNI
ssh -o PasswordAuthentication=no -o "StrictHostKeyChecking no" "${UPGRADE_USER}@${CP_NODE_IP}" -- kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
provision_worker_node

wait_for_worker_to_scale_out ${CP_NODE_IP}

echo "Create a new metal3MachineTemplate with new boot disk image for worker nodes"
wr_Metal3MachineTemplate_OUTPUT_FILE="/tmp/wr_new_image.yaml"
CLUSTER_UID=$(kubectl get clusters -n metal3 test1 -o json |jq '.metadata.uid' | cut -f2 -d\")
IMG_CHKSUM=$(curl -s https://cloud-images.ubuntu.com/bionic/current/MD5SUMS | grep bionic-server-cloudimg-amd64.img | cut -f1 -d' ')
generate_metal3MachineTemplate "${new_wr_metal3MachineTemplate_name}" "${CLUSTER_UID}" "${wr_Metal3MachineTemplate_OUTPUT_FILE}" "${IMG_CHKSUM}"

kubectl apply -f "${wr_Metal3MachineTemplate_OUTPUT_FILE}"

# Change metal3MachineTemplate references.
kubectl get machinedeployment -n metal3 test1 -o json | jq '.spec.strategy.rollingUpdate.maxSurge=1|.spec.strategy.rollingUpdate.maxUnavailable=1' | kubectl apply -f-
kubectl get machinedeployment -n metal3 test1 -o json | jq '.spec.template.spec.infrastructureRef.name="test1-new-workers-image"' | kubectl apply -f-


echo "Waiting for start of boot disk upgrade of all worker nodes"
for i in {1..3600};do
  count=$(kubectl get bmh -n metal3 | awk 'NR>1'| grep -i ${new_wr_metal3MachineTemplate_name} | wc -l)
  if [ $count -lt 3 ]; then
      echo -n "-"	  
	  if [[ "${i}" -ge 3600 ]];then
		  echo "Error: Upgrade on some or all worker nodes did not start in time"
		  exit 1
      fi
      sleep 5
	  continue
  else
    echo "Upgrade of all worker nodes has started"
	  break
  fi
done

# Verify that all upgraded worker nodes have joined the cluster.
echo "Waiting for all upgraded worker nodes to join the cluster"
for i in {1..3600};do
  echo -n "*"
  replicas=$(ssh "-o LogLevel=quiet" -o "UserKnownHostsFile=/dev/null" -o PasswordAuthentication=no -o "StrictHostKeyChecking no" "${UPGRADE_USER}@${CP_NODE_IP}" -- kubectl get nodes| grep -v master | wc -l)
  if [[ "$replicas" == "3" ]]; then
    echo ''
    echo "Upgraded worker nodes have joined the cluster"
    break
  fi
  sleep 5
  if [[ "${i}" -ge 3600 ]];then
		  echo "Error: Upgraded worker node did not join the cluster in time"
		  exit 1
  fi
done


echo "Successfully upgraded multiple worker with NO extra node"

deprovision_cluster
wait_for_cluster_deprovisioned
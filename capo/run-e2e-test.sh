#!/bin/bash

GIT_ROOT=$(git rev-parse --show-toplevel)
CAPO_REPO=$(realpath "${GIT_ROOT}/../cluster-api-provider-openstack")
CAPO_E2E_SSH_KEY="${CAPO_REPO}/_artifacts/ssh/cluster-api-provider-openstack-sigs-k8s-io.pub"
echo "export OPENSTACK_SSH_AUTHORIZED_KEY=$(cat $CAPO_E2E_SSH_KEY)" >> /tmp/e2e_vars_openstack.sh

echo "source relevant variables"
source ./capo_os_vars.rc
source ./e2e_os_vars.rc
source /tmp/e2e_vars_openstack.sh

# Remove capo-e2e cluster, if it exists
kind delete cluster --name capo-e2e || echo "capo-e2e ind cluster does not exist"
rm -rf  "${CAPO_REPO}/_artifacts/ssh" | echo "No ssh keys found"
docker run --rm -v /tmp/openstackrc:/tmp/openstackrc openstacktools/openstack-client \
    bash -c "source /tmp/openstackrc && openstack keypair delete cluster-api-provider-openstack-sigs-k8s-io 2>/dev/null"
# move to capo repo
pushd "${CAPO_REPO}"
# replace cirros user by ubuntu
sed 's/cirros/ubuntu/' -i test/e2e/shared/exec.go
make test-e2e
popd

# Needs to be done from the e2e test go code
# eval $(ssh-agent -s)
# ssh-add -k cluster-api-provider-openstack-sigs-k8s-io
# ssh -A -i cluster-api-provider-openstack-sigs-k8s-io 188.95.231.106
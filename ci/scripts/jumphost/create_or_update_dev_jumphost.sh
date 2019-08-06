#! /usr/bin/env bash

set -eu

CI_DIR="$(dirname "$(readlink -f "${0}")")/../.."
OS_SCRIPTS_DIR="${CI_DIR}/scripts/openstack"
RT_SCRIPTS_DIR="${CI_DIR}/scripts/artifactory"
JUMPHOST_SCRIPTS_DIR="${CI_DIR}/scripts/jumphost"

# shellcheck disable=SC1090
source "${RT_SCRIPTS_DIR}/utils.sh"
# shellcheck disable=SC1090
source "${OS_SCRIPTS_DIR}/utils.sh"
# shellcheck disable=SC1090
source "${OS_SCRIPTS_DIR}/infra_defines.sh"

JUMPOST_INT_PORT_NAME="${DEV_JUMPHOST_NAME}-int-port"
JUMPOST_EXT_PORT_NAME="${DEV_JUMPHOST_NAME}-ext-port"
JUMPHOST_FLAVOR="4C-16GB-50GB"

# Create or rebuild jumphost image
JUMPHOST_SERVER_ID="$(openstack server list --name "${DEV_JUMPHOST_NAME}" -f json \
  | jq -r 'map(.ID) | @csv' \
  | tr ',' '\n' \
  | tr -d '"')"

if [ -n "${JUMPHOST_SERVER_ID}" ]
then
  echo "Rebuilding DEV Jumphost with ID[${JUMPHOST_SERVER_ID}]."
  openstack server rebuild --image "${CI_JENKINS_IMAGE}" "${JUMPHOST_SERVER_ID}" > /dev/null
else

  # Cleanup any stale ports
  delete_port "${JUMPOST_EXT_PORT_NAME}"
  delete_port "${JUMPOST_INT_PORT_NAME}"

  # Create new ports
  echo "Creating new jumphost ports."
  INT_PORT_ID="$(openstack port create -f json \
    --network "${DEV_INT_NET}" \
    --fixed-ip subnet="$(get_subnet_name "${DEV_INT_NET}")" \
    "${JUMPOST_INT_PORT_NAME}" | jq -r '.id')"
  EXT_PORT_ID="$(openstack port create -f json \
    --network "${DEV_EXT_NET}" \
    --fixed-ip subnet="$(get_subnet_name "${DEV_EXT_NET}")" \
    "${JUMPOST_EXT_PORT_NAME}" | jq -r '.id')"

  # Create new jumphost
  echo "Creating new jumphost Server."
  JUMPHOST_SERVER_ID="$(openstack server create -f json \
    --image "${CI_JENKINS_IMAGE}" \
    --flavor "${JUMPHOST_FLAVOR}" \
    --port "${EXT_PORT_ID}" \
    --port "${INT_PORT_ID}" \
    "${DEV_JUMPHOST_NAME}" | jq -r '.id')"
fi

# Recycle or create floating IP and assign it to jumphost port
FLOATING_IP_ID="$(openstack floating ip list --tags "${DEV_JUMPHOST_FLOATING_IP_TAG}" -f json \
    | jq -r 'map(.ID) | @csv' \
    | tr ',' '\n' \
    | tr -d '"')"

if [ -n "${FLOATING_IP_ID}" ]
then
  echo "Unattaching and Attaching floating IP to updated Jumphost port"
  openstack floating ip unset --port "${FLOATING_IP_ID}" > /dev/null
  openstack floating ip set --port "${JUMPOST_EXT_PORT_NAME}" "${FLOATING_IP_ID}" > /dev/null
else

  echo "Creating new jumphost floating ip"
  FLOATING_IP_ID="$(openstack floating ip create -f json \
    --port "${JUMPOST_EXT_PORT_NAME}" \
    --tag "${DEV_JUMPHOST_FLOATING_IP_TAG}" \
    "${EXT_NET}" | jq -r '.id')"
fi

FLOATING_IP_ADDRESS="$(openstack floating ip list --tags "${DEV_JUMPHOST_FLOATING_IP_TAG}" -f json \
  | jq -r 'map(."Floating IP Address") | @csv' \
  | tr ',' '\n' \
  | tr -d '"')"

echo "DEV Jumphost Public IP = ${FLOATING_IP_ADDRESS}"

wait_for_ssh "${AIRSHIP_CI_USER}" "${AIRSHIP_CI_USER_KEY}" "${FLOATING_IP_ADDRESS}"


# Update Authorized users in Jumphost
"${JUMPHOST_SCRIPTS_DIR}/update_dev_jumphost_users.sh"
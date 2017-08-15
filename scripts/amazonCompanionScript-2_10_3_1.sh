#!/bin/bash
#Source properties file
source /tmp/amazonProperties.properties
#Source common functions
source /tmp/common-2_10_3_1.sh

INSTALLATION_MODE=${1:-EMR}

MAX_HEAP=$(awk '$1=="MemTotal:"{printf("%d\n", $2 * 2/5000000)}' /proc/meminfo)
LICENSE_PATH=/tmp/license.key
PROPS_FILE=/tmp/silent_installer.properties
FUSION_HOSTS_FILE=/tmp/fusionhosts
FUSION_HOSTNAME=$(curl -f http://169.254.169.254/latest/meta-data/public-ipv4)
FUSION_HOSTNAME=${FUSION_HOSTNAME%% *}
INSTANCE_ID=$(curl -f http://169.254.169.254/latest/meta-data/instance-id)
export SILENT_CONFIG_PATH="/tmp/silent_installer_env.sh"

function create_silent_installer_properties(){
  echo "Creating Fusion silent install properties."
  cat << EOF > "$PROPS_FILE"
license.file.path=${LICENSE_PATH}
server.java.heap.max=${MAX_HEAP}
ihc.server.java.heap.max=${MAX_HEAP}
fusion.domain=${FUSION_HOSTNAME}
fusion.server.zone.name=${ZONE_NAME}
fusion.scheme.and.fs=fusionWithHcfs
s3.bucket.name=${BUCKET_NAME}
fs.s3.buffer.dir=/mnt/s3
local.user.password=${PASSWORD}
local.user.username=${USERNAME}
EOF

  # optional parameters
  # induction

  if [ -n "${INDUCTOR_IP}" ]; then
    cat << EOF >> ${PROPS_FILE}
induction.skip=false
induction.remote.node=${INDUCTOR_IP}
EOF
  else
    cat << EOF >> ${PROPS_FILE}
induction.skip=true
EOF
  fi

  # add to zone
  if [ -n "${EXISTING_ZONE_HOST}" ]; then
    cat << EOF >> ${PROPS_FILE}
existing.zone.domain=${EXISTING_ZONE_HOST}
existing.zone.port=8083
EOF
  fi

  if [ "$INSTALLATION_MODE" == "EMR" ]; then
    echo "hadoop.tmp.dir=/mnt/var/lib/hadoop/tmp" >> "$PROPS_FILE"
    echo "management.endpoint.type=UNMANAGED_EMR" >> "$PROPS_FILE"
    echo "emr.installation.mode=true" >> "$PROPS_FILE"

    if [ -n "$SERVER_ENCRYPTION_ALGORITHM" ]; then
        cat << EOF >> "$PROPS_FILE"
s3.fs.encryption=true
s3.fs.encryption.algorithm=${SERVER_ENCRYPTION_ALGORITHM}
EOF
      fi

      # KMS encryption
      if [ -n "$KMS_KEY" ]; then
        cat << EOF >> "$PROPS_FILE"
fs.s3.cse.enabled=true
fs.s3.cse.kms.keyId=${KMS_KEY}
EOF
      fi
  fi

  # S3 plugin mode

  if [ "$INSTALLATION_MODE" == "S3" ]; then
    echo "management.endpoint.type=UNMANAGED_S3" >> "$PROPS_FILE"
    echo "s3.installation.mode=true" >> "$PROPS_FILE"
    if [[ -n "${BUCKET_REGION_ENDPOINT}" ]]; then
      echo "fs.fusion.s3.endpoint=${BUCKET_REGION_ENDPOINT}" >> "$PROPS_FILE"
    fi

    if [[ -n "${S3_SEGMENT_SIZE}" ]]; then
      S3_SEGMENT_SIZE_IN_BYTES=$((S3_SEGMENT_SIZE*1024**2))
      echo "fs.fusion.s3.segmentSize=${S3_SEGMENT_SIZE_IN_BYTES}L" >> "$PROPS_FILE"
    fi
  fi
  chown hdfs:hdfs "$PROPS_FILE"
}

function create_silent_installer_env() {
  echo "Creating silent installer env.sh."
  cat << EOF > "$SILENT_CONFIG_PATH"
SILENT_PROPERTIES_PATH=${PROPS_FILE}
FUSIONUI_USER=hdfs
FUSIONUI_GROUP=hdfs
FUSIONUI_FUSION_BACKEND_CHOICE=${BACKEND_VERSION}
FUSIONUI_INTERNALLY_MANAGED_USERNAME=${USERNAME}
FUSIONUI_INTERNALLY_MANAGED_PASSWORD=${PASSWORD}
EOF
  chown hdfs:hdfs "$SILENT_CONFIG_PATH"
}


function create_membership() {
  # sleep to allow nodes to catch up with induction
  sleep 60

  # Get a list of nodeid and locationid from the remote node
  NODES_INFO=$(curl -s ${INDUCTOR_IP}:8082/fusion/nodes)
  node_count=$(echo "$NODES_INFO" | xmllint  --xpath "count(//node)" - );
  declare -a nodes=( )
  declare -a locations=( )

  node_counter=0
  while [[ "$node_counter" -lt "$node_count" ]]; do
    nodes[$node_counter]=$(echo "$NODES_INFO" | xmllint --xpath "//node[$node_counter+1]/nodeIdentity/text()" -)
    locations[$node_counter]=$(echo "$NODES_INFO" | xmllint --xpath "//node[$node_counter+1]/locationIdentity/text()" -)
    ((node_counter++))
  done

  if [[ "${#nodes[@]}" -eq 0 || "${#locations[@]}" -eq 0 ]]; then
    error_exit "Could not find nodes or locations for membership creation." "$CLUSTER_COMPLETE_HANDLE" 1
  fi

  # Make sure all aws nodes are inducted
  awk '{print $1}' "$FUSION_HOSTS_FILE" | readarray -t HOSTS_ARRAY
  for host in "${HOSTS_ARRAY[@]}"; do
    host_id=$(curl "$host":8082/fusion/nodes/local | xmllint --xpath "//nodeIdentity[1]/text()" -)
    if [[ -z "$host_id" ]]; then
      error_exit "Unable to obtain the node id for ${HOSTS_ARRAY[$i]}", "$CLUSTER_COMPLETE_HANDLE" 1
    else
      if ! containsElement "$host_id" "${nodes[@]}"; then
        error_exit "Remote node is not aware of all AWS nodes." "$CLUSTER_COMPLETE_HANDLE" 1
      fi
    fi
  done

  MEMBERSHIP_XML=/tmp/membership
  MEMBERSHIP_ID="${#nodes[@]}-Node-Membership-${RANDOM}${RANDOM}"

  cat << EOF > ${MEMBERSHIP_XML}
<membership>
<membershipIdentity>${MEMBERSHIP_ID}</membershipIdentity>
<distinguishedNodeIdentity>${nodes[0]}</distinguishedNodeIdentity>
<acceptors>
$(for (( i=0; i < ${#nodes[@]}; i++ )); do echo -e "<node>
<nodeIdentity>${nodes[$i]}</nodeIdentity>
<nodeLocation>${locations[$i]}</nodeLocation>
</node>"; done)
</acceptors>
<proposers>
$(for (( i=0; i < ${#nodes[@]}; i++ )); do echo -e "<node>
<nodeIdentity>${nodes[$i]}</nodeIdentity>
<nodeLocation>${locations[$i]}</nodeLocation>
</node>"; done)
</proposers>
<learners>
$(for (( i=0; i < ${#nodes[@]}; i++ )); do echo -e "<node>
<nodeIdentity>${nodes[$i]}</nodeIdentity>
<nodeLocation>${locations[$i]}</nodeLocation>
</node>"; done)
</learners>
</membership>
EOF

  #make sure the membership was created
  NODE2_NODEID=$(curl -s ${FUSION_HOSTNAME}:8082/fusion/nodes/local | xmllint --xpath "//nodeIdentity[1]/text()" -)
  if [[ -z "$NODE2_NODEID" ]]; then
    error_exit "Unable to find id of second node to validate membership creation." "$CLUSTER_COMPLETE_HANDLE" 1
  fi

  attempt_counter=0
  max_attempts=10

  while ! does_membership_exist; do
    ((attempt_counter++))
    if [[ "$attempt_counter" -lt "$max_attempts" ]]; then
      sleep 10
    else
      error_exit "Did not get expected response to membership creation." "$CLUSTER_COMPLETE_HANDLE" 1
    fi
  done
}

function does_membership_exist() {
  RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -d@${MEMBERSHIP_XML} -H "Content-Type: application/xml" http://${FUSION_HOSTNAME}:8082/fusion/node/${NODE2_NODEID}/membership)
  if [[ "$RESPONSE_CODE" -eq 200 || "$RESPONSE_CODE" -eq 202 ]]; then
    return 0
  else
    return 1
  fi
}


sns_subscribe "$SUBSCRIBE_EMAIL_ARN" "$AWS_REGION" "$SUBSCRIBE_EMAIL_ADDRESS"
update_cloud_formation_tools
validate_security_group "$AWS_REGION" "$SECURITY_GROUP_ID"
if [ "$INSTALLATION_MODE" == "EMR" ]; then
  check_bucket_region "$BUCKET_NAME" "$AWS_REGION"
fi

iptables -I INPUT 3 -p tcp --dport 8023 -j ACCEPT
service iptables save

get_private_ips
wait_for_nodes_to_start_with_launch_index
tag_instance "$AWS_CLUSTER_NAME" "$LAUNCH_INDEX" "$INSTANCE_ID" "$AWS_REGION"
get_license "$LICENSE_PATH" "$LICENSE_URL"
setup_hadoop
create_silent_installer_properties
create_silent_installer_env
install_fusion "$FUSION_INSTALLER"
signal_and_wait "$AWS_STACKID" "$AWS_REGION" "$FUSION_INSTALLED_HANDLER" "FusionInstalledCondition"

# remove_from_autoscaling_group "$INSTANCE_ID" "$AWS_REGION"
# the last node will create a default membership if there is only one zone
if [ "$LAUNCH_INDEX" -eq $(( $CLUSTER_INSTANCE_COUNT - 1 )) ] && [ -n "$INDUCTOR_IP" ]; then
  create_membership
fi
delete_root_volume_on_terminate "$INSTANCE_ID" "$AWS_REGION"

curl -X PUT http://localhost:8082/fusion/zone/properties/local\?ihcDirection\=INBOUND
service fusion-ihc-server-emr_5_4_0 stop && service fusion-server stop && service fusion-ihc-server-emr_5_4_0 start && service fusion-server start

send_notification "$SUBSCRIBE_EMAIL_ARN" "$AWS_REGION"
signal_and_wait "$AWS_STACKID" "$AWS_REGION" "$CLUSTER_COMPLETE_HANDLE" "ClusterCompleteCondition"


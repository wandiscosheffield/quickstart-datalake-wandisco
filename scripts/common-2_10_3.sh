#!/bin/bash

BOOTSTRAP_LATEST_URL="https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz"
VALIDATION_SCRIPT_PATH="/tmp/validation-2_10_3.py"
INSTALLER_PATH="/tmp/fusion-ui-server-installer.sh"
DEFAULT_LICENSE_URL="s3://wandisco-public-files/fusion/license.key"
DEFAULT_LICENSE_BUCKET_REGION="eu-west-1"

function containsElement() {
  test -z "$1" && return 1
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

function update_cloud_formation_tools() {
    echo "Installing cloud formation tools."
    if ! easy_install "$BOOTSTRAP_LATEST_URL"; then
        echo "Could not update cloud formation tools."
        exit_with_signal
    fi
}

function setup_hadoop() {
  echo "Setting up hadoop directories."
  mkdir -p /mnt/s3 /mnt/var/lib/hadoop/tmp
  chown hadoop:hadoop -R /mnt/s3 /mnt/var/lib/hadoop/tmp
  chmod a+w /mnt/s3 /mnt/var/lib/hadoop/tmp
}

function error_exit() {
  local message=$1
  local resource=$2
  local exit_code=$3

  test -z "$message" && message="Unknown error."
  test -z "$exit_code" && exit_code="1"

  if [[ -z "$resource" ]]; then
    echo "No resource specified, unable to signal resource!"
  else
    /opt/aws/bin/cfn-signal -e "$exit_code" "$resource" -r "$message"
  fi

  exit 1
}


function get_license() {
  local license_path=$1
  local license_url=$2

  test -z "$license_path" && error_exit "Unable to get license, no license path provided." "$FUSION_INSTALLED_HANDLER" 1

  if [ -z "$license_url" ]; then
    license_url="$DEFAULT_LICENSE_URL"
    LICENSE_BUCKET_REGION="$DEFAULT_LICENSE_BUCKET_REGION"
  fi

  if [[ ${license_url} =~ ^s3://[^/]+/.+ ]]; then
    if [[ -z "${LICENSE_BUCKET_REGION}" ]]; then
      LICENSE_BUCKET_REGION=$(aws s3api get-bucket-location --bucket ${BUCKET_NAME} | awk '{gsub(/"/, "", $2); print $2}')
    fi
    aws s3 cp --region ${LICENSE_BUCKET_REGION} "$license_url" "$license_path"
  else
    wget "$license_url" -O "$license_path"
  fi

  if ! [ -s "$license_path" ]; then
    error_exit "'$license_url' is an invalid license" "$FUSION_INSTALLED_HANDLER" 1
  fi

  chown hdfs:hdfs "$license_path"
}

function tag_instance() {
  local cluster_name=$1
  local launch_index=$2
  local instance_id=$3
  local region=$4

  test -z "$cluster_name" && error_exit "Unable to tag instance! Clustername not provided!" "$FUSION_INSTALLED_HANDLER" 1
  test -z "$launch_index" && error_exit "Unable to tag instance! Launch index not provided!" "$FUSION_INSTALLED_HANDLER" 1
  test -z "$instance_id" && error_exit "Unable to tag instance! Instance id not provided!" "$FUSION_INSTALLED_HANDLER" 1
  test -z "$region" && error_exit "Unable to tag instance! Region not provided!" "$FUSION_INSTALLED_HANDLER" 1

  echo "Tagging instance."
  local instance_tag="$cluster_name-node$launch_index"
  aws ec2 create-tags --region "$region" --resources "$instance_id" --tags Key=Name,Value="$instance_tag"
}

function validate_security_group() {
  local region=$1
  local security_group_id=$2

  test -z "$region" && error_exit "Unable to validate security group. No region provided!" "$FUSION_INSTALLED_HANDLER" 1
  test -z "$security_group_id" && error_exit "Unable to validate security group. Security group not provided!" "$FUSION_INSTALLED_HANDLER" 1

  echo "Validating security group."
  ## Check that the security group is configured correctly
  aws s3 cp s3://wandisco-public-files/scripts/validation-2_10_3.py "$VALIDATION_SCRIPT_PATH"
  if [[ ! -e  "$VALIDATION_SCRIPT_PATH" ]]; then
    error_exit "Could not download validation-2_10_3.py." "$FUSION_INSTALLED_HANDLER" 1
  else
    if ! python "$VALIDATION_SCRIPT_PATH" "$region" "$security_group_id"; then
      error_exit "Error running validation script, see logs for more information." "$FUSION_INSTALLED_HANDLER" 1
    fi
  fi
}

function install_fusion() {
  local fusion_installer=$1

  test -z "$fusion_installer" && error_exit "Unable to install Fusion. Fusion installer not specified!" "$FUSION_INSTALLED_HANDLER" 1

  echo "Downloading and installing Fusion."
  aws s3 cp "$fusion_installer" "$INSTALLER_PATH"
  if [[ ! -e "$INSTALLER_PATH" ]]; then
    error_exit "Unable to download the Fusion installer." "$FUSION_INSTALLED_HANDLER" 1
  fi

  sh "$INSTALLER_PATH"
}


function remove_from_autoscaling_group() {
  local instance_id=$1
  local region=$2

  test -z "$instance_id" && error_exit "Unable to remove from auto scaling group. Instance id not specified!" "$CLUSTER_COMPLETE_HANDLE" 1
  test -z "$region" && error_exit "Unable to remove from auto scaling group. Region not specified!" "$CLUSTER_COMPLETE_HANDLE" 1

  echo "Removing instance from autoscaling group."
  local autoScalingGroupId=$(aws autoscaling describe-auto-scaling-instances --instance-ids="$instance_id" --region="$region" | grep AutoScalingGroupName | cut -d \" -f4)

  if ! aws autoscaling detach-instances --instance-ids "$instance_id" --auto-scaling-group-name "$autoScalingGroupId" --should-decrement-desired-capacity --region="$region"; then
    error_exit "Unable to remove node from autoscaling group." "$CLUSTER_COMPLETE_HANDLE" 1
  fi
}

function wait_for_resource_complete() {
  local resource_id=$1
  local stack_id=$2
  local region=$3
  local error_resource=$4

  if [[ -z "$error_resource" ]]; then
    echo "No error resource provided for get_resource_status."
    echo "Unable to signal failure!"
    exit 1
  fi

  test -z "$resource_id" && error_exit "Unable to get resource status. Resource ID not specified!" "$error_resource" 1
  test -z "$region" && error_exit "Unable to get resource status. Region not specified!" "$error_resource" 1
  test -z "$stack_id" && error_exit "Unable to get resource status. Stack name not specified!" "$error_resource" 1

  local count=0
  while [[ $(aws cloudformation describe-stack-resources --region "$region" --stack-name "$stack_id" --logical-resource-id "$resource_id" --query StackResources[].ResourceStatus --output text) != "CREATE_COMPLETE" ]]; do
    if [[ "$count" -lt "10" ]]; then
      sleep 60
      ((count++))
    else
      error_exit "Resource was not complete after 10 minutes." "$error_resource" 1
    fi
  done
}

function signal_and_wait() {
  local stack_id=$1
  local region=$2
  local handler=$3
  local resource_id=$4

  if [[ -z "$handler" ]]; then
    echo "No resource handler provided for signal_and_wait."
    echo "Unable to signal failure!"
    exit 1
  fi

  test -z "$resource_id" && error_exit "Unable to signal handler: $handler. Resource id not specified." "$handler" 1
  test -z "$stack_id" && error_exit "Unable to signal handler:$handler. Stack name not specified!" "$handler" 1
  test -z "$region" && error_exit "Unable to signal handler:$handler. Region not specified!" "$handler" 1

  /opt/aws/bin/cfn-signal -e 0 "$handler"

  wait_for_resource_complete "$resource_id" "$stack_id" "$region" "$handler"
}

function check_bucket_region() {
  local bucket_name=$1
  local region=$2

  test -z "$bucket_name" && error_exit "Unable to validate bucket region. No bucket_name provided." "$FUSION_INSTALLED_HANDLER" 1
  test -z "$region" && error_exit "Unable to validate bucket region. No region provided." "$FUSION_INSTALLED_HANDLER" 1

  ##Check bucket region is same as AWS region
  local aws_bucket_region=$(aws s3api get-bucket-location --bucket "$bucket_name"| jq -r '.LocationConstraint')
  if [[ "$aws_bucket_region" != "$region" ]] && [[ "$aws_bucket_region" != "null" ]]; then
    error_exit "Bucket's must be in the same region as stack! Bucket $bucket_name is in $aws_bucket_region." "$FUSION_INSTALLED_HANDLER" 1

  ##Buckets can be made in the US Standard region which returns null but is the us-east-1 region
  ##See http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region
  elif [[ "$aws_bucket_region" = "null" ]] && [[ "$region" != "us-east-1" ]]; then
    error_exit "Bucket's must be in the same region as stack! Bucket $bucket_name is in us-east-1." "$FUSION_INSTALLED_HANDLER" 1
  fi
}

function wait_for_preceeding_nodes_to_start() {
  local existing_zone_host=$1
  local zone_name=$2
  local launch_index=$3

  test -z "$existing_zone_host" && error_exit "Unable to check status of other nodes. No existing_zone_host provided." "$FUSION_INSTALLED_HANDLER" 1
  test -z "$zone_name" && error_exit "Unable to check status of other nodes. No zone_name provided." "$FUSION_INSTALLED_HANDLER" 1
  test -z "$launch_index" && error_exit "Unable to check status of other nodes. No launch_index provided." "$FUSION_INSTALLED_HANDLER" 1

  local attempt=1
  local max_attempts=30
  local sleep_time=60
  local num_nodes=0

  for ((attempt=1; attempt <= $max_attempts; attempt++)); do
    num_nodes=$(curl "$existing_zone_host:8082/fusion/locations" 2>/dev/null | \
      xmllint --xpath "count(//key[text()=\"zone\"]/parent::*/value[text()=\"$zone_name\"])" - 2>/dev/null)

    if [[ "$num_nodes" -lt "$launch_index" ]]; then
      echo "Only ${num_nodes:-0} of $launch_index have nodes started up. "
      echo "Sleeping for $sleep_time seconds, Attempt $attempt of $max_attempts."
      sleep "$sleep_time"
    else
      break
    fi
  done

  if [[ "$num_nodes" -lt "$launch_index" ]]; then
    error_exit "Not all nodes were started in time." "$FUSION_INSTALLED_HANDLER" 1
  else
    echo "All nodes have started."
  fi
}

function sns_subscribe() {
  local subscribe_email_arn="$1"
  local aws_region="$2"
  local subscribe_email_address="$3"

  [[ -n "$aws_region" ]] && aws_region=" --region $aws_region"

  if [[ -n "${subscribe_email_arn}" ]]; then
    aws sns subscribe --topic-arn ${subscribe_email_arn} --protocol email --notification-endpoint ${subscribe_email_address} ${aws_region}
  fi
}

function send_notification() {
  eip=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
  int_ip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)

  local subscribe_email_arn="$1"
  local aws_region="$2"
  local message_sns=${3:-"Automated email from WANdisco Fusion. Fusion has been successfully deployed on instance ${eip} / ${int_ip} : You can connect to the FusionUI on either http://${eip}:8083 OR http://${int_ip}:8083 - which link works depends on your AWS security group setup."}

  [[ -n "$aws_region" ]] && aws_region=" --region $aws_region"

  if [[ -n "${subscribe_email_arn}" ]]; then
    aws sns publish --topic-arn ${subscribe_email_arn} --message "${message_sns}" ${aws_region}
  fi
}

function get_private_ips() {
  echo "Getting private ip of all nodes being created."
  aws ec2 describe-instances --output text --region "$AWS_REGION" \
    --filters 'Name=instance-state-name,Values=running' \
    --query 'Reservations[].Instances[].[PrivateDnsName,AmiLaunchIndex,InstanceId,Tags[?Key == `aws:cloudformation:stack-id`] | [0].Value ] ' \
    | grep -w "$AWS_STACKID" | sort -k 2 | awk '{print $1" FUSIONNODE"NR-1" "$3}' > "$FUSION_HOSTS_FILE"
  if [[ ! -e "$FUSION_HOSTS_FILE" ]]; then
    error_exit "Unable to get the private ips of the other nodes." "$FUSION_INSTALLED_HANDLER" 1
  fi
}

function wait_for_nodes_to_start_with_launch_index() {
  # now we have the private ips get the launch index and existing zone host
  LAUNCH_INDEX=$(curl http://169.254.169.254/latest/meta-data/ami-launch-index)

  if [ "$LAUNCH_INDEX" -gt 0 ]; then
    EXISTING_ZONE_HOST=$(awk '/\<FUSIONNODE0\>/{print $1}' "$FUSION_HOSTS_FILE")
    INDUCTOR_IP=${INDUCTOR_IP:-$EXISTING_ZONE_HOST}

    wait_for_preceeding_nodes_to_start "$EXISTING_ZONE_HOST" "$ZONE_NAME" "$LAUNCH_INDEX"

    echo "Other nodes are available but will pause for another 120 seconds just to make sure the installation of Fusion can be successful."
    sleep 120
  else
    echo "This is the first or only node, skipping wait."
  fi
}

function delete_root_volume_on_terminate() {
  local instance_id="$1"
  local aws_region="$2"
  aws ec2 modify-instance-attribute --instance-id "$instance_id" --block-device-mappings "[{\"DeviceName\": \"/dev/xvda\",\"Ebs\":{\"DeleteOnTermination\":true}}]" --region "$aws_region"
}

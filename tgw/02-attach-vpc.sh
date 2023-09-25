#!/bin/bash

#
# Attach a VPC to the TGW created via 01-create-tgw.sh 
# Creates a stack that defines a Transit Gateway Attachment
#

main() {

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        shift
        if [[ "$1" != "" ]]; then
          NAME="$1"
        else
          err "Missing value for --name."
          usage
        fi
        ;;

      --vpcid)
        shift
        if [[ "$1" != "" ]]; then
          VPCID="$1"
        else
          err "Missing value for --vpcid."
          usage
        fi
        ;;

      --subnetid1)
        shift
        if [[ "$1" != "" ]]; then
          SUBNETID1="$1"
        else
          err "Missing value for --subnetid1."
          usage
        fi
        ;;

      --subnetid2)
        shift
        if [[ "$1" != "" ]]; then
          SUBNETID2="$1"
        else
          err "Missing value for --subnetid2."
          usage
        fi
        ;;

      --subnetid3)
        shift
        if [[ "$1" != "" ]]; then
          SUBNETID3="$1"
        else
          err "Missing value for --subnetid3."
          usage
        fi
        ;;

      --routes)
        shift
        if [[ "$1" != "" ]]; then
          ROUTES="$1"
        else
          err "Missing value for --routes."
          usage
        fi
        ;;

      --help)
        shift
        usage
        exit 1
        ;;

      --region)
        shift
        if [[ "$1" != "" ]]; then
          REGION_ARG="$1"
        else
          err "Missing value for --region."
          usage
        fi
        ;;

      *)
        echo "Unknown argument: $1"
        usage
        ;;
    esac
    shift
  done

  echo "Beginning... $0"

  # Which region? Display to user so they can double-check.
  # Our first preference is the --region argument, then AWS_DEFAULT_REGION, lastly just use that set in the profile.
  REGION=${REGION_ARG:-${AWS_DEFAULT_REGION:-$(aws configure get default.region)}}

  echo $REGION
  echo "TGW Attachment will be setup in $REGION..."

  validate_arguments

  PREFIX=$NAME
  echo "All stack names will be prefixed with $PREFIX..."

  # Retrieve the TGW ID from the stack.
  TGWID=$(aws cloudformation list-exports --query "Exports[?Name=='$NAME-TgwId'].Value" --output text --region $REGION)
  if [[ -z "$TGWID" ]]; then
    err "TGWID=$TGWID - TGW can't be found)..."
    exit 2
  fi
  echo "TGWID=$TGWID"

  # Validate TGW is available.
  TGW_STATUS=$(aws ec2 describe-transit-gateways --transit-gateway-ids $TGWID --region $REGION --query "TransitGateways[0].State" --output text)
  if [[ "$TGW_STATUS" != "available" ]]; then
    err "TGWID=$TGWID is not in available status (or can't be found)..."
    exit 2
  fi

  STACK_NAME=$PREFIX-tgw-attachment-$VPCID
  aws cloudformation deploy --template-file tga.yaml \
  --parameter-overrides Prefix=$NAME \
  VpcId=$VPCID \
  TgwId=$TGWID \
  SubnetId1=$SUBNETID1 \
  SubnetId2=$SUBNETID2 \
  SubnetId3=$SUBNETID3 \
  --stack-name $STACK_NAME --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION
  aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region $REGION

  aws cloudformation wait stack-exists --stack-name $STACK_NAME --region $REGION
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --region $REGION --output text)
  if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
          err "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
          exit 1
  fi

  echo "$STACK_NAME is ready."

  # We ALSO need to put Routes into the VPCs route tables.
  # Loop through all the route tables in the VPC. Add the --routes specified.
  # REMEMBER: --routes needs to specify the CIDR ranges for OTHER VPCs that we want to be able to connect to.
  IFS=','
  read -ra routes <<< "$ROUTES"

  ROUTETABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPCID" --region $REGION --query "RouteTables[*].RouteTableId" --output text | tr -s '[:blank:]' '\n')
  echo $ROUTETABLES

  IFS=$'\n'
  for rt in $ROUTETABLES; do
    for route in "${routes[@]}"; do
      echo "Adding route=$route to $rt"
      # Add route to routetable here.
      # We try to replace existing rule first. If that fails (254) then do a create instead.
      aws ec2 replace-route --transit-gateway-id $TGWID --route-table-id $rt --destination-cidr-block $route --region $REGION
      if [[ "$?" == 254 ]]; then
         aws ec2 create-route --transit-gateway-id $TGWID --route-table-id $rt --destination-cidr-block $route --region $REGION
      fi
    done
  done
 
}

err() {
   echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

usage() {
  echo " Create a Transit Gateway Attachment for a VPC."
  echo " "
  echo " --name : The "Name" tag value of the TGW."
  echo " --vpcid : The ID of the VPC to attach."
  echo " --subnetid1 : The first ID of a subnet (in the VPC) to used by TGW."
  echo " --subnetid2 : The second ID of a subnet (in the VPC) to used by TGW."
  echo " --routes : Comma delimited list of CIDRs to be reached via the TGW, such as: 192.168.1.0/24,172.31.0.0/16"
  echo " --region : Region (Optional)"
  echo " --help : This help."
  echo " "
  exit 1
}

validate_subnet() {
  local subnet_id="$1"
  SUBNET_STATUS=$(aws ec2 describe-subnets --subnet-ids $subnet_id --region $REGION --query "Subnets[0].State" --output text)
  if [[ "$SUBNET_STATUS" != "available" ]]; then
    err "subnet_id=$subnet_id is not in available state (or can't be found)..."
    exit 2
  fi

}

validate_arguments() {
  
  if [[ -z "$NAME" ]]; then
    err "Missing required argumemts."
    usage
    exit 1
  fi

  if [[ -z "$VPCID" ]]; then
    err "Missing required argumemts."
    usage
    exit 1
  fi

  if [[ -z "$ROUTES" ]]; then
    err "Missing required argumemts."
    usage
    exit 1
  fi

  # Make sure VPC is legit
  VPC_STATUS=$(aws ec2 describe-vpcs --vpc-ids $VPCID --region $REGION --query "Vpcs[0].State" --output text)
  if [[ "$VPC_STATUS" != "available" ]]; then
    err "VPCID=$VPCID is not in available status (or can't be found)..."
    exit 2
  fi

  if [[ -z "$SUBNETID1" ]]; then
    err "Missing required argumemts."
    usage
    exit 1
  fi
  # Make sure Subnet is legit and belongs to the VPC
  validate_subnet $SUBNETID1

  if [[ -z "$SUBNETID2" ]]; then
    err "Missing required argumemts."
    usage
    exit 1
  fi
  validate_subnet $SUBNETID2

  # TGW Has to be in each AZ you want to use... so if there is a 3rd subnet setting provided, we'll handle that.
  if [[ "$SUBNETID3" != "" ]]; then
    validate_subnet $SUBNETID3
  fi 

}

main "$@"
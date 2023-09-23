#!/bin/bash

#
# Peer TGW with another TGW in another region 
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

      --peerregion)
        shift
        if [[ "$1" != "" ]]; then
          PEERREGION="$1"
        else
          err "Missing value for --peerregion."
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

      --peerroutes)
        shift
        if [[ "$1" != "" ]]; then
          PEERROUTES="$1"
        else
          err "Missing value for --peerroutes."
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

  
  # Which region? Display to user so they can double-check.
  # Our first preference is the --region argument, then AWS_DEFAULT_REGION, lastly just use that set in the profile.
  REGION=${REGION_ARG:-${AWS_DEFAULT_REGION:-$(aws configure get default.region)}}

  echo $REGION
  echo "TGW Attachment will be setup in $REGION (with peer in $PEERREGION)..."

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

  # Retrieve the TGW ID from the stack.
  PEERTGWID=$(aws cloudformation list-exports --query "Exports[?Name=='$NAME-TgwId'].Value" --output text --region $PEERREGION)
  if [[ -z "$PEERTGWID" ]]; then
    err "PEERTGWID=$PEERTGWID - TGW can't be found)..."
    exit 2
  fi
  echo "PEERTGWID=$PEERTGWID"

  # Validate TGW is available.
  PEERTGW_STATUS=$(aws ec2 describe-transit-gateways --transit-gateway-ids $PEERTGWID --region $PEERREGION --query "TransitGateways[0].State" --output text)
  if [[ "$PEERTGW_STATUS" != "available" ]]; then
    err "PEERTGWID=$PEERTGWID is not in available status (or can't be found)..."
    exit 2
  fi

  STACK_NAME=$PREFIX-tgw-peer-$PEERTGWID
  aws cloudformation deploy --template-file peer.yaml \
  --parameter-overrides Prefix=$NAME \
  PeerRegion=$PEERREGION \
  TgwId=$TGWID \
  PeerTgwId=$PEERTGWID \
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

  # Accept the peering attachment - gotta do this from the remote side
  PEER_ACCEPT=$(aws ec2 describe-transit-gateway-peering-attachments --query "TransitGatewayPeeringAttachments[?State=='pendingAcceptance'].TransitGatewayAttachmentId" --output text --region $PEERREGION)

  if [[ -z "$PEER_ACCEPT" ]]; then
    err "Did not find any peering attachment in pendingAcceptance status in $PEERREGION."
    # Don't exit out - just assume it was already accepted.
  else
    aws ec2 accept-transit-gateway-peering-attachment --transit-gateway-attachment-id $PEER_ACCEPT --region $PEERREGION
  fi

  # Specify TGW Static Routes on both ends.

  # Need to find:
  # The Peered Attachment ID
  # The Route Table ID for each 
  ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-peering-attachments --filter "Name=transit-gateway-id,Values=$TGWID" "Name=state,Values=available" --region $REGION --query "TransitGatewayPeeringAttachments[0].TransitGatewayAttachmentId" --output text)
  echo "ATTACHMENT_ID=$ATTACHMENT_ID"

  ROUTE_TABLE_ID=$(aws ec2 describe-transit-gateways --region $REGION --transit-gateway-ids $TGWID --query "TransitGateways[0].Options.PropagationDefaultRouteTableId" --output text)
  echo "ROUTE_TABLE_ID=$ROUTE_TABLE_ID"

  IFS=','
  read -ra routes <<< "$ROUTES"

  for route in "${routes[@]}"; do
    echo "Adding route=$route to $ROUTE_TABLE_ID"
    # Add route to routetable here.
    aws ec2 create-transit-gateway-route --destination-cidr-block $route --region $REGION --transit-gateway-route-table-id $ROUTE_TABLE_ID --transit-gateway-attachment-id $ATTACHMENT_ID
  done

  # Now... the other side
  ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-peering-attachments --filter "Name=transit-gateway-id,Values=$PEERTGWID" "Name=state,Values=available" --region $PEERREGION --query "TransitGatewayPeeringAttachments[0].TransitGatewayAttachmentId" --output text)
  echo "ATTACHMENT_ID=$ATTACHMENT_ID"

  ROUTE_TABLE_ID=$(aws ec2 describe-transit-gateways --region $PEERREGION --transit-gateway-ids $PEERTGWID --query "TransitGateways[0].Options.PropagationDefaultRouteTableId" --output text)
  echo "ROUTE_TABLE_ID=$ROUTE_TABLE_ID"

  IFS=','
  read -ra routes <<< "$PEERROUTES"

  for route in "${routes[@]}"; do
    echo "Adding route=$route to $ROUTE_TABLE_ID"
    # Add route to routetable here.
    aws ec2 create-transit-gateway-route --destination-cidr-block $route --region $PEERREGION --transit-gateway-route-table-id $ROUTE_TABLE_ID --transit-gateway-attachment-id $ATTACHMENT_ID
  done
 
}

err() {
   echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

usage() {
  echo " Create a Transit Gateway Attachment for a VPC."
  echo " "
  echo " --name : The "Name" tag value of the TGW."
  echo " --routes : Comma delimited list of CIDRs to be reached via the TGW, such as: 192.168.1.0/24,172.31.0.0/16"
  echo " --region : Region (Optional)"
  echo " --peerroutes : Comma delimited list of CIDRs to be reached via the TGW, such as: 192.168.1.0/24,172.31.0.0/16"
  echo " --peerregion : Peer Region (Required - where the remote peer TGW resides)"
  echo " --help : This help."
  echo " "
  exit 1
}

validate_arguments() {
  
  if [[ -z "$NAME" ]]; then
    err "Missing required argumemts."
    usage
    exit 1
  fi

  if [[ -z "$PEERREGION" ]]; then
    err "Missing required argumemts."
    usage
    exit 1
  fi

  # if [[ -z "$ROUTES" ]]; then
  #   err "Missing required argumemts."
  #   usage
  #   exit 1
  # fi

}

main "$@"
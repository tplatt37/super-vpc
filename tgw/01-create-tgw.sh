#!/bin/bash

#
# Create a Transit Gateway (TGW) in some region
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

  validate_arguments

  # Which region? Display to user so they can double-check.
  # Our first preference is the --region argument, then AWS_DEFAULT_REGION, lastly just use that set in the profile.
  REGION=${REGION_ARG:-${AWS_DEFAULT_REGION:-$(aws configure get default.region)}}

  echo $REGION
  echo "TGW will be setup in $REGION..."

  PREFIX=$NAME
  echo "All stack names will be prefixed with $PREFIX..."

  STACK_NAME=$PREFIX-tgw
  aws cloudformation deploy --template-file tgw.yaml \
  --parameter-overrides Prefix=$NAME \
  --stack-name $STACK_NAME --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION
  aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"

  aws cloudformation wait stack-exists --stack-name $STACK_NAME --region $REGION
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --region $REGION --output text)
  if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
          err "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
          exit 1
  fi

  echo "$STACK_NAME is ready."
 
}

err() {
   echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

usage() {
  echo " Create a Transit Gateway."
  echo " "
  echo " --name : The "Name" tag value of the TGW."
  echo " --region : Region (Optional)"
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

}

main "$@"
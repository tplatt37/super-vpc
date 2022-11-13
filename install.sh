#!/bin/bash
#
# Setup an full-featured VPC - in a hands-free fashion!
#

if [ -z $1 ]; then
        echo "Must pass in a unique name that will also be used as a prefix to use for resource naming... Exiting..."
        exit 1
fi

# Which region? Display to user so they can double-check.
REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

echo $REGION
echo "VPC will be setup in $REGION..."

PREFIX=$1
echo "All stack names will be prefixed with $PREFIX..."

STACK_NAME=$PREFIX-logging
aws cloudformation deploy --template-file bucket.yaml \
 --parameter-overrides Prefix=$PREFIX \
 --stack-name $STACK_NAME --capabilities CAPABILITY_NAMED_IAM
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"

aws cloudformation wait stack-exists --stack-name $STACK_NAME
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi

echo "$STACK_NAME is ready."

STACK_NAME=$PREFIX-vpc
aws cloudformation deploy \
  --template-file vpc-multi-az.yaml \
  --parameter-overrides Prefix=$PREFIX UseThirdAZ=True UseWithRDS=True \
  --stack-name "$STACK_NAME"
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"
 
aws cloudformation wait stack-exists --stack-name $STACK_NAME
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi

echo "$STACK_NAME is ready."

echo "Done."
#!/bin/bash

#
# Super-VPC
# This uninstalls (DELETES!) everything.
#

if [ -z $1 ]; then
        echo "Must pass in the unique name that you wish to delete... Exiting..."
        exit 1
fi
PREFIX=$1

REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# NOTE: if you invoke with --yes (must be after the prefix name) it will skip these "Are you sure?" prompts
if [[ $2 != "--yes" ]]; then
    read -p "This will delete $PREFIX in $REGION and all associated resources. Are you sure? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
    
    read -p "Have you deleted any LOAD BALANCERS or INGRESS before proceeding? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
    
    read -p "Did you run ./unpeer.sh to remove any VPC Peering you created with ./peer.sh? If you didn't run peer.sh, enter Y. (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "For a clean un-install, you should run ./unpeer.sh CLUSTERNAME before deleting..."
        exit 1
    fi

fi

if [[ $2 != "--yes" ]]; then
    read -p "About to start deleting. Are you sure you are sure???? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
fi

echo "OK... here we go..."

# Are there ENIs other than the NAT Gateways and Interface Endpoints?
# If so, you probably need to get rid of those resources first...
# This is not definitive, but it's better than nothing.

VPCID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-VpcId'].Value" --output text)
echo "VPCID=$VPCID"

if [[ $VPCID == "" ]]; then
    echo "Could not find Stack related to $PREFIX ($REGION) - please double check PREFIX and Region."
    exit 0
fi


# TODO - Count up interfaces - warn the user.
#aws ec2 describe-network-interfaces --filter Name=vpc-id,Values=$VPCID
#
ENI_COUNT=$(aws ec2 describe-network-interfaces --filter Name=vpc-id,Values=$VPCID --query "NetworkInterfaces[*].Description" | grep "\"\"" | wc -l)

if [[ $ENI_COUNT > 0 ]]; then
    
    echo "It appears there are $ENI_COUNT ENI(s) in this VPC that need to be handled before uninstalling..."
    aws ec2 describe-network-interfaces --filter Name=vpc-id,Values=$VPCID --query "NetworkInterfaces[*].[Description, InterfaceType]" 
    echo "Uninstall canceled..."
    exit 1
    
fi


# Disable Flow Logs first, so we stop putting things in the S3 bucket 
FLOW_LOG_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-FlowLogId'].Value" --output text)
echo "FLOW_LOG_ID=$FLOW_LOG_ID"
aws ec2 delete-flow-logs --flow-log-ids $FLOW_LOG_ID

# Get the artifacts bucket from the Logging stack
BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-VPCLoggingBucket'].Value" --output text)
echo "BUCKET=$BUCKET"

# Empty the utility bucket (Otherwise stack delete will fail)
echo "Will empty bucket $BUCKET - to prevent stack delete from failing..."
aws s3 rm s3://$BUCKET --recursive

# For the Athena, we have to do a forced delete.
WORKGROUP=$(aws athena list-work-groups --query "WorkGroups[?Description=='This workgroup has the queries related to vpc flow logs.'].Name" --output text)
echo "WORKGROUP=$WORKGROUP"

if [[ $WORKGROUP != "" ]]; then
    # This is like a force delete. Otherwise the CFN stack delete will fail...
    aws athena delete-work-group --work-group $WORKGROUP --recursive-delete-option
    sleep 10
fi

# Athena stack may not exist - that's OK
STACK_NAME=$PREFIX-athena-query
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

#
# Remove all Ingress and Egress rules from the EC2SecurityGroup for a CLEAN uninstall.
#

./revoke-group-ingress.sh $PREFIX


STACK_NAME=$PREFIX-vpc
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

STACK_NAME=$PREFIX-logging
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME 

exit 0
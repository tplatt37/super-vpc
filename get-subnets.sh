#!/bin/bash

#
# Return a comma delimited list of 1, 2, or 3 subnets (private or public)
# Example:
# ./get-subnets.sh "a-new-startup" "public" "2"
# OR
# ./get-subnets.sh "a-new-startup" "private" "3"
#
# This works by using super-vpc's custom AWS tags
#

if [ -z $1 ]; then
        echo "Must pass in the naming prefix ... Exiting..."
        exit 1
fi
PREFIX=$1

if [ -z $2 ]; then
        echo "Must pass in the subnet_type - public or private... Exiting..."
        exit 1
fi
SUBNET_TYPE=$2

if [ -z $3 ]; then
        echo "Also need a to know how many you want (1,2, or 3?) ... Exiting..."
        exit 0
fi
SUBNET_COUNT=$3

REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

VPCID=$(./get-vpcid.sh $PREFIX)

SUBNETS=$(aws ec2 describe-subnets \
    --filter "Name=vpc-id,Values=$VPCID" \
    "Name=tag:subnet_type,Values=$SUBNET_TYPE" \
    --query "Subnets[*].SubnetId" \
    --output text)

#
# This turns on string into multiple lines, we head the amount we want, then turn it into a comma delimited list with no trailing comma.
#
echo $SUBNETS | tr -s '[:blank:]' '\n' | head -n $SUBNET_COUNT | tr '\n' ',' | sed 's/,$/\n/'

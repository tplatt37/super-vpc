#!/bin/bash

#
# Returns the VpcId of the VPC created via super-vpc or ("")
# You must pass in the naming prefix.
#

if [ -z $1 ]; then
        echo "Must pass in the unique naming prefix... Exiting..."
        exit 1
fi
PREFIX=$1

REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# We pull the VPCID from the Stack Export.
VPCID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-VpcId'].Value" --output text)
echo "$VPCID"

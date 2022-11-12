#!/bin/bash
# Creates a VPC for use with the databases.
# This creates 3 AZs - so you can use a Multi-AZ Cluster

./95-check-prereqs.sh
if [[ $? -ne 0 ]]; then
    echo "Missing prerequisites... exiting..."
    exit 1
fi

PREFIX="database"

REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}
echo "Creating in $REGION..."

echo "Setting up VPC..."
# NOTE: We're using 3 AZs, but this template also supports 2 (see parameter).
aws cloudformation deploy --template-file vpc-multi-az.yaml --parameter-overrides UseThirdAZ=True --stack-name $PREFIX-vpc

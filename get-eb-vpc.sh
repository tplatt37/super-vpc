#!/bin/bash

#
# Creates a vpc.config file that can be used with Elastic Beanstalk.
# Ref: https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.managing.vpc.html
# Example:
# ./get-subnets.sh "demo" "2"
#
# 

if [ -z $1 ]; then
        echo "Must pass in the naming prefix ... Exiting..."
        exit 1
fi
PREFIX=$1

if [ -z $2 ]; then
        echo "Also need a to know how many you want (1,2, or 3?) ... Exiting..."
        exit 0
fi
SUBNET_COUNT=$2

if [ -z $3 ]; then
        echo "Must pass an output path ... Exiting..."
        exit 0
fi
OUTPUT_FILE=$3

REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# We pull the VPCID from the Stack Export.
VPCID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-VpcId'].Value" --output text)
echo "$VPCID"

echo "VPCID=$VPCID"

#
# NOTE: This only works because super-vpc puts a convenient "subnet_type" tag on each subnet (public/private)
# This is NOT standard AWS behavior!
#
SUBNET_TYPE="public"
PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
    --filter "Name=vpc-id,Values=$VPCID" \
    "Name=tag:subnet_type,Values=$SUBNET_TYPE" \
    --query "Subnets[*].SubnetId" \
    --output text)

echo "PUBLIC_SUBNETS=$PUBLIC_SUBNETS"

SUBNET_TYPE="private"
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filter "Name=vpc-id,Values=$VPCID" \
    "Name=tag:subnet_type,Values=$SUBNET_TYPE" \
    --query "Subnets[*].SubnetId" \
    --output text)

echo "PRIVATE_SUBNETS=$PRIVATE_SUBNETS"

#
# This turns a string into multiple lines, we head the amount we want, then turn it into a comma delimited list with no trailing comma.
#
FINAL_PUBLIC=$(echo $PUBLIC_SUBNETS | tr -s '[:blank:]' '\n' | head -n $SUBNET_COUNT | tr '\n' ',' | sed 's/,$/\n/')
FINAL_PRIVATE=$(echo $PRIVATE_SUBNETS | tr -s '[:blank:]' '\n' | head -n $SUBNET_COUNT | tr '\n' ',' | sed 's/,$/\n/')


cat<<EoF > vpc.config
option_settings:
   aws:ec2:vpc:
      VPCId: $VPCID
      AssociatePublicIpAddress: 'false'
      ELBScheme: public
      ELBSubnets: $FINAL_PUBLIC
      Subnets: $FINAL_PRIVATE
EoF

cp vpc.config $OUTPUT_FILE

cat $OUTPUT_FILE

echo "Done..."
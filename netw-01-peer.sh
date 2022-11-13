#!/bin/bash
# Run this on a Cloud9 or EC2 instance to get Peered to the VPC Super-VPC 
# This is idempotent.  Run it as many times as you like, anything already existing won't be created a second time.
# (Although you'll probably see error messages the second time through!)

if [ -z $1 ]; then
        echo "Must pass in the unique Prefix Name that was used as a prefix for resource naming... Exiting..."
        exit 1
fi
PREFIX=$1

if [ -z $2 ]; then
        echo "Must pass in the C9_REGION - where the Cloud9 or EC2 instance resides... Exiting..."
        exit 1
fi
C9_REGION=$2

if [ -z $3 ]; then
        echo "Must pass in the C9_VPC_ID - of the Cloud9 or EC2 instance... Exiting..."
        exit 1
fi
C9_VPC_ID=$3

if [ -z $4 ]; then
        echo "Must pass in the TARGET_REGION - where the Target Resource resides... Exiting..."
        exit 1
fi
TARGET_REGION=$4

if [ -z $5 ]; then
        echo "Must pass in the TARGET_VPC_ID - where the Target Resource resides... Exiting..."
        exit 1
fi
TARGET_VPC_ID=$5

echo "Checking for Cloud9/EC2 Instance $INSTANCE_ID in Region $C9_REGION"


#PRIVATE_IP_ADDRESS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PrivateIpAddress" --output text --region $C9_REGION)
#echo "PRIVATE_IP_ADDRESS=$PRIVATE_IP_ADDRESS"


TARGET_VPC_CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $TARGET_VPC_ID --query ["Vpcs[*].CidrBlock"] --output text)
echo "TARGET_VPC_CIDR_BLOCK=$TARGET_VPC_CIDR_BLOCK"

# Peering from the VPC / REGION Cloud9 is in to the VPC / REGION that the databases are in.
# NOTE: Big assumption that you have your AWS CLI pointed to the REGION with the TARGET VPC!
#
PEERING_ID=$(aws ec2 create-vpc-peering-connection --region $C9_REGION --vpc-id $C9_VPC_ID --peer-vpc-id $TARGET_VPC_ID --peer-region $TARGET_REGION --output text --query "VpcPeeringConnection.VpcPeeringConnectionId")
echo "PEERING_ID=$PEERING_ID"

# Give it just a moment before waiting for it...
sleep 5

echo "Gonna wait for the VPC peering connection to come into existence..."
aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-id $PEERING_ID --region $C9_REGION

echo "Accepting VPC Peering connection..."
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PEERING_ID --region $TARGET_REGION

echo "Sleep 30 seconds, wait for VPC peering to be Active..."
sleep 30

echo "Modifying VPC Peering Connection to allow DNS Name Resolution ... both ways."
aws ec2 modify-vpc-peering-connection-options --requester-peering-connection-options AllowDnsResolutionFromRemoteVpc=true --vpc-peering-connection-id $PEERING_ID --region $C9_REGION 
aws ec2 modify-vpc-peering-connection-options --accepter-peering-connection-options AllowDnsResolutionFromRemoteVpc=true --vpc-peering-connection-id $PEERING_ID --region $TARGET_REGION 

exit 0
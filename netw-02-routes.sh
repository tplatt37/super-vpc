#!/bin/bash

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

if [ -z $6 ]; then
        echo "Must pass in the INSTANCE_ID ... Exiting..."
        exit 1
fi
INSTANCE_ID=$6

if [ -z $7 ]; then
        echo "Must pass in the PEERING_ID - of the peering connection... Exiting..."
        exit 1
fi
PEERING_ID=$7

echo "PEERING_ID=$PEERING_ID"
echo "INSTANCE_ID=$INSTANCE_ID"

TARGET_VPC_CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $TARGET_VPC_ID --query ["Vpcs[*].CidrBlock"] --output text)
echo "TARGET_VPC_CIDR_BLOCK=$TARGET_VPC_CIDR_BLOCK"

# TODO - don't think this is needed here.
#PRIVATE_IP_ADDRESS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PrivateIpAddress" --output text --region $C9_REGION)
#echo "PRIVATE_IP_ADDRESS for the Cloud9 instance is $PRIVATE_IP_ADDRESS."

#
# Find the Route Table of the Cloud9/EC2 instance.
# We'll need to add routes so it can reach the peered VPC!
#

C9_SUBNET_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].SubnetId" --output text --region $C9_REGION)
echo "SUBNET_ID=$C9_SUBNET_ID"

C9_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $C9_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$C9_SUBNET_ID'].RouteTableId")
echo "C9_ROUTE_TABLE_ID=$C9_ROUTE_TABLE_ID."

if [[ $C9_ROUTE_TABLE_ID -eq "" ]]; then
    # If no route table listed, assume IMPLICIT Associaton to the main route table.
    echo "C9 Must be using the Main Route Table! (Implicit Association)"
    # Must combine both server side --filter and client side --query to get the Main route table
    C9_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $C9_REGION --output text --query "RouteTables[?VpcId=='$C9_VPC_ID'].RouteTableId" --filters "Name=association.main,Values=true" )
    echo "C9_ROUTE_TABLE_ID=$C9_ROUTE_TABLE_ID"

fi

# We need to add a Route to the CIDR of the Cloud9 VPC, pointing to the peering connection

C9_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $C9_SUBNET_ID --region $C9_REGION --output text --query "Subnets[0].CidrBlock")
echo "C9_CIDR_BLOCK (Subnet)=$C9_CIDR_BLOCK"

C9_VPC_CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $C9_VPC_ID --region $C9_REGION --query ["Vpcs[*].CidrBlock"] --output text)
echo "C9_VPC_CIDR_BLOCK (VP)=$C9_VPC_CIDR_BLOCK"

#
# Now we need to update the Route Tables.
# There's ONE route table for the Cloud9 instance (which resides in one subnet - of course)
#
# There's up to 4 Route Tables on the TARGET VPC side.
# There are either 2 or 3 Private Route Tables, and 1 Public Route Table.
#

#
# Cloud9 Subnet
#

# Add 1 Route Table entry so the single Cloud9 Subnet can reach all of the Private Subnets.
aws ec2 create-route --region $C9_REGION \
    --route-table-id $C9_ROUTE_TABLE_ID \
    --vpc-peering-connection-id $PEERING_ID \
    --destination-cidr-block $TARGET_VPC_CIDR_BLOCK 

#
# Public Subnets - there's only 1 route table for the public subnets
#

echo "PUBLIC SUBNETS"

# We grab the first subnet, as it uses the same route table as all of them.
TARGET_SUBNET_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PublicSubnetId01'].Value" --output text)
echo "TARGET_SUBNET_ID=$TARGET_SUBNET_ID"

RT_PUBLIC=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID'].RouteTableId")
echo "RT_PUBLIC=$RT_PUBLIC"

# Add a Route Table Entries so this Private Subnet can reach the Cloud9 VPC
aws ec2 create-route --region $TARGET_REGION \
    --route-table-id $RT_PUBLIC \
    --vpc-peering-connection-id $PEERING_ID \
    --destination-cidr-block $C9_CIDR_BLOCK 

#
# Private Subnet 01
# 

echo "PRIVATE SUBNET 01"

TARGET_SUBNET_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId01'].Value" --output text)
echo "TARGET_SUBNET_ID=$TARGET_SUBNET_ID"

RT_PRIVATE=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID'].RouteTableId")
echo "RT_PRIVATE=$RT_PRIVATE"

# Add a Route Table Entries so this Private Subnet can reach the Cloud9 VPC
aws ec2 create-route --region $TARGET_REGION \
    --route-table-id $RT_PRIVATE \
    --vpc-peering-connection-id $PEERING_ID \
    --destination-cidr-block $C9_CIDR_BLOCK 

#
# Private Subnet 02
#

echo "PRIVATE SUBNET 02"

TARGET_SUBNET_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId02'].Value" --output text)
echo "TARGET_SUBNET_ID=$TARGET_SUBNET_ID"

RT_PRIVATE=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID'].RouteTableId")
echo "RT_PRIVATE=$RT_PRIVATE"

# Add a Route Table Entries so this Private Subnet can reach the Cloud9 VPC
aws ec2 create-route --region $TARGET_REGION \
    --route-table-id $RT_PRIVATE \
    --vpc-peering-connection-id $PEERING_ID \
    --destination-cidr-block $C9_CIDR_BLOCK 

#
# OPTIONAL Third Subnet (Private)
#
# This subnet is optional and will only be present if you overrode the UseThirdAZ parameter in the VPC stack.
#

echo "Checking to see if a 3rd private subnet was created..."
TARGET_SUBNET_ID_3=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId03'].Value" --output text)
echo "TARGET_SUBNET_ID_3=$TARGET_SUBNET_ID_3."

if [[ $TARGET_SUBNET_ID_3 != "" ]]; then

    echo "PRIVATE SUBNET 03"
    
    RT_PRIVATE=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID_3'].RouteTableId")
    echo "RT_PRIVATE=$RT_PRIVATE"
    
    # Add a Route Table Entries so this Private Subnet can reach the Cloud9 VPC
    aws ec2 create-route --region $TARGET_REGION \
        --route-table-id $RT_PRIVATE \
        --vpc-peering-connection-id $PEERING_ID \
        --destination-cidr-block $C9_CIDR_BLOCK 
       
else
    echo "3rd private subnet not found... and that's OK."
fi
    
echo "Done."
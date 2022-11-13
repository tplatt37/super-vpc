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
TARGET_VPC_ID=$6

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

#PRIVATE_IP_ADDRESS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PrivateIpAddress" --output text --region $C9_REGION)
#echo "PRIVATE_IP_ADDRESS for the Cloud9 instance is $PRIVATE_IP_ADDRESS."

C9_SUBNET_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].SubnetId" --output text --region $C9_REGION)
echo "SUBNET_ID=$C9_SUBNET_ID"

C9_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $C9_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$C9_SUBNET_ID'].RouteTableId")
echo "C9_ROUTE_TABLE_ID=$C9_ROUTE_TABLE_ID."

if [[ $C9_ROUTE_TABLE_ID -eq "" ]]; then
    # If not route table listed, assume IMPLICIT Associaton to the main route table.
    echo "C9 Must be using the Main Route Table! (Implicit Association)"
    # Must combine both server side --filter and client side --query to get the Main route table
    C9_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $C9_REGION --output text --query "RouteTables[?VpcId=='$C9_VPC_ID'].RouteTableId" --filters "Name=association.main,Values=true" )
    echo "C9_ROUTE_TABLE_ID=$C9_ROUTE_TABLE_ID"

fi

# We need to add a Route to the CIDR of the remote VPC, pointing to the peering connection

C9_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $C9_SUBNET_ID --region $C9_REGION --output text --query "Subnets[0].CidrBlock")
echo "C9_CIDR_BLOCK (Subnet)=$C9_CIDR_BLOCK"

C9_VPC_CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $C9_VPC_ID --region $C9_REGION --query ["Vpcs[*].CidrBlock"] --output text)
echo "C9_VPC_CIDR_BLOCK (VP)=$C9_VPC_CIDR_BLOCK"

exit


# Deal with the destination route tables first.

#
# Subnet 01
# 

TARGET_SUBNET_ID_1=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId01'].Value" --output text)
echo "TARGET_SUBNET_ID_1=$TARGET_SUBNET_ID_1"

TARGET_SUBNET_CIDR_BLOCK_1=$(aws ec2 describe-subnets --subnet-ids $TARGET_SUBNET_ID_1 --region $REGION --output text --query "Subnets[0].CidrBlock")
echo "TARGET_SUBNET_CIDR_BLOCK_1=$TARGET_SUBNET_CIDR_BLOCK_1"

ROUTE_TABLE_ID_1=$(aws ec2 describe-route-tables --region $REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID_1'].RouteTableId")
echo "ROUTE_TABLE_ID_1=$ROUTE_TABLE_ID_1"

#
# Subnet 02
#

TARGET_SUBNET_ID_2=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId02'].Value" --output text)
echo "TARGET_SUBNET_ID_2=$TARGET_SUBNET_ID_2"

TARGET_SUBNET_CIDR_BLOCK_2=$(aws ec2 describe-subnets --subnet-ids $TARGET_SUBNET_ID_2 --region $REGION --output text --query "Subnets[0].CidrBlock")
echo "TARGET_SUBNET_CIDR_BLOCK_2=$TARGET_SUBNET_CIDR_BLOCK_2"

ROUTE_TABLE_ID_2=$(aws ec2 describe-route-tables --region $REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID_2'].RouteTableId")
echo "ROUTE_TABLE_ID_2=$ROUTE_TABLE_ID_2"

# TODO Public Subnets? 
# TODO Subnet 3 ?


# Add 1 Route Table entries so Cloud9 can reach all of the Private Subnets.
aws ec2 create-route --region $C9_REGION \
    --route-table-id $C9_ROUTE_TABLE_ID \
    --vpc-peering-connection-id $PEERING_ID \
    --destination-cidr-block $TARGET_VPC_CIDR_BLOCK \
    > /dev/null

# Add 2 Route Table Entries so the Private Subnets can reach Cloud9    
aws ec2 create-route --region $REGION \
    --route-table-id $ROUTE_TABLE_ID_1 \
    --vpc-peering-connection-id $PEERING_ID \
    --destination-cidr-block $C9_CIDR_BLOCK \
    > /dev/null
    
aws ec2 create-route --region $REGION \
    --route-table-id $ROUTE_TABLE_ID_2 \
    --vpc-peering-connection-id $PEERING_ID \
    --destination-cidr-block $C9_CIDR_BLOCK \
    > /dev/null


#
# Subnet 03
#
# This subnet is optional and will only be present if you overrode the UseThirdAZ parameter in the VPC stack.
#

echo "Checking to see if a 3rd private subnet was created..."
TARGET_SUBNET_ID_3=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId03'].Value" --output text)
echo "TARGET_SUBNET_ID_3=$TARGET_SUBNET_ID_3."

if [[ $TARGET_SUBNET_ID_3 != "" ]]; then

    TARGET_SUBNET_CIDR_BLOCK_3=$(aws ec2 describe-subnets --subnet-ids $TARGET_SUBNET_ID_3 --region $REGION --output text --query "Subnets[0].CidrBlock")
    echo "TARGET_SUBNET_CIDR_BLOCK_3=$TARGET_SUBNET_CIDR_BLOCK_3"
    
    ROUTE_TABLE_ID_3=$(aws ec2 describe-route-tables --region $REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID_3'].RouteTableId")
    echo "ROUTE_TABLE_ID_3=$ROUTE_TABLE_ID_3"
        
    aws ec2 create-route --region $REGION \
        --route-table-id $ROUTE_TABLE_ID_3 \
        --vpc-peering-connection-id $PEERING_ID \
        --destination-cidr-block $C9_CIDR_BLOCK \
        > /dev/null
        
    # TODO - Also PUBLIC SUBNET
    
else
    echo "3rd private subnet not found... that's OK."
fi
    
./groups.sh 

echo "Done."
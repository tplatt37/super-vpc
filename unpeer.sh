#!/bin/bash
# Run this on a Cloud9 instance to get UN-Peered to the VPC the Target Resource is in.
#
# This basically UNDOES what peer.sh deos.
#
# Removes the Routing Table entries that were added for peering (from both sides)
# TODO: Removes the EC2 Security Group ingress rules that were added to allow traffic from C9
# Removes the Peering Connection.
#

if [ -z $1 ]; then
        echo "Must pass in the unique PREFIX that was used for resource naming... Exiting..."
        exit 1
fi
PREFIX=$1

# This is the REGION where the VPC is.
TARGET_REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# IMPORTANT
# REGION is the REGION the Databases are in
# C9_REGION is the REGION that the EC2 / C9 Instance is in.
#
#

# OPTIONAL: You can provide the EC2 INSTANCE_ID that you want to be able to use to connect to the databases.
# It's easier if you just run this command from the C9/EC2 instance...
# If you pass in an INSTANCE_ID you also need to pass in the REGION.

if [ -z $2 ]; then
    read -p "Are you running this on the Cloud9 or EC2 instance that you wish to UNPEER? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "Well... I need you to give me the INSTANCE ID and REGION as parameters, please!"
        exit 1
    fi
    
    # Get the Instance ID via IMDSv2
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    echo "INSTANCE_ID=$INSTANCE_ID."
    
    # Must figure out which REGION this Cloud9 instance is in.
    EC2_AVAIL_ZONE=`curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone`
    if [[ -z $EC2_AVAIL_ZONE ]]; then
            echo "Could not access Instance Meta Data Service (IMDS). Exiting..."
            exit 2
    fi
    C9_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

else
    INSTANCE_ID=$2
    
    if [ -z $3 ]; then
        echo "Need to know the REGION for the instance ID $INSTANCE_ID..."
        exit 2
    fi
    
    C9_REGION=$3
    
fi

echo "Checking for Cloud9 Instance $INSTANCE_ID in Region $C9_REGION"

C9_VPC_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].VpcId" --output text --region $C9_REGION)
echo "C9_VPC_ID=$C9_VPC_ID"

TARGET_VPC_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-VpcId'].Value" --output text)
echo "TARGET_VPC_ID=$TARGET_VPC_ID"

# Need this when removing specific routes.
TARGET_VPC_CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $TARGET_VPC_ID --query ["Vpcs[*].CidrBlock"] --output text)
echo "TARGET_VPC_CIDR_BLOCK=$TARGET_VPC_CIDR_BLOCK"

# NOTE: We're using server side --filter to make sure we find the proper ACTIVE peering connection between the two VPCs.
# See: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-vpc-peering-connections.html (--filters)
PEERING_ID=$(aws ec2 describe-vpc-peering-connections --filters "Name=accepter-vpc-info.vpc-id,Values=$C9_VPC_ID" "Name=requester-vpc-info.vpc-id,Values=$TARGET_VPC_ID" "Name=status-code,Values=active" --query "VpcPeeringConnections[*].VpcPeeringConnectionId" --output text --region $TARGET_REGION)
echo "PEERING_ID=$PEERING_ID"

echo "Deleting Route in the Cloud9 Subnet Route table"

C9_VPC_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].VpcId" --output text --region $C9_REGION)
echo "VPC_ID for the Cloud9 instance is $C9_VPC_ID."

C9_SUBNET_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].SubnetId" --output text --region $C9_REGION)
echo "SUBNET_ID=$C9_SUBNET_ID"

C9_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $C9_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$C9_SUBNET_ID'].RouteTableId")
echo "C9_ROUTE_TABLE_ID=$C9_ROUTE_TABLE_ID."

if [[ $C9_ROUTE_TABLE_ID -eq "" ]]; then
    # If no route table listed, assume IMPLICIT Associaton to the main route table.
    echo "C9 Must be using the Main Route Table! (Implicit Association)"
    # Based off this : https://stackoverflow.com/questions/66599866/aws-api-how-to-get-main-route-table-id-by-subnet-id-association-subnet-id-fil
    # Must combine both server side --filter and client side --query to get the Main route table
    # I have NOT tested this extensively...
    C9_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $C9_REGION --output text --query "RouteTables[?VpcId=='$C9_VPC_ID'].RouteTableId" --filters "Name=association.main,Values=true" )
    echo "C9_ROUTE_TABLE_ID=$C9_ROUTE_TABLE_ID"
fi

C9_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $C9_SUBNET_ID --region $C9_REGION --output text --query "Subnets[0].CidrBlock")
echo "C9_CIDR_BLOCK=$C9_CIDR_BLOCK"

# We need to remove the route from the C9 route table BEFORE we delete the Peering Connection.
aws ec2 delete-route \
    --route-table-id $C9_ROUTE_TABLE_ID \
    --destination-cidr-block $TARGET_VPC_CIDR_BLOCK \
    --region $C9_REGION

#
# Public Subnet Route
# 

TARGET_SUBNET_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PublicSubnetId01'].Value" --output text)
echo "TARGET_SUBNET_ID=$TARGET_SUBNET_ID"

TARGET_SUBNET_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $TARGET_SUBNET_ID --region $TARGET_REGION --output text --query "Subnets[0].CidrBlock")
echo "TARGET_SUBNET_CIDR_BLOCK=$TARGET_SUBNET_CIDR_BLOCK"

ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID'].RouteTableId")
echo "ROUTE_TABLE_ID=$ROUTE_TABLE_ID"

echo "Removing Route Table entry for Public Subnets (1 entry for all public subnets)..."
aws ec2 delete-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block $C9_CIDR_BLOCK


#
# Private Subnet 1
#

TARGET_SUBNET_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId01'].Value" --output text)
echo "TARGET_SUBNET_ID=$TARGET_SUBNET_ID"

TARGET_SUBNET_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $TARGET_SUBNET_ID --region $TARGET_REGION --output text --query "Subnets[0].CidrBlock")
echo "TARGET_SUBNET_CIDR_BLOCK=$TARGET_SUBNET_CIDR_BLOCK"

ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID'].RouteTableId")
echo "ROUTE_TABLE_ID=$ROUTE_TABLE_ID"

echo "Removing Route Table entry for Private Subnets (1 of possibly 3)..."
aws ec2 delete-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block $C9_CIDR_BLOCK

#
# Private Subnet 2
#

TARGET_SUBNET_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId02'].Value" --output text)
echo "TARGET_SUBNET_ID=$TARGET_SUBNET_ID"

TARGET_SUBNET_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $TARGET_SUBNET_ID --region $TARGET_REGION --output text --query "Subnets[0].CidrBlock")
echo "TARGET_SUBNET_CIDR_BLOCK=$TARGET_SUBNET_CIDR_BLOCK"

ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID'].RouteTableId")
echo "ROUTE_TABLE_ID=$ROUTE_TABLE_ID"

echo "Removing Route Table entry for Private Subnets (2 of possibly 3)..."
aws ec2 delete-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block $C9_CIDR_BLOCK


#
# OPTIONAL PRIVATE Subnet 03
#
# This subnet is optional and will only be present if you overrode the UseThirdAZ parameter in the VPC stack.
#

echo "Checking to see if a 3rd private subnet was created..."
TARGET_SUBNET_ID_3=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-PrivateSubnetId03'].Value" --output text)
echo "TARGET_SUBNET_ID_3=$TARGET_SUBNET_ID_3."

if [[ $TARGET_SUBNET_ID_3 != "" ]]; then

    TARGET_SUBNET_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $TARGET_SUBNET_ID_3 --region $TARGET_REGION --output text --query "Subnets[0].CidrBlock")
    echo "TARGET_SUBNET_CIDR_BLOCK=$TARGET_SUBNET_CIDR_BLOCK"
    
    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $TARGET_REGION --output text --query "RouteTables[*].Associations[?SubnetId=='$TARGET_SUBNET_ID_3'].RouteTableId")
    echo "ROUTE_TABLE_ID=$ROUTE_TABLE_ID"
    
    echo "Removing Route Table entry for Private Subnets (3 of 3)..."
    aws ec2 delete-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block $C9_CIDR_BLOCK

fi

# The LAST thing we do is remove the Peering Connection...
echo "Removing Peering connection ($PEERING_ID $TARGET_REGION)..."
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PEERING_ID --region $TARGET_REGION

#
#
# NOTE: We DO NOT remove the EC2SecurityGroup ingress rules here. 
# We have to do that in a brute force way - so we'll clean those up on VPC uninstall
# (If you add manual ingress and egress rules - it'll be hard to figure out which is which)
#
#
#


echo "Done."


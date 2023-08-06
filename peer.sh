#!/bin/bash
# Run this on a Cloud9 or EC2 instance to get Peered to the VPC create by Super-VPC 
# This is idempotent.  Run it as many times as you like, anything already existing won't be created a second time.
# (Although you'll probably see error messages the second time through!)
# Both VPCs must be in same account, but can be in different regions.
#

if [ -z $1 ]; then
        echo "Must pass in the unique Prefix Name that was used as a prefix for resource naming... Exiting..."
        exit 1
fi

PREFIX=$1

# The TARGET_REGION is where the Target Resource (VPC) is.
TARGET_REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# OPTIONAL: You can provide the EC2 INSTANCE_ID that you want to be able to use to connect to the databases.
# It's easier if you just run this command from the C9/EC2 instance...
# If you pass in an INSTANCE_ID you also need to pass in the REGION.
#
if [ -z $2 ]; then
    read -p "Are you running this on the Cloud9 or EC2 instance that you wish to use for demos? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "Well... you need to give me the INSTANCE ID and REGION of the instance as input parameters!"
        exit 1
    fi
    
    # Get the Instance ID via IMDS
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    
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

# The VPC the Cloud9/EC2 instance is in.
C9_VPC_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].VpcId" --output text --region $C9_REGION)

# NOTE: Big assumption here that you created the VPC with super-vpc and we are getting the ID via Export
TARGET_VPC_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-VpcId'].Value" --output text)

echo "PREFIX=$PREFIX"
echo "C9_REGION=$C9_REGION"
echo "C9_VPC_ID=$C9_VPC_ID"
echo "TARGET_REGION=$TARGET_REGION"
echo "TARGET_VPC_ID=$TARGET_VPC_ID"

# This will create, tag, and accept the VPC Peering Connection
./netw-01-peer.sh $PREFIX $C9_REGION $C9_VPC_ID $TARGET_REGION $TARGET_VPC_ID

# Find the Peering Connection that was just created and accepted.
PEERING_ID=$(aws ec2 describe-vpc-peering-connections --region $TARGET_REGION \
--filters "Name=accepter-vpc-info.vpc-id,Values=$C9_VPC_ID" "Name=requester-vpc-info.vpc-id,Values=$TARGET_VPC_ID" \
--output text --query "VpcPeeringConnections[0].VpcPeeringConnectionId")
echo "INSTANCE_ID=$INSTANCE_ID"
echo "PEERING_ID=$PEERING_ID"

# We need routes to enable the two VPCs to talk back and forth.
./netw-02-routes.sh $PREFIX $C9_REGION $C9_VPC_ID $TARGET_REGION $TARGET_VPC_ID $INSTANCE_ID $PEERING_ID

exit 0
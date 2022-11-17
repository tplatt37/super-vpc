#!/bin/bash

# Add inbound rules to the pre-existing Security Group (EC2SecurityGroup)
#
# Parameters:
# Ports (Destination)
#

if [ -z $1 ]; then
        echo "Must pass in the unique PREFIX that was used for resource naming... Exiting..."
        exit 1
fi
PREFIX=$1

if [ -z $2 ]; then
        echo "Must pass in a comma delimited list of TCP Ports to open - such as: 22,80,443 Exiting..."
        exit 1
fi
TCP_PORTS=$2

# This is the TARGET_REGION where the Security Group and VPC is.
TARGET_REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# We have to modify the rules on the Security Group created in the VPC Stack.
SECURITY_GROUP=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-EC2SecurityGroup'].Value" --output text)
echo "SECURITY_GROUP=$SECURITY_GROUP"

if [[ $SECURITY_GROUP == "" ]]; then
    echo "Couldn't find Security Group for $PREFIX ($TARGET_REGION). Please double-check and try again."
    exit 404
fi


# OPTIONAL: You can provide the EC2 INSTANCE_ID that you want to be able to use to connect to the databases.
# It's easier if you just run this command from the C9/EC2 instance...
# If you pass in an INSTANCE_ID you also need to pass in the REGION.

if [ -z $3 ]; then
    read -p "Are you running this on the Cloud9 or EC2 instance that you will use to connect (the source)? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "Well... I need you to give me the INSTANCE ID and REGION as parameters, please!"
        exit 1
    fi
    
    # Get the Instance ID via IMDS
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    echo "INSTANCE_ID=$INSTANCE_ID."
    
    # Must figure out which REGION this Cloud9 instance is in.
    EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
    if [[ -z $EC2_AVAIL_ZONE ]]; then
            echo "Could not access Instance Meta Data Service (IMDS). Exiting..."
            exit 2
    fi
    C9_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

else
    INSTANCE_ID=$3
    
    if [ -z $4 ]; then
        echo "Need to know the REGION for the instance ID $INSTANCE_ID..."
        exit 2
    fi
    
    C9_REGION=$4
    
fi

#
# We need to figure out the SOURCE of the traffic.
# We'll use the Cloud9/EC2 instance's CIDR Block (of the subnet)
# We could just use the IP? 
#

echo "Checking for Cloud9 Instance $INSTANCE_ID in Region $C9_REGION"

C9_VPC_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].VpcId" --output text --region $C9_REGION)
echo "C9_VPC_ID=$C9_VPC_ID"

C9_SUBNET_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].SubnetId" --output text --region $C9_REGION)
echo "C9_SUBNET_ID=$C9_SUBNET_ID"

C9_CIDR_BLOCK=$(aws ec2 describe-subnets --subnet-ids $C9_SUBNET_ID --region $C9_REGION --output text --query "Subnets[0].CidrBlock")
echo "C9_CIDR_BLOCK=$C9_CIDR_BLOCK"

#
#
# Loop through a list of TCP Ports (comma delimited), such as:
# 22,80,443,3000
#
# TODO: Port Ranges like (30000-32767). We do not (YET) support port range on the port list
# TODO: Protocols other than tcp (udp, icmp)
#

ARRAY=($(echo "$TCP_PORTS" | tr ',' '\n'))
for P in "${ARRAY[@]}"
do
    echo "TCP PORT: $P ..."

    aws ec2 authorize-security-group-ingress \
    --region $TARGET_REGION \
    --group-id $SECURITY_GROUP \
    --protocol tcp \
    --port $P \
    --cidr $C9_CIDR_BLOCK

done

echo "Done."
exit 0
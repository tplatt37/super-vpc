#!/bin/bash

# Add an inbound rule to a pre-exising Security Group.
#
# Parameters:
# TARGET_REGION
# SecurityGroupId
# Ports (Destination)
# C9_CIDR_BLOCK (source)
#


# We have to modify the rules on a security group created by eksctl.
TARGET_SECURITY_GROUP=$(aws cloudformation describe-stacks --stack-name "eksctl-$PREFIX-cluster" --query "Stacks[0].Outputs[?OutputKey=='ClusterSecurityGroupId'].OutputValue" --output text)
echo "TARGET_SECURITY_GROUP=$TARGET_SECURITY_GROUP"

aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $TARGET_SECURITY_GROUP \
    --protocol tcp \
    --port 22 \
    --cidr $C9_CIDR_BLOCK
    
aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $TARGET_SECURITY_GROUP \
    --protocol tcp \
    --port 80 \
    --cidr $C9_CIDR_BLOCK

aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $TARGET_SECURITY_GROUP \
    --protocol tcp \
    --port 443 \
    --cidr $C9_CIDR_BLOCK

aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $TARGET_SECURITY_GROUP \
    --protocol tcp \
    --port 3000 \
    --cidr $C9_CIDR_BLOCK

aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $TARGET_SECURITY_GROUP \
    --protocol tcp \
    --port 8080 \
    --cidr $C9_CIDR_BLOCK

aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $TARGET_SECURITY_GROUP \
    --ip-permissions IpProtocol=tcp,FromPort=30000,ToPort=32767,IpRanges="[{CidrIp=$C9_CIDR_BLOCK,Description='Access to NodePort range'}]" 

echo "Done."
#!/bin/bash
#

#
# REMOVE/REVOKE ALL inbound rules on the pre-existing Security Group (EC2SecurityGroup)
#
# We do this so the Stack deletion doesn't fail.
#


if [ -z $1 ]; then
        echo "Must pass in the unique PREFIX that was used for resource naming... Exiting..."
        exit 1
fi
PREFIX=$1

# This is the TARGET_REGION where the Security Group and VPC is.
TARGET_REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# We have to modify the rules on the Security Group created in the VPC Stack.
SECURITY_GROUP=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-EC2SecurityGroup'].Value" --output text)
echo "SECURITY_GROUP=$SECURITY_GROUP"

if [[ $SECURITY_GROUP == "" ]]; then
    echo "Couldn't find Security Group for $PREFIX ($TARGET_REGION). Please double-check and try again."
    exit 404
fi

#
# We only delete ingress rules. There's a default egress rule - just leave it.
#

INGRESS_RULES=$(aws ec2 describe-security-group-rules \
 --filters "Name=group-id,Values=$SECURITY_GROUP" \
 --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' \
 --output text)
echo "INGRESS_RULES=$INGRESS_RULES"

ARRAY=($(echo $INGRESS_RULES | tr -s '[:blank:]' '\n'))
for R in "${ARRAY[@]}"
do
    echo "SG Rule: $R ..."

    aws ec2 revoke-security-group-ingress \
    --region $TARGET_REGION \
    --group-id $SECURITY_GROUP \
    --security-group-rule-ids $R
done

exit 0
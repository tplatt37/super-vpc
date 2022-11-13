#!/bin/bash

#
# After some VPC Logs have arrived, you can setup Athena querying easily
# Ref: https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-athena.html
#
#

if [ -z $1 ]; then
        echo "Must pass in a unique name that will also be used as a prefix to use for resource naming... Exiting..."
        exit 1
fi

# Which region? Display to user so they can double-check.
REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

echo $REGION
echo "Athena Query will be setup in $REGION..."

PREFIX=$1
echo "All stack names will be prefixed with $PREFIX..."

FLOW_LOG_ID=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-FlowLogId'].Value" --output text)
echo "FLOW_LOG_ID=$FLOW_LOG_ID."

# Get the artifacts bucket from the Logging stack
BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-VPCLoggingBucket'].Value" --output text)
echo "BUCKET=$BUCKET."

# Partition date for the current month - Gotta be from today to the end of the month.
FIRST=$(date +%Y-%m-%d)
LAST=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%Y-%m-%d)
TIME="T00:00:00"

# Make config file using our S3 bucket and the VPC Flow Log ID
# NOTE: You do NOT want a trailing slash in the ConfigDeliveryS3DestinationArn!
cat <<EoF >athena-query-config.json
{
    "FlowLogId": "$FLOW_LOG_ID",
    "ConfigDeliveryS3DestinationArn": "arn:aws:s3:::$BUCKET/athena-templates",
    "IntegrateServices": {
        "AthenaIntegrations": [
            {
                "IntegrationResultS3DestinationArn": "arn:aws:s3:::$BUCKET/athena-query-results/",
                "PartitionLoadFrequency": "monthly",
                "PartitionStartDate": "$FIRST$TIME",
                "PartitionEndDate": "$LAST$TIME"
            }
        ]
    }
}
EoF

# Make sure destination dir for the template is empty (in case we are running this a second time due to failure)
aws s3 rm s3://$BUCKET/athena-templates --recursive

# This creates a cloudformation template in the bucket / folder specified in the config file 
aws ec2 get-flow-logs-integration-template --cli-input-json file://athena-query-config.json

# Get the file created.  We need awk. There should be only one .yml file in the bucket
# ls output will be like:
# 2022-11-12 23:16:03      15481 athena-templates/VPCFlowLogsIntegrationTemplate_fl-0c4cf2c9e927d09c5_Sat Nov 12 23:16:02 UTC 2022.yml
#
CFN_FILE=$(aws s3 ls s3://$BUCKET/athena-templates/ --recursive | awk -F' ' '{$1=$2=$3=""; print $0}'| awk -F'/' '{print $2}')
echo "CFN_FILE=$CFN_FILE."

aws s3 cp "s3://$BUCKET/athena-templates/$CFN_FILE" athena.yml

aws cloudformation create-stack \
    --stack-name $PREFIX-athena-query \
    --capabilities CAPABILITY_IAM \
    --template-body file://athena.yml \

echo "Once the cloudformation template completes..."
echo "1. Go to Athena, look for a table with VPCFlowLogs in the name, try Preview Table"
echo "2. Look for a new Workgroup. There are Saved queries, including a Top Talkers report, etc."

echo "Done."
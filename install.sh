#!/bin/bash
#
# Setup an full-featured VPC - in a hands-free fashion!
#

if [ -z $1 ]; then
        echo "Must pass in a unique name that will also be used as a prefix to use for resource naming... Exiting..."
        exit 1
fi

# Which region? Display to user so they can double-check.
REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

echo $REGION
echo "VPC will be setup in $REGION..."

PREFIX=$1
echo "All stack names will be prefixed with $PREFIX..."

aws cloudformation deploy \
  --template-file vpc-multi-az.yaml \
  --parameter-overrides Prefix=$PREFIX UseThirdAZ=True UseWithRDS=True \
  --stack-name "$PREFIX-vpc"

echo "Done."


exit

./95-check-prereqs.sh
if [[ $? -ne 0 ]]; then
    echo "Missing prerequisites... exiting..."
    exit 1
fi

# Must pass in an s3 bucket (private) where the source code zip can be stored...
if [ -z $1 ]; then
        echo "Need the S3 Bucket Name as a parameter. Exiting..."
        exit 0
fi
BUCKET=$1


echo "Downloading certs that will be needed for SSL/TLS connections. These will be stored in the scripts folder..."
./11-get-certs.sh
      
echo "Creating repos..."
echo "$(date +"%T")"
./01-repo.sh $BUCKET
echo "$(date +"%T")"
STACK_NAME=$PREFIX-repo
./wait-for-stack-name.sh $STACK_NAME 10
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi


echo "Creating secrets..."
echo "$(date +"%T")"
./02-secret.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-secrets
./wait-for-stack-name.sh $STACK_NAME 10
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi


echo "Creating Aurora clusters..."
echo "$(date +"%T")"
./03-aurora.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-aurora
./wait-for-stack-name.sh $STACK_NAME 60
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi


echo "Creating MySQL Multi-AZ Instance..."
echo "$(date +"%T")"
./04-rds-instance.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-rds-instance
./wait-for-stack-name.sh $STACK_NAME 60
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi

echo "Creating Postgresql Multi-AZ Cluster ..."
echo "$(date +"%T")"
./08-rds-cluster.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-rds-cluster
./wait-for-stack-name.sh $STACK_NAME 60
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi


echo "Creating DocumentDB ..."
echo "$(date +"%T")"
./05-docdb.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-docdb
./wait-for-stack-name.sh $STACK_NAME 60
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi


echo "Creating Neptune..."
echo "$(date +"%T")"
./06-neptune.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-neptune
./wait-for-stack-name.sh $STACK_NAME 60
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi


echo "Creating Redshift..."
echo "$(date +"%T")"
./07-redshift.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-redshift
./wait-for-stack-name.sh $STACK_NAME 60
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi


echo "Creating pipeline..."
echo "$(date +"%T")"
./09-pipeline.sh
echo "$(date +"%T")"
STACK_NAME=$PREFIX-pipeline
./wait-for-stack-name.sh $STACK_NAME 20
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].StackStatus" --output text)
if [[ $STACK_STATUS != "CREATE_COMPLETE" ]] && [[ $STACK_STATUS != "UPDATE_COMPLETE" ]]; then
        echo "Create or Update of Stack $STACK_NAME failed: $STACK_STATUS.  Cannot continue..."
        exit 1
fi

echo "Done."

echo "The CodePipeline to populate database schema should start running automatically. It will take a few minutes to complete."

PIPELINE_STATUS=$(aws codepipeline get-pipeline-state --name $PREFIX-schema-install --query "stageStates[?stageName=='Build'].latestExecution.status" --output text)
echo "(Current status of the Pipeline is $PIPELINE_STATUS)"

echo "While you wait, you can Peer your Cloud9 or EC2 VPC to the Database VPC by running ./peer.sh next..."
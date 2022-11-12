#!/bin/bash

#
# This uninstalls (DELETES!) everything.
#

if [ -z $1 ]; then
        echo "Must pass in the unique name that you wish to delete... Exiting..."
        exit 1
fi
PREFIX=$1

REGION=${AWS_DEFAULT_REGION:-$(aws configure get default.region)}

# NOTE: if you invoke with --yes (must be after the prefix name) it will skip these "Are you sure?" prompts
if [[ $2 != "--yes" ]]; then
    read -p "This will delete $PREFIX in $REGION and all associated resources. Are you sure? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
    
    read -p "Have you deleted any LOAD BALANCERS or INGRESS before proceeding? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
    
    read -p "Did you run ./unpeer.sh to remove any VPC Peering you created with ./peer.sh? If you didn't run peer.sh, enter Y. (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "For a clean un-install, you should run ./unpeer.sh CLUSTERNAME before deleting..."
        exit 1
    fi

fi

if [[ $2 != "--yes" ]]; then
    read -p "About to start deleting. Are you sure you are sure???? (Yy) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
fi

echo "OK... here we go..."

# Get the artifacts bucket from the Pipeline stack
BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='$PREFIX-LoggingBucket'].Value" --output text)

# Empty the utility bucket (Otherwise stack delete will fail)
echo "Will empty bucket $BUCKET - to prevent stack delete from failing..."
aws s3 rm s3://$BUCKET --recursive

STACK_NAME=$PREFIX-vpc
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME 

STACK_NAME=$PREFIX-logging
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME 


exit


# Find the Node Instance Role and remove any manually attached policies (otherwise stack delete will fail)
NODE_INSTANCE_ROLE=$(aws cloudformation describe-stack-resources --stack-name "eksctl-$PREFIX-nodegroup-nodes" --query "StackResources[?LogicalResourceId=='NodeInstanceRole'].PhysicalResourceId" --output text)
POLICIES=$(aws iam list-attached-role-policies --role-name $NODE_INSTANCE_ROLE --query "AttachedPolicies[*].PolicyArn" --output text )

echo "Removing all policies attached to $NODE_INSTANCE_ROLE (To ensure a clean stack delete)"
#
# This is important because we might've added app specific policies, or CloudWatch, etc.
#
ARRAY=($POLICIES)
for P in "${ARRAY[@]}"
do
    echo "Detaching $P..."
    aws iam detach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn $P
done

# Need to get all fargate profiles and loop to delete/remove
FARGATE_PROFILES=$(aws eks list-fargate-profiles --cluster-name $PREFIX --query "fargateProfileNames[*]" --output text)
echo "Looking for Fargate Profiles ..."
ARRAY=($FARGATE_PROFILES)
for F in "${ARRAY[@]}"
do
    echo "Profile: $F."
    echo "Deleting Fargate Profile $F... (This can take awhile, be patient.)"
    eksctl delete fargateprofile --cluster $PREFIX --name $F --wait 
done

# Find OIDC Provider
# This gives us the https:// Issuer name
OIDC_ISSUER=$(aws eks describe-cluster --name $PREFIX --query "cluster.identity.oidc.issuer" --output text)
echo "OIDC_ISSUER=$OIDC_ISSUER.  Now we need to find the ARN..."

echo "Checking all the existing ODIC providers to find the ARN of the one associated with the cluster..."
# We'll just grab the ARN for now, and delete it later.
OIDCS=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[*].Arn" --output text)
ARRAY_OIDCS=($OIDCS)
OIDC_ARN=""
for O in "${ARRAY_OIDCS[@]}"
do
    URL=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn $O --query "Url" --output text)
    if [[ "https://$URL" == "$OIDC_ISSUER" ]]; then
        OIDC_ARN=$O
        echo "Found OIDC_ARN=$OIDC_ARN."
    fi
done 
# OIDC_ARN should now be the ARN of the OIDC Provider that we'll delete later.

STACK_NAME=eksctl-$PREFIX-addon-iamserviceaccount-kube-system-aws-load-balancer-controller
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

STACK_NAME=eksctl-$PREFIX-addon-iamserviceaccount-kube-system-cluster-autoscaler
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

STACK_NAME=eksctl-$PREFIX-addon-aws-ebs-csi-driver
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

STACK_NAME=eksctl-$PREFIX-nodegroup-nodes
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

STACK_NAME=eksctl-$PREFIX-addon-vpc-cni
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

# Find any "other" stacks that seem related.
# If the stackname starts with "eksctl-CLUSTERNAME-" it's possibly related. But we ask to make sure.
OTHER_STACKS=$(aws cloudformation list-stacks --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].StackName" --output text)
echo "Looking for stacks that look related, but were created outside of the install script..."
ARRAY=($OTHER_STACKS)
for S in "${ARRAY[@]}"
do
    # Skip the -cluster stack - we'll delete that one AFTER any dependent stacks are gone.
    if [[ $S != "eksctl-$PREFIX-cluster" ]]; then
        if [[ "$S" == *"eksctl-$PREFIX-"* ]]; then
            read -p "Stack named $S ($AWS_DEFAULT_REGION) appears related, but created manually. DO YOU WANT TO DELETE THIS STACK? (Yy) " -n 1 -r
            echo    # (optional) move to a new line
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Deleting stack $S..."
                aws cloudformation delete-stack --stack-name $S
                aws cloudformation wait stack-delete-complete --stack-name $S
            else
                echo "Leaving stack $S as-is..."
            fi
        fi
    fi
done

STACK_NAME=eksctl-$PREFIX-cluster
echo "Deleting ($STACK_NAME) ..."
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME


if [[ $OIDC_ARN != "" ]]; then
    echo "Deleting OIDC Provider $OIDC_ARN..."
    aws iam delete-open-id-connect-provider --open-id-connect-provider-arn $OIDC_ARN
fi
	
echo "Done."

echo "You probably want to run ./99-uninstall.sh now, to remove the IAM roles and VPC."
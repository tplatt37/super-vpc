#!/bin/bash

#
# After some VPC Logs have arrived, you can setup Athena querying easily
# Ref: https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-athena.html
#
#

aws ec2 get-flow-logs-integration-template --cli-input-json file://athena-query-config.json

aws cloudformation create-stack \
    --stack-name my-vpc-flow-logs 
    --template-body file://my-cloudformation-template.json
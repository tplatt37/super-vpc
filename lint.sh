#!/bin/bash

cfn-lint bucket.yaml
cfn-lint vpc-multi-az.yaml

aws cloudformation validate-template --template-body file://bucket.yaml
aws cloudformation validate-template --template-body file://vpc-multi-az.yaml
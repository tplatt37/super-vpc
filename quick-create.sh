#!/bin/bash

#
# This is how I normally run this. so let's make it a script.
#

export AWS_DEFAULT_REGION=us-east-1
cd ~/environment && git clone git@github.com:tplatt37/super-vpc; cd ~/environment/super-vpc
./install.sh "demo"
export PRIVATE_SUBNETS=$(./get-subnets.sh "demo" "private" 2)
export PUBLIC_SUBNETS=$(./get-subnets.sh "demo" "public" 2)

echo "PRIVATE_SUBNETS=$PRIVATE_SUBNETS"
echo "PUBLIC_SUBNETS=$PUBLIC_SUBNETS"

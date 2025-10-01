#

Super-VPC - a VPC for trainers

It includes:

* 2 or 3 Availability Zones
* Public Subnet (with NAT GW) and Private Subnet for each AZ ($$$!)
* VPC Flow logs are enabled and logging to an S3 bucket (encrypted with KMS symmetric key)
* Gateway Endpoints - DynamoDB and S3
* Interface Endpoints - For Systems Manager

Also
* Optionally, you can create an Athena Workgroup for querying the VPC Flow logs.
* Easy to peer up your EC2 instance for demos - Peering Connection, Route Tables, Security Group updates all done via helper script.
* Includes a DB Subnet Group for use with RDS (and a Security Group)

# Installation

Simply run the installer. You need to provide a Prefix for resource naming:
```
./install.sh "demo"
```

Here's a recommended way to run this, which places some commonly used info into environment variables:
```
export AWS_DEFAULT_REGION=us-west-2
cd ~/environment && git clone git@github.com:tplatt37/super-vpc; cd ~/environment/super-vpc
./install.sh "demo"
PRIVATE_SUBNETS=$(./get-subnets.sh "demo" "private" 2)
PUBLIC_SUBNETS=$(./get-subnets.sh "demo" "public" 2)
echo "PRIVATE_SUBNETS=$PRIVATE_SUBNETS"
echo "PUBLIC_SUBNETS=$PUBLIC_SUBNETS"
```

# Then What?

You can use the VPC as usual.

Peer it up with your EC2 demo instance easily:
```
./peer.sh "demo"
```

There's a built-in security group you can use with your own EC2 instances. Open ports from your EC2 instance easily:
```
./update-group-ingress.sh "demo" "22,80,443"
```

The above opens TCP 22,80, and 443 from source of EC2

You can optionally enable an Athena Query Work Group with predefined queries (such as Top Talkers)
```
./athena-query-setup.sh "demo"
```

# Other things

1. The Logging Bucket is ready to be used for ELB access logs
2. If you use the UseWithRDS option, a DB Subnet Group and Security Group for convenient DB access is provided.


# Uninstall

You will need to perform any cleanup of resources using the network resources.

Once done, run the uninstsaller:

```
./unpeer.sh "demo"
```

```
./revoke-group-ingress.sh "demo"
```

Be sure to uninstall/delete/remove any custom resources you added... then

```
./uninstall.sh "demo"
```

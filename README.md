#

Super-VPC - a VPC for trainers

It includes:

* 2 or 3 Availability Zones
* Public Subnet and Private Subnet for each AZ
* VPC Flow logs are enabled and logging to an S3 bucket (encrypted with KMS symmetric key)
* Gateway Endpoints - DynamoDB and S3
* Interface Endpoints - For Systems Manager
* Optionally, you can create an Athena Workgroup for querying the VPC Flow logs.

# Installation

Simply run the installer. You need to provide a Prefix for resource naming:
```
./install.sh "demo"
```

# Then What?

You can use the VPC as usual.

You can optionally enable an Athena Query Work Group with predefined queries (such as Top Talkers)
```
./athena-query-setup.sh "demo"
```
# Other things

1. The Logging Bucket is ready to be used for ELB access logs
2. If you use the UseWithRDS option, a DB Subnet Group and Security Group for convenient DB access is provided.
3. 

# Uninstall

You will need to perform any cleanup of resources using the network resources.

Once done, run the uninstsaller:

```
./uninstall.sh "demo"
```

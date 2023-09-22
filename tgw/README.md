# Transit Gateway

Optionally with Super-VPC you can create a Transit Gateway (TGW) which is regional virtual router.

You can use this TGW to peer together multiple VPCs and you can peer this TGW to another TGW in another region.

# Pre-Requisites

This script helps setup two peered TGWs for trainer demonstration purposes. 

It is far simpler (and cheaper) to simply use VPC Peering when you have a small number of VPCs that need to connect. (But a Transit Gateway is more scalable, and can also accomodate VPN and Direct Connect connections too...)

You need to provide:
1. One or more VPCs (created by Super-VPC?) in two regions

You can then setup...

# Install

# Uninstall


# Notes

What would make sense?

us-west-2 
  Dev VPC
  TGW

aus-east-1
  Database VPC
  Dev VPC
  TGW

Both DEV VPC can connect to Database but not to each other?
Database VPC is like a "Shared Services" style of TGW Pattern.

```
01-create-tgw.sh --region us-east-1 --name "super-vpc"
```

You can run the following commands as many times as needed to attach VPCs to the TGW.
Please note this will result in FULL MESH CONNECTIVITY, as the default route table will be used.
That's good enough for simple demos. If you wanted to demo network isolation you should attach with a custom route table.
This command will create a declarative TGW Attachment via CFN, but will also place the Route Table entry into the VPCs route table (this is NOT done declaratively)
```
02-attach-vpc.sh --region us-east-1 --vpcid --name
```

```
03-peer-tgw.sh
```
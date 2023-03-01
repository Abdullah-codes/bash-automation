## Automation to setup AWS infra and Deploy Wordpress.

By using only single script we can create the AWS infrastructure and deploy the wordpress.

**Setup_infra_and_deploy.sh**

This script creates the infrastructure and deploys the wordpress on the two EC2 instances fronted by load balancer .
It creates networking components necessary to run the EC2 instance. E.g. VPC Security Groups, Subnets, internet gateway. 
Then creates RDS which is used by wordpress.
Next step creates a Load balancer then an auto scaling group and registers the auto scaling group with the target group so we can access the website using Load balancer.

**packages.sh**

This script is part of an Launch config we provide it as an user data so when ec2 instance spins up this script will run on that instance which will  install all the necessary packages create database entries, configure and launch wordpress on the instance,

**Delete_infra.sh**

As the name suggest this script cleans up the whole infra.


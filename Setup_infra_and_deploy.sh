#! /usr/bin/bash
  
set -euo pipefail


create_vpc () {

        echo "creating vpc...."
        VPC_ID=$( aws ec2 create-vpc --cidr-block 10.0.0.0/16 | jq .Vpc.VpcId -r)

        echo "setting up vpc  name "
        aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=aws_cli
}


create_subnets () { 
	
	echo "creating subnet public"
	SUBNET_ID_PUBLIC=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone-id aps1-az1 | jq .Subnet.SubnetId -r )
	echo "SUBNET ID PUBLIC : $SUBNET_ID_PUBLIC"

	echo "creating subnet private"
	SUBNET_ID_PRIVATE=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone-id aps1-az1 | jq .Subnet.SubnetId -r )

	echo "creating private subnet for availability zone for rds subnet group"
	SUBNET_ID_PRIVATE_RDS=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone-id aps1-az3 | jq .Subnet.SubnetId -r )

	echo "creating db subnet group"
	DB_SUBNET_GROUP_NAME=$(aws rds create-db-subnet-group --db-subnet-group-name dbsubnetgroup --db-subnet-group-description " DB subnet group" --subnet-ids '["'$SUBNET_ID_PRIVATE'","'$SUBNET_ID_PRIVATE_RDS' "]' |jq .DBSubnetGroup.DBSubnetGroupName -r)

	echo $DB_SUBNET_GROUP_NAME

	echo "creating subnet for load balancer"
	SUBNET_ID_LB=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.4.0/24 --availability-zone-id aps1-az3 | jq .Subnet.SubnetId -r )

	echo $SUBNET_ID_LB


}


create_ig () {

	echo "creating internet gateway"
	IGW_ID=$(aws ec2 create-internet-gateway | jq .InternetGateway.InternetGatewayId -r)

	echo "attaching ig to vpc"
	aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

}


create_route_table () {

	echo "creating route table"
	ROUTE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID | jq .RouteTable.RouteTableId -r )

	echo "creating route for internet access"
	aws ec2 create-route --route-table-id $ROUTE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

	echo "associatng route tablle to public subnet"
	aws ec2 associate-route-table  --subnet-id $SUBNET_ID_PUBLIC --route-table-id $ROUTE_ID

	echo "associatng route table to lb subnet"
	aws ec2 associate-route-table  --subnet-id $SUBNET_ID_LB --route-table-id $ROUTE_ID


}


allocate_public_ip_to_subnet () {
	
	echo "setup auto public ip in public subnet"
	aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID_PUBLIC --map-public-ip-on-launch
	aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID_LB --map-public-ip-on-launch

}

create_security_group () {

	echo "creating security group"
	SECURITY_GID_PUBLIC=$(aws ec2 create-security-group --group-name SSHAccess2 --description "Security group for SSH access 2" --vpc-id $VPC_ID | jq .GroupId -r )

	echo "allowing port 22 in security group"
	aws ec2 authorize-security-group-ingress --group-id $SECURITY_GID_PUBLIC --protocol tcp --port 22 --cidr 0.0.0.0/0

	echo "allowing port 80 for inbound traffic"
	aws ec2 authorize-security-group-ingress --group-id $SECURITY_GID_PUBLIC --protocol tcp --port 80 --cidr 0.0.0.0/0

	echo "creating security group for DB"
	SECURITY_GID_DB=$(aws ec2 create-security-group --group-name Dbsecurty --description "Security group for DB" --vpc-id $VPC_ID | jq .GroupId -r )

	echo "allowing port 22 in security group"
	aws ec2 authorize-security-group-ingress --group-id $SECURITY_GID_DB --protocol tcp --port 22 --cidr 0.0.0.0/0

	echo "allowing port 3306 in security group"
	aws ec2 authorize-security-group-ingress --group-id $SECURITY_GID_DB --protocol tcp --port 3306 --cidr 0.0.0.0/0

}

create_rds_database () {
	echo "launching databse RDS in private subnet "
	aws rds create-db-instance --db-instance-identifier mysql-instance --db-instance-class db.t2.micro --engine mysql --master-username admin --master-user-password salafi123 --allocated-storage 20 --port 3306 --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" --vpc-security-group-ids "$SECURITY_GID_DB"

}

check-status () {
        # this function will time out in sleep_interval * loop_count time (e.g. 10s*90=900s=15mins)
        sleep_interval=10s
        counter=1
        loop_count=90
        echo "starting loop no $counter"
        while true ; do
          state=$(aws rds describe-db-instances | jq '.DBInstances[] | select(.DBInstanceClass=="db.t2.micro") | .DBInstanceStatus' -r)
          #state="hfysgfysef"
          #state="available"
          if [[ $state == "available" ]]; then
                echo "db in available state, exiting wait loop"
                break
          else
                echo "db in creating mode"
                sleep $sleep_interval
                counter=$((counter+1))
                echo "starting loop no $counter"
                if [[ $counter -eq $loop_count ]]; then
                        echo "timing out after 15mins"
                        exit 1
                fi
          fi
        done

}


sleep_function () {
	echo "sleeping for 8 mins"
	sleep 8m
}

rds_endpoint () {
	echo "getting DB endpoint"
	RDS_ENDPOINT=$(aws rds describe-db-instances | jq '.DBInstances[].Endpoint | .Address' -r)
	echo $RDS_ENDPOINT

}

create_packages_sh () {
	echo "copying templet packages file"
	cp -f packages.sh packages_launch.sh
	echo "putting rds endpoint in userDAta script"
	sed -i "s/rdsendpoint/$RDS_ENDPOINT/g" packages_launch.sh
}


create_load_balancer () {
	echo "creating load balancer"
	LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer --name my-load-balancer --subnets $SUBNET_ID_PUBLIC $SUBNET_ID_LB --security-groups $SECURITY_GID_PUBLIC | jq .LoadBalancers[].LoadBalancerArn -r )

	echo $LOAD_BALANCER_ARN

}

create_target_group () {
	echo "creating target group"
	TARGATE_GROUPP_ARN=$(aws elbv2 create-target-group --name my-targets --health-check-path /health.html --protocol HTTP --port 80 --vpc-id $VPC_ID | jq .TargetGroups[].TargetGroupArn -r )

	echo $TARGATE_GROUPP_ARN


}

create_listner () {
	echo "creating listner of load balancer"
	aws elbv2 create-listener --load-balancer-arn $LOAD_BALANCER_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TARGATE_GROUPP_ARN

	
}

create_launch_conf () {
	echo "creating luanch conf"

	aws autoscaling create-launch-configuration --launch-configuration-name my-launch-config --image-id ami-0c1a7f89451184c8b --instance-type t2.micro --key-name awskeypair --security-groups $SECURITY_GID_PUBLIC --user-data file:///home/abdullah/Desktop/aws_automation_functions/packages_launch.sh

	
}

sleep_function_two () {
	echo "sleeping for 10 sec"
}


get_launch_conf_name () {
	
	echo "getting launch conf name"
	LAUNCH_CONF_NAME=$(aws autoscaling describe-launch-configurations | jq '.LaunchConfigurations[] | select(.KeyName=="awskeypair") | .LaunchConfigurationName' -r)
	echo $LAUNCH_CONF_NAME

}


create_auto_scaling_group () {
	echo "Creating Auto scaling group"
	aws autoscaling create-auto-scaling-group --auto-scaling-group-name my-asg --launch-configuration-name $LAUNCH_CONF_NAME --min-size 2 --max-size 2 --desired-capacity 2 --vpc-zone-identifier "$SUBNET_ID_PUBLIC" --health-check-type ELB --health-check-grace-period 200 --target-group-arns $TARGATE_GROUPP_ARN
	
}

main () {
	
	create_vpc
	create_subnets
	create_ig
	create_route_table
	allocate_public_ip_to_subnet
	create_security_group
	create_rds_database
	check-status
#	sleep_function
	rds_endpoint
	create_packages_sh
	create_load_balancer
	create_target_group
	create_listner
	create_launch_conf
	sleep_function_two
	get_launch_conf_name
	create_auto_scaling_group

				
} 


main

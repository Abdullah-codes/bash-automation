#! /usr/bin/bash
  
#set -euo pipefail


get_vpc_id () {
	
	echo "Getting VPC ID "
	VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=aws_cli" | jq .Vpcs[].VpcId -r )
	echo "VPC ID: $VPC_ID "
}


delete_auto_scaling_group () {
	
	echo "getting auto scaling group name"
	AUTO_SCALING_GROUP_NAME=$(aws autoscaling describe-auto-scaling-groups |jq .AutoScalingGroups[].AutoScalingGroupName -r)
	echo $AUTO_SCALING_GROUP_NAME
	echo "deleting auto scaling group"
	aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $AUTO_SCALING_GROUP_NAME --force-delete
}


delete_rds_database () {

	echo "getting db instance-identifier "
	DB_INSTANCE_IDENTIFIER=$(aws rds describe-db-instances | jq '.DBInstances[] | select(.DBInstanceClass=="db.t2.micro") | .DBInstanceIdentifier' -r)
	echo $DB_INSTANCE_IDENTIFIER
	echo "Deleting all DB instances"
	for db_id in $DB_INSTANCE_IDENTIFIER;do  aws rds delete-db-instance --db-instance-identifier $db_id --skip-final-snapshot ;done

	
}

check_status () {
        # this function will time out in sleep_interval * loop_count time (e.g. 10s*90=900s=15mins)
        sleep_interval=10s
        counter=1
        loop_count=90
        echo "starting loop no $counter"
        while true ; do
          #state=$(cat emptydatabse | jq '.DBInstances' -r)
	  auto_scaling_state=$(aws autoscaling describe-auto-scaling-groups | jq  .AutoScalingGroups[] )
          rds_state=$(aws rds describe-db-instances | jq '.DBInstances[] | select(.DBInstanceClass=="db.t2.micro") | .DBInstanceIdentifier' -r)
          #state="available"
          if [[ "$rds_state" == "" ]] && [[ "$auto_scaling_state" == "" ]]; then
                echo "db has been deleted got empty list and autoscaling has been deleted"
                break
          else
                echo "db and auto scaling is in  deleting state"
                sleep $sleep_interval
                counter=$((counter+1))
                echo "starting loop no $counter"
                if [[ $counter -eq $loop_count  ]]; then
                        echo "timing out after 15mins"
                        exit 1
                fi
          fi
        done

}

done_rds () {

	echo "succefully deleted rds --------------------------- and auto scaling groups"

}

sleep_function_8min () {
echo "sleeping for 8 mins"
sleep 8m
}

delete_load_balancer () {
	
	echo "getting load balacer "
	LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers |jq .LoadBalancers[].LoadBalancerArn -r)
	echo "deleting load balancer"
	aws elbv2 delete-load-balancer --load-balancer-arn $LOAD_BALANCER_ARN

}

sleep_function_10s () {
	echo "sleeping for 10s"
	sleep 10s
}

delete_target_group () {
	
	echo "getting target group arn for deletation"
	TRAGET_GROUP_ARN=$(aws elbv2 describe-target-groups|jq .TargetGroups[].TargetGroupArn -r)
	echo "deleting target group"
	aws elbv2 delete-target-group --target-group-arn $TRAGET_GROUP_ARN

	
}

delete_launch_conf () {

	echo "getting launch conf name"
	LUANCH_CONF_NAME=$(aws autoscaling describe-launch-configurations | jq '.LaunchConfigurations[] | select(.KeyName=="awskeypair") | .LaunchConfigurationName' -r)
	echo "deleting launch conf"
	aws autoscaling delete-launch-configuration --launch-configuration-name $LUANCH_CONF_NAME
}

delete_route_tables () {

	echo "disassociating route table from subnet"
	ROUTE_TABLE_ASSOCIASION_IDS=$(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID | jq '.RouteTables[].Associations[] | select(.Main==false) | .RouteTableAssociationId' -r )
	for rt_associasion in $ROUTE_TABLE_ASSOCIASION_IDS;
	do
  	 aws ec2 disassociate-route-table --association-id $rt_associasion ;
	done
	echo "sleeping for 5s"
	sleep 5s
	echo "getting route tables"
	ROUTE_TABLE_ID_ONE=$(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID | jq '.RouteTables[] | select(.Routes[].DestinationCidrBlock=="0.0.0.0/0") | .RouteTableId' -r )
	echo "Deleting ROUTE TABLE ID: $ROUTE_TABLE_ID_ONE "
	aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID_ONE

}

delete_rds_subnet_group () {
	
	echo "getting rds subnet group name"
	RDS_DB_SUBNET_NAME=$(aws rds describe-db-subnet-groups | jq '.DBSubnetGroups[] | select(.VpcId=="'$VPC_ID'") | .DBSubnetGroupName' -r)
	echo "deleting rds subnet group"
	aws rds delete-db-subnet-group --db-subnet-group-name $RDS_DB_SUBNET_NAME
}

delete_security_groups () {

	echo "getting security ID "
	SECURITY_ID=$(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq '.SecurityGroups[] | select(.GroupName!="default") | .GroupId' -r )
	echo "SECURITY GID: $SECURITY_ID"
	echo "Deleting security group"
	for sg_id in $SECURITY_ID;do   aws ec2 delete-security-group --group-id $sg_id; done

}


delete_subnets () {
	
	echo "getting subnet IDS"
	SUBNET_IDS=$(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq .Subnets[].SubnetId -r)
	echo "SUBNET ID: $SUBNET_IDS"
	echo "deleting subnets"
	for sub_id in $SUBNET_IDS;do  aws ec2 delete-subnet --subnet-id $sub_id; done
}


delete_ig () {
		
	echo "getting internet gatway ID"
	INTERNET_GATWAY_ID=$(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq .InternetGateways[].InternetGatewayId -r)
	echo "INTERNET_GID: $INTERNET_GATWAY_ID"
	echo "detaching IG "
	aws ec2 detach-internet-gateway --internet-gateway-id $INTERNET_GATWAY_ID --vpc-id $VPC_ID
	echo "deleting IG"
	aws ec2 delete-internet-gateway --internet-gateway-id $INTERNET_GATWAY_ID
	
}


delete_vpc () {
	
	echo "Deleting VPC"
	aws ec2 delete-vpc --vpc-id $VPC_ID
	
}

main () {
	
	get_vpc_id
	delete_auto_scaling_group
	delete_rds_database
	check_status
	done_rds
#	sleep_function_8min
	delete_load_balancer
	sleep_function_10s
	delete_target_group
	delete_launch_conf
	delete_route_tables
	delete_rds_subnet_group
	delete_security_groups
	delete_subnets		
	delete_ig
	delete_vpc

}

main	

#!/bin/bash

####common VIRT_TYPE specific value ################
VIRT_TYPE="ec2"

cd ..
source ./commonutil.sh

#### VIRT_TYPE specific processing  (must define)###
#$1 nodename $2 disksize $3 nodenumber $4 hostgroup#####
run(){
	NODENAME=$1
	DISKSIZE=$2
	NODENUMBER=$3
	HOSTGROUP=$4

	vpcid=`aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=VPC-${PREFIX}" --query "Vpcs[].VpcId" --output text`
	
	sgid=`aws ec2 describe-security-groups --region $REGION --filters "Name=tag:Name,Values=SG-${PREFIX}" --query "SecurityGroups[].GroupId" --output text`
 
	subnetid=`aws ec2 describe-subnets --region $REGION --filters "Name=tag:Name,Values=SUBNET-${PREFIX}" --output text --query "Subnets[].SubnetId"`

        
	DeviceJson="[{\"DeviceName\":\"${data_disk_dev}\",\"Ebs\":{\"VolumeSize\":${2},\"DeleteOnTermination\":true,\"VolumeType\":\"gp2\"}}]"
	
	INSTANCE_ID=$(aws ec2 run-instances --region $REGION $INSTANCE_OPS $INSTANCE_TYPE_OPS --key-name $PREFIX --subnet-id $subnetid --security-group-ids $sgid --block-device-mappings $DeviceJson --count 1 --query "Instances[].InstanceId" --output text)
	aws ec2 create-tags --region $REGION --resources $INSTANCE_ID --tags Key=NODENAME,Value=$NODENAME
	External_IP=`get_External_IP $INSTANCE_ID`
	Internal_IP=`get_Internal_IP $INSTANCE_ID`
	#$NODENAME $IP $INSTANCE_ID $NODENUMBER $HOSTGROUP
	common_update_all_yml
	common_update_ansible_inventory $NODENAME $External_IP $INSTANCE_ID $NODENUMBER $HOSTGROUP

	echo $Internal_IP

}

#### VIRT_TYPE specific processing  (must define)###
#$1 nodecount                                  #####
runonly(){
	if [ "$1" = "" ]; then
		nodecount=3
	else
		nodecount=$1
	fi

	vpcid=`aws ec2 create-vpc --cidr-block $VPC_ADDR --region $REGION --query 'Vpc.VpcId' --output text`
	
	aws ec2 create-tags --region $REGION --resources $vpcid --tags Key=Name,Value=VPC-${PREFIX}

	aws ec2 modify-vpc-attribute --region $REGION --vpc-id $vpcid --enable-dns-support
	aws ec2 modify-vpc-attribute --region $REGION --vpc-id $vpcid --enable-dns-hostnames

	subnetid=`aws ec2 create-subnet --vpc-id $vpcid --cidr-block $SUBNET_ADDR  --availability-zone ${REGION}a --region $REGION --query 'Subnet.SubnetId' --output text`

	aws ec2 create-tags --region $REGION --resources $subnetid --tags Key=Name,Value=SUBNET-${PREFIX}

	sgid=`aws ec2 create-security-group --region $REGION --group-name ${PREFIX} --description "Security group for SSH access" --vpc-id $vpcid --query "GroupId" --output text`

	aws ec2 create-tags --region $REGION --resources $sgid --tags Key=Name,Value=SG-${PREFIX}
	
	aws ec2 authorize-security-group-ingress --region $REGION --group-id $sgid --protocol all --source-group $sgid
	
	aws ec2 authorize-security-group-ingress --region $REGION --group-id $sgid --protocol tcp --port 22 --cidr 0.0.0.0/0

	GatewayId=`aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text`

	aws ec2 create-tags --region $REGION --resources $GatewayId --tags Key=Name,Value=GW-${PREFIX}

	aws ec2 attach-internet-gateway --region $REGION --vpc-id $vpcid --internet-gateway-id $GatewayId

	RouteTableId=`aws ec2 create-route-table --region $REGION --vpc-id $vpcid --query 'RouteTable.RouteTableId' --output text`

	aws ec2 create-tags --region $REGION --resources $RouteTableId --tags Key=Name,Value=RTABLE-${PREFIX}


	aws ec2 create-route  --region  $REGION --route-table-id $RouteTableId --destination-cidr-block 0.0.0.0/0 --gateway-id $GatewayId

aws ec2 associate-route-table  --region $REGION --subnet-id $subnetid --route-table-id $RouteTableId

aws ec2 modify-subnet-attribute  --region $REGION --subnet-id $subnetid --map-public-ip-on-launch
 
        if [  ! -e ${ansible_ssh_private_key_file} ] ; then
	        aws ec2 create-key-pair --region $REGION --key-name $ansible_ssh_private_key_file  --query 'KeyMaterial' --output text > $ansible_ssh_private_key_file
		chmod 600 ${ansible_ssh_private_key_file}*
	fi
   

	STORAGEIP=`run storage $STORAGE_DISK_SIZE 0 storage`
	
	common_update_all_yml "STORAGE_SERVER: $STORAGEIP"
	
	for i in `seq 1 $nodecount`;
	do
		NODENAME="$NODEPREFIX"`printf "%.3d" $i`
		run $NODENAME $NODE_DISK_SIZE $i "dbserver"
	done
	
	sleep 300s
#	CLIENTNUM=70
#	NUM=`expr $BASE_IP + $CLIENTNUM`
#	CLIENTIP="${SEGMENT}$NUM"	
#	run "client01" $CLIENTIP $CLIENTNUM "client"
	
}

deleteall(){
   	common_deleteall $*
	#### VIRT_TYPE specific processing ###
	if [ -e "$ansible_ssh_private_key_file" ]; then
   		rm -rf ${ansible_ssh_private_key_file}*
		aws ec2 delete-key-pair --region $REGION --key-name $ansible_ssh_private_key_file
	fi
   	
	
sgid=`aws ec2 describe-security-groups --region $REGION --filters "Name=tag:Name,Values=SG-${PREFIX}" --query "SecurityGroups[].GroupId" --output text`


aws ec2 delete-security-group --region $REGION --group-id $sgid

	subnetid=`aws ec2 describe-subnets --region $REGION --filters "Name=tag:Name,Values=SUBNET-${PREFIX}" --output text --query "Subnets[].SubnetId"`
	
	aws ec2 delete-subnet --region $REGION --subnet-id $subnetid

RouteTableId=`aws ec2 describe-route-tables --region $REGION --filters "Name=tag:Name,Values=RTABLE-${PREFIX}" --query "RouteTables[].RouteTableId" --output text`

aws ec2 delete-route-table --region $REGION --route-table-id $RouteTableId


	vpcid=`aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=VPC-${PREFIX}" --query "Vpcs[].VpcId" --output text`

	GatewayId=`aws ec2 describe-internet-gateways --region $REGION --filters "Name=tag:Name,Values=GW-${PREFIX}" --query "InternetGateways[].InternetGatewayId" --output text`
	
aws ec2 detach-internet-gateway --region $REGION --internet-gateway-id $GatewayId --vpc-id $vpcid

aws ec2 delete-internet-gateway --region $REGION --internet-gateway-id $GatewayId

aws ec2 delete-vpc --region $REGION --vpc-id $vpcid
}

replaceinventory(){
	for FILE in $VIRT_TYPE/host_vars/*
	do
		INSTANCE_ID=`echo $FILE | awk -F '/' '{print $3}'`
		External_IP=`get_External_IP $INSTANCE_ID`
		common_replaceinventory $INSTANCE_ID $External_IP
	done
}

get_External_IP(){
	if [[ $1 = i-*  ]]; then
		INSTANCE_ID=$1
	else
		expr "$1" + 1 >/dev/null 2>&1
		if [ $? -lt 2 ]
		then
    			NODENAME="$NODEPREFIX"`printf "%.3d" $1`
		else
    			NODENAME=$1
		fi
		
		
		INSTANCE_ID=`aws ec2 describe-tags --region $REGION --filters "Name=resource-type,Values=instance" "Name=key,Values=NODENAME" "Name=value,Values=$NODENAME" --query "Tags[].ResourceId" --output text`
	fi


	External_IP=`aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query "Reservations[].Instances[].PublicIpAddress" --output text`
	echo $External_IP	
}

get_Internal_IP(){
	if [[ $1 = i-*  ]]; then
		INSTANCE_ID=$1
	else
		expr "$1" + 1 >/dev/null 2>&1
		if [ $? -lt 2 ]
		then
    			NODENAME="$NODEPREFIX"`printf "%.3d" $1`
		else
    			NODENAME=$1
		fi
		
		
		INSTANCE_ID=`aws ec2 describe-tags --region $REGION --filters "Name=resource-type,Values=instance" "Name=key,Values=NODENAME" "Name=value,Values=$NODENAME" --query "Tags[].ResourceId" --output text`
	fi

	Internal_IP=`aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query "Reservations[].Instances[].PrivateIpAddress" --output text`
	echo $Internal_IP	
}

source ./common_menu.sh

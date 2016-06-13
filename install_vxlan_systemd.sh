#!/bin/bash
source ./common.sh
cp ./vxlan.service /etc/systemd/system/vxlan.service
cp ./vxlan.init /usr/local/bin/vxlan.init
mkdir -p /etc/vxlan/
for i in $NODE_LIST ;
do
	echo $i >> /etc/vxlan/all.ip
done

CNT=0
MyNumber=`getmynumber`
for j in $NETWORK
do
        vxlanip=`getip $CNT real $MyNumber`
        #get network prefix     
        eval `ipcalc -s -p ${NETWORKS[$CNT]}/24`
        cat >/etc/vxlan/vxlan${CNT}.conf <<EOF
vInterface = vxlan${CNT}
Id = 1${CNT}
Ether = eth0
List = /etc/vxlan/all.ip
Address = ${vxlanip}/${PREFIX}
EOF
	CNT=`expr $CNT + 1`
done

chmod 0700  /usr/local/bin/vxlan.init
ln -s /etc/systemd/system/vxlan.service /etc/systemd/system/multi-user.target.wants/vxlan.service
systemctl start vxlan
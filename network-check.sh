#!/bin/bash
#
#This script is used to check the cluster network
#version 1.0.0
#author chenhui
#data 2016-12-19

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"

# config file
conf_path=$(cd "$(dirname "$0")"; pwd)/cephenv-check.conf
cluster_nic_speed=$(cat ${conf_path} | grep "cluster_nic_speed" | awk -F " = " '{print $2}')
public_nic_speed=$(cat ${conf_path} | grep "public_nic_speed" | awk -F " = " '{print $2}')
firewall_ports=$(cat ${conf_path} | grep "firewall_ports" | awk '{for(i=3;i<=NF;i++){print $i}}')
#log
logFolderPath=$(cat ${conf_path} | grep "logFolderPath" | awk -F " = " '{print $2}')
if [[ ! -d $logFolderPath ]]; then
	mkdir $logFolderPath	
fi
logFilePath=${logFolderPath}/network-check${logDate}.log
errFilePath=${logFolderPath}/network-check-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

echo "[${hostname}] "$(${curDate})" INFO: Network-check is starting to do on machine ${hostname}..." | tee ${logFilePath}

#network interface card
nics=$(ip a | grep  'inet ' | awk '{print $NF}')

#get ceph public network ip info
beginLine=$(cat /etc/hosts | grep -n ^"#ceph public" | grep -o '[0-9]*')
endLine=$(cat /etc/hosts | grep -n ^"#end ceph public" | grep -o '[0-9]*')
rangeLine=`expr $endLine - $beginLine - 1`
ceph_public_ips=$(cat /etc/hosts | egrep -A ${rangeLine} ^"#ceph public" | grep -v "#ceph" | awk '{print $1}')

#get ceph cluster network ip info
beginLine=$(cat /etc/hosts | grep -n ^"#ceph cluster" | grep -o '[0-9]*')
endLine=$(cat /etc/hosts | grep -n ^"#end ceph cluster" | grep -o '[0-9]*')
rangeLine=`expr $endLine - $beginLine - 1`
ceph_cluster_ips=$(cat /etc/hosts | egrep -A ${rangeLine} ^"#ceph cluster" | grep -v "#ceph" | awk '{print $1}')

funErrTalk(){
	while :
	do
		if read -t 10 -p "Do you want to continue? [y/n]:"; then
			case $REPLY in
				Y|y)
					break
					;;
				N|n)
					exit 1
					;;
				*)
					echo -e "\n input parameter error !! \n"
					continue
			esac
		fi
	done
}

#ping check
funPing(){
	for i in $@
	do
		echo "[${hostname}] "$(${curDate})" INFO: ${MONGLINE} PING $i ${MONGLINE}" | tee -a ${logFilePath}
		ping -w 4 -f -c 100 $i>/dev/null 2>&1
		if [[ "$?" == "0" &&  "0% packet loss" == `ping -w 4 -f -c 100 $i | tee -a ${logFilePath} | grep -o "0% packet loss"` ]]; then
			echo "[${hostname}] "$(${curDate})" INFO: Destination host $i is up, no packet loss!" | tee -a ${logFilePath}
		else
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Destination host $i unreachable, please check it !\e[0m" | tee -a ${errFilePath}
			#funErrTalk
		fi
	done
}

#network check
echo "[${hostname}] "$(${curDate})" INFO: ${DOUBPLET} Checking ceph network... ${DOUBPLET}" | tee -a ${logFilePath}
for i in ${nics[@]}
do
	curIP=$(ip a | grep 'inet ' | grep " ${i}" | awk '{print $2}' | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
	# check cluster nic
	echo "${ceph_cluster_ips[@]}" | grep "${curIP}">/dev/null 2>&1
	if [[ "$?" == "0" ]]; then
		echo "[${hostname}] "$(${curDate})" INFO: Ceph cluster network using IP is ${curIP} which NIC is ${i}" | tee -a ${logFilePath}
		speed=$(ethtool ${i} | grep 'Speed:' | awk '{print $2}' | grep -o '[0-9]*')
		if [[ ${cluster_nic_speed} -gt ${speed} ]]; then
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: NIC's speed must be at least ${cluster_nic_speed}Mb/s, but ${i}'s speed is ${speed}Mb/s\e[0m" | tee -a ${errFilePath}
			continue
		else
			echo "[${hostname}] "$(${curDate})" INFO: NIC's speed is ${speed}Mb/s"
			funPing ${ceph_cluster_ips[@]}
		fi
	fi
	# check public nic
	echo "${ceph_public_ips[@]}" | grep "${curIP}">/dev/null 2>&1
	if [[ "$?" == "0" ]]; then
		echo "[${hostname}] "$(${curDate})" INFO: Ceph public network using IP is ${curIP} which NIC is ${i}" | tee -a ${logFilePath}
		speed=$(ethtool ${i} | grep 'Speed:' | awk '{print $2}' | grep -o '[0-9]*')
		if [[ ${public_nic_speed} -gt ${speed} ]]; then
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: NIC's speed must be at least ${public_nic_speed}Mb/s, but ${i}'s speed is ${speed}Mb/s\e[0m" | tee -a ${errFilePath}
			continue
		else
			echo "[${hostname}] "$(${curDate})" INFO: NIC's speed is ${speed}Mb/s"
			funPing ${ceph_public_ips[@]}
		fi
	fi
done

#check & initial firewall
echo "[${hostname}] "$(${curDate})" INFO: ${DOUBPLET} Checking firewall ${DOUBPLET}" | tee -a ${logFilePath}
funCheckPort(){
	port=$(echo "$1" | egrep -o '[0-9]*-?[0-9]*')
	if [[ "$1" == `firewall-cmd --list-ports | grep -o "$1"` ]]; then
		echo "[${hostname}] "$(${curDate})" INFO: Firewall ports ${port} have been opened" | tee -a ${logFilePath}
	else
		echo "[${hostname}] "$(${curDate})" INFO: Opening Firewall ports ${port}" | tee -a ${logFilePath}
		echo "[${hostname}] "$(${curDate})" INFO: Open Firewall ports ${port} $(firewall-cmd --zone=public --add-port=$1 --permanent)" | tee -a ${logFilePath}
		echo "[${hostname}] "$(${curDate})" INFO: Firewall.service reload $(firewall-cmd --reload )" | tee -a ${logFilePath}
	fi
}

if [[ "running" == `firewall-cmd --state` ]]; then
	echo "[${hostname}] "$(${curDate})" INFO: Firewalld.service is running" | tee -a ${logFilePath}
	for i in `echo ${firewall_ports}`
	do
		funCheckPort ${i}/tcp
	done
else
	echo "[${hostname}] "$(${curDate})" INFO: Firewalld.service is not running" | tee -a ${logFilePath}
	echo "[${hostname}] "$(${curDate})" INFO: Firewalld.service is starting..." | tee -a ${logFilePath}
	systemctl start firewalld.service>/dev/null 2>&1
	echo "[${hostname}] "$(${curDate})" INFO: Firewalld.service is $(firewall-cmd --state)" | tee -a ${logFilePath}
	for i in `echo ${firewall_ports}`
	do
		funCheckPort ${i}/tcp
	done
fi

echo "[${hostname}] "$(${curDate})" INFO: ${DOUBPLET} The modified firewall information ${DOUBPLET}">>${logFilePath}
firewall-cmd --zone=public --list-all>>${logFilePath}

#ban SElinux
echo "[${hostname}] "$(${curDate})" INFO: ${DOUBPLET} Checking SElinux ${DOUBPLET}" | tee -a ${logFilePath}
cat /etc/sysconfig/selinux | grep -o "SELINUX=disabled">/dev/null 2>&1
if [[ "$?"  == "0" ]]; then
	echo "[${hostname}] "$(${curDate})" INFO: SElinux is disabled" | tee -a ${logFilePath}
else
	echo "[${hostname}] "$(${curDate})" INFO: Ban SElinux" | tee -a ${logFilePath}
	sed -i s'/SELINUX=enforcing/SELINUX=disabled'/g /etc/sysconfig/selinux>>${logFilePath}
fi

echo "[${hostname}] "$(${curDate})" INFO: Network-check is completed on machine ${hostname}." | tee -a ${logFilePath}
exit 0

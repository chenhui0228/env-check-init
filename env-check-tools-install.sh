#!/bin/bash
#
#This script is used to check system env
#version 1.0.0
#author chenhui
#data 2016-12-19

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"

#config file
conf_path=$(cd "$(dirname "$0")"; pwd)/cephenv-check.conf
ntpServers=$(cat ${conf_path} | grep "server =" | awk '{for(i=3;i<=NF;i++){print $i}}')
yums=$(cat ${conf_path} | grep "yumSources =" | awk '{for(i=3;i<=NF;i++){print $i}}')
kernel_version=$(cat ${conf_path} | grep "kernel_version" | awk -F " = " '{print $2}')
mon_var=$(cat ${conf_path} | grep "monVar" | awk -F " = " '{print $2}')

# log
logFolderPath=$(cat ${conf_path} | grep "logFolderPath" | awk -F " = " '{print $2}')
if [[ ! -d $logFolderPath ]]; then
        mkdir $logFolderPath
fi
logFilePath=${logFolderPath}/env-check-tools-install${logDate}.log
errFilePath=${logFolderPath}/env-check-tools-install-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

echo "[${hostname}] "$(${curDate})" INFO: System-check is starting to do on machine ${hostname}..." | tee ${logFilePath}
#echo "[${hostname}] "$(${curDate})" INFO: This is an error log for System-check on machine ${hostname}...">${errFilePath}


#kernel version check
version=$(cat /proc/version | awk '{print $3}')
kernelVersion=$(echo "${version}" | egrep -o "[0-9]*\.[0-9]*\.[0-9]*")
systemVersion=$(echo "${version}" | egrep -o "el7")
echo "[${hostname}] "$(${curDate})" INFO: Linux version is ${version}" | tee -a ${logFilePath}
if [[ "el7" == "${systemVersion}" && ("${kernelVersion}" > "${kernel_version}" || "${kernelVersion}" == "${kernel_version}") ]]; then
	echo "[${hostname}] "$(${curDate})" INFO: This liunx version can meet ssdcache installation needs" | tee -a ${logFilePath}
else
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Linux version can not meet ssdcache installation needs, at least require Linux version ${kernel_version}-xxx.el7.x86_64\e[0m" | tee -a ${errFilePath}
	exit 0
fi

# check /var volums for ceph
if [[ "" == `lsblk | grep $mon_var` ]]; then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Volums $mon_var for ceph not found\e[0m" | tee -a ${errFilePath}
else
	echo "[${hostname}] "$(${curDate})" INFO: Volums $mon_var for ceph is "`lsblk | grep $mon_var | awk '{print $1}' | grep -o '[A-Za-z0-9-]\{1,20\}'` | tee -a ${logFilePath}
fi

#yum config check
ls /etc/yum.repos.d/ | grep "repo$">>${logFilePath}
yum clean all>/dev/null 2>&1
funYumCheck(){
	for i in `echo ${yums[@]}`
	do
		yum list | grep -i "${i}">/dev/null 2>&1
		if [[ "$?" == "0" ]]; then
			rpm -qa | grep "${i}">/dev/null 2>&1
			if [[ "$?" == "0" ]]; then
				echo "[${hostname}] "$(${curDate})" INFO: ${i} already installed" | tee -a ${logFilePath}
			else
				echo "[${hostname}] "$(${curDate})" INFO: Yum repository for ${i} already configured" | tee -a ${logFilePath}
				#install tools with yum
                                echo "[${hostname}] "$(${curDate})" INFO: Installing ${i}" | tee -a ${logFilePath}
                                yum install ${i} -y>/dev/null 2>&1
			fi
		else
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Yum repository for ${i} not found, will lead to the next check & initialization failed, please configured first\e[0m" | tee -a ${errFilePath}
		fi
	done
}
funYumCheck

#sync time properly with ntp server
funSyncTime(){
	sed -i s'/server /#server '/g /etc/chrony.conf
	lastLine=$(cat /etc/chrony.conf | grep "server " | tail -1)
	for i in ${ntpServers[@]}
	do
		sed -i '/'"${lastLine}"'/a server '"${i}"' iburst' /etc/chrony.conf
	done
	systemctl restart chronyd
	chronyc sourcestats -v>>${logFilePath}
	echo "[${hostname}] "$(${curDate})" INFO: Time synchronization is complete" | tee -a ${logFilePath}
}
yum list | grep chrony | grep @base>/dev/null 2>&1
if [[ "$?" != "0" ]]; then
	echo "[${hostname}] "$(${curDate})" INFO: Install chrony" | tee -a ${logFilePath}
	yum -y install chrony>/dev/null 2>&1
fi
funSyncTime

echo "[${hostname}] "$(${curDate})" INFO: System-check is completed on machine ${hostname}." | tee -a ${logFilePath}

exit 0

#!/bin/bash
#
#This script is used to check memory env
#version 1.0.0
#author chenhui
#data 2016-12-19

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"

# config file
conf_path=$(cd "$(dirname "$0")"; pwd)/cephenv-check.conf
memory_warn=$(cat ${conf_path} | grep "memory_warn" | awk -F " = " '{print $2}')
# log
logFolderPath=$(cat ${conf_path} | grep "logFolderPath" | awk -F " = " '{print $2}')
if [[ ! -d $logFolderPath ]]; then
        mkdir $logFolderPath
fi
logFilePath=${logFolderPath}/memory-check${logDate}.log
errFilePath=${logFolderPath}/memory-check-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

echo "[${hostname}] "$(${curDate})" INFO: memory-check is starting to do on machine ${hostname}..." | tee ${logFilePath}

# check memory have errors or not
dmesg | grep "[a-zA-Z]emory" | grep error
if [[ "$?" == "0" ]]; then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Memory may be have some errors\e[0m" | tee -a ${errFilePath}
	dmesg | grep "[a-zA-Z]emory" | grep error | tee -a ${errFilePath}
fi

# check memory status
funMemCheck(){
	mem_total=$(free -m | grep "Mem" | awk '{print $2}')
	mem_used=$(free -m | grep "Mem" | awk '{print $3}')
	mem_free=$(free -m | grep "Mem" | awk '{print $4}')
	echo "[${hostname}] "$(${curDate})" INFO: Memory total size is $mem_total MB" | tee -a ${logFilePath}
	echo "[${hostname}] "$(${curDate})" INFO: Memory used size is $mem_used MB" | tee -a ${logFilePath}
	if [[ "0" != $mem_used ]]; then
		mem_per=`echo "scale=2;$mem_free/$mem_total" | bc`
		echo "[${hostname}] "$(${curDate})" INFO: Memory available is $mem_free MB, free percent "`echo "scale=2;${mem_per}*100" | bc`% | tee -a ${logFilePath}
	fi
	mem_now=`expr $mem_per \> $memory_warn`
	if [[ $mem_now == 0 ]]; then  
		# sync
		# echo 3 > /proc/sys/vm/drop_caches
		echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: Memory usage rate is too high\e[0m" | tee -a ${logFilePath}
	fi 
}
funMemCheck

echo "[${hostname}] "$(${curDate})" INFO: memory-check is completed on machine ${hostname}." | tee -a ${logFilePath}

exit 0

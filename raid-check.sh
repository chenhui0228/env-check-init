#!/bin/bash
#
#This script is used to check raid env
#version 1.0.0
#author chenhui
#data 2016-12-19

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"

# config file
conf_path=$(cd "$(dirname "$0")"; pwd)/cephenv-check.conf
raid_memory=$(cat ${conf_path} | grep "raid_memory" | awk -F " = " '{print $2}')
SSD_Prop=$(cat ${conf_path} | grep "SSD_Prop" | awk '{for(i=3;i<=NF;i++){print $i}}')
HDD_Prop=$(cat ${conf_path} | grep "HDD_Prop" | awk '{for(i=3;i<=NF;i++){print $i}}')
# log
logFolderPath=/var/log/cephenv
if [[ ! -d $logFolderPath ]]; then
        mkdir $logFolderPath
fi
logFilePath=${logFolderPath}/raid-check${logDate}.log
errFilePath=${logFolderPath}/raid-check-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

echo "[${hostname}] "$(${curDate})" INFO: raid-check is starting to do on machine ${hostname}..." | tee ${logFilePath}

# find RAID card
dmesg | grep -i RAID > /dev/null 2>&1
tmp=$?
cat /proc/scsi/scsi | grep -i raid > /dev/null 2>&1
if [[ "$?" != "0" && "$tmp" != "0" ]]; then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Could not found RAID card\e[0m" | tee -a ${errFilePath}
	exit 1
fi

# check Megacli is installed or not
rpm -qa | grep MegaCli>/dev/null 2>&1
if [[ "$?" != "0" ]]; then
	echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: MegaCli not found, please install first\e[0m" | tee -a ${errFilePath}
	echo "[${hostname}] "$(${curDate})" INFO: Installing MegaCli..." | tee -a ${logFilePath}
	yum -y install MegaCli>/dev/null 2>&1
	if [[ "$?" != "0" ]]; then
		echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: MegaCli can not install with yum\e[0m" | tee -a ${errFilePath}
		exit 1
	fi
	echo "[${hostname}] "$(${curDate})" INFO: MegaCli install success" | tee -a ${logFilePath}
fi

MegaCli=$(find /opt -name MegaCli64)
if [[ -z $MegaCli ]]; then
	MegaCli=$(which MegaCli)
fi

# check raid's BBU
BBUStatus=$($MegaCli -AdpBbuCmd -GetBbuStatus -aALL | grep "Exit Code:" | awk '{print $3}')
echo "[${hostname}] "$(${curDate})" INFO: Check RAID's BBU" | tee -a ${errFilePath}
if [[ "0x00" == $BBUStatus ]]; then
	echo "[${hostname}] "$(${curDate})" INFO: RAID's BBU is ok " | tee -a ${logFilePath}
else
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: RAID card may not have the battery protection, or the battery protection is bad, or the mechine is not support MegaCli\e[0m" | tee -a ${errFilePath}
	echo "[${hostname}] "$(${curDate})" INFO: $DOUBPLET Infomation for BBU $1 $DOUBPLET">>${errFilePath}
	$MegaCli -CfgDsply -aALL | grep -A 4 "Adapter:">>${errFilePath}
	$MegaCli -AdpBbuCmd -GetBbuStatus -aALL | grep -C 7 "BBU status for Adapter">>${errFilePath}
	$MegaCli -AdpBbuCmd -GetBbuStatus -aALL | grep -A 4 "Relative State of Charge:">>${errFilePath}
	echo "[${hostname}] "$(${curDate})" INFO: $DOUBPLET">>${errFilePath}
fi

# check raid's memory
echo "[${hostname}] "$(${curDate})" INFO: Check RAID's memory" | tee -a ${logFilePath}
memory=$($MegaCli -CfgDsply -aALL | grep "Memory" | grep -o "[0-9]\{1,4\}")
if [[ "" == $memory ]]; then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: MegaCli not supported on machine\e[0m" | tee -a ${errFilePath}
	exit
fi
if [[ "${raid_memory}" -gt $memory ]]; then
	echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: RAID's cache memory is ${memory}MB less then ${raid_memory}MB\e[0m" | tee -a ${errFilePath}
else 
	echo "[${hostname}] "$(${curDate})" INFO: RAID's cache memory is ${memory}MB" | tee -a ${logFilePath}
fi

# initialize raid parameters
diskTargetId_lists=$($MegaCli -CfgDsply -aALL | grep "Target Id:" | awk '{print $3}')
ssdTargetId_lists=$($MegaCli -CfgDsply -aALL | grep -B 57 "SSD" | grep "Target Id:" | awk '{print $3}')
ax=$($MegaCli -AdpAllInfo -aAll | grep ^"Adapter" | grep -o "[0-9]\{1,2\}")
echo "[${hostname}] "$(${curDate})" INFO: Initialize RAID parameters" | tee -a ${logFilePath}
for i in ${diskTargetId_lists[@]}
do
	enclosure=$($MegaCli -CfgDsply -aALL | grep -A 49 "Target Id: 19" | grep "Enclosure Device ID:" | awk '{print $4}')
	slot=$($MegaCli -CfgDsply -aALL | grep -A 49 "Target Id: 19" | grep "Slot Number:" | awk '{print $3}')
	if [[ `echo "${ssdTargetId_lists[@]}" | grep -w $i` ]]; then
		
		echo "[${hostname}] "$(${curDate})" INFO: Initialize RAID parameters" | tee -a ${logFilePath}
		# $MegaCli -CfgLdAdd -r0 [$enclosure:$slot] -a0 
		for j in ${SSD_Prop[@]}
		do
			$MegaCli -LDSetProp ${j} -L${i} -a0>/dev/null 2>&1
		done
	else
		for j in ${HDD_Prop[@]}
		do
			$MegaCli -LDSetProp ${j} -L${i} -a0>/dev/null 2>&1
		done
	fi
done
$MegaCli -LDGetProp -Cache -LALL -aALL>>${logFilePath}
echo "[${hostname}] "$(${curDate})" INFO: raid-check is completed on machine ${hostname}." | tee -a ${logFilePath}

exit 0

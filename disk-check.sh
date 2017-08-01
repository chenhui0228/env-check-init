#!/bin/bash
#
#This script is used to check disk
#version 1.0.0
#author chenhui
#data 2016-12-19

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"

# config file
conf_path=$(cd "$(dirname "$0")"; pwd)/cephenv-check.conf

#chec item
Power_On_Hours=$(cat ${conf_path} | grep "Power_On_Hours =" | awk '{print $3}')
Raw_Read_Error_Rate=$(cat ${conf_path} | grep "Raw_Read_Error_Rate =" | awk '{print $3}')
Write_Error_Rate=$(cat ${conf_path} | grep "Write_Error_Rate =" | awk '{print $3}')
# SSD INFO
Device_Model=$(cat ${conf_path} | grep "Device_Model" | awk -F " = " '{print $2}')
User_Capacity_SSD=$(cat ${conf_path} | grep "User_Capacity_SSD" | awk -F " = " '{print $2}')
# HDD INFO
Product=$(cat ${conf_path} | grep "Product" | awk -F " = " '{print $2}')
Revision=$(cat ${conf_path} | grep "Revision" | awk -F " = " '{print $2}')
User_Capacity_HDD=$(cat ${conf_path} | grep "User_Capacity_HDD" | awk -F " = " '{print $2}')

# log
logFolderPath=$(cat ${conf_path} | grep "logFolderPath" | awk -F " = " '{print $2}')
if [[ ! -d $logFolderPath ]]; then
        mkdir $logFolderPath
fi
logFilePath=${logFolderPath}/disk-check${logDate}.log
errFilePath=${logFolderPath}/disk-check-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

echo "[${hostname}] "$(${curDate})" INFO: disk-check is starting to do on machine ${hostname}..." | tee ${logFilePath}

# check tools is install or not
funCheckTools(){
	rpm -qa | grep $1>/dev/null 2>&1
	if [[ "$?" != "0" ]]; then
		echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: $1 not found, please install first\e[0m" | tee -a ${errFilePath}
		echo "[${hostname}] "$(${curDate})" INFO: Installing $1..." | tee -a ${logFilePath}
		yum -y install $1>/dev/null 2>&1
		if [[ "$?" != "0" ]]; then
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: $1 can not install with yum\e[0m" | tee -a ${errFilePath}
			exit 1
		fi
		echo "[${hostname}] "$(${curDate})" INFO: $1 install success" | tee -a ${logFilePath}
	fi
}

funCheckTools smartmontools
funCheckTools MegaCli
funCheckTools lsscsi

which MegaCli>/dev/null 2>&1
if [[ $? -eq 0 ]]; then
	megacli="$(which MegaCli) -CfgDsply -aALL"
else
	megacli="/opt/MegaRAID/MegaCli/MegaCli64 -CfgDsply -aALL"
fi

diskDevices=$(smartctl --scan | grep "sd" | awk '{print $1}')
megaraids=$(smartctl --scan | grep "mega" | awk '{print $3}')
device_ids=$($megacli | grep -E 'Device Id:' | awk '{print $3}' | sort)

# check disk health status
funCheckDisk(){
	device_id=$1
	ldev=$2
	if [[ x"${Power_On_Hours}" == x ]]; then PowerUpHours=1000; else PowerUpHours=$Power_On_Hours; fi
	serial_no=$(smartctl -i -d megaraid,$device_id $ldev | grep "Serial number:" |awk '{print $3}')
	smartctl -H -d megaraid,$device_id $ldev | grep "SMART Health Status: OK">>/dev/null 2>&1
	curStats=$?
	smartctl -H -d megaraid,$device_id $ldev | grep "SMART overall-health self-assessment test result: PASSED">>/dev/null 2>&1
	if [[ "$?" == "0" || $curStats == "0" ]]; then
		echo "[${hostname}] "$(${curDate})" INFO: Device megaraid,$device_id $ldev's health status is OK" | tee -a ${logFilePath}
		
		# check power up hours
		curPowerUpHours=$(smartctl -a -d megaraid,$device_id $ldev | grep "hours powered up" | awk '{print $7}')
		if [[ -z $curPowerUpHours ]];then
			curPowerUpHours=$(smartctl -a -d megaraid,$device_id $ldev | grep "Power_On_Hours" | awk '{print $10}')
		fi
		if [[ -z $curPowerUpHours ]];then
			return
		elif [[ `echo "${curPowerUpHours} > ${PowerUpHours}" | bc` -eq 1 ]]; then
				smart_type=$(smartctl -a -d megaraid,$device_id $ldev | grep "Power_On_Hours" | awk '{print $7}')
				if [[ -z smart_type ]];then
					smart_type="Old_age"
				fi
				echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: Device megaraid,$device_id $ldev not a new device and is $smart_type, has been used ${curPowerUpHours} hours\e[0m" | tee -a ${errFilePath}
		fi
		# check Raw_Read_Error_Rate
		curRawReadErrorRate=$(smartctl -a -d megaraid,$device_id $ldev | grep "Read_Error_Rate" | awk '{print $10}')
		if [[ -z $curRawReadErrorRate ]];then
			return
		elif [[ `echo "${curRawReadErrorRate} < ${Raw_Read_Error_Rate}" | bc` -eq 1 ]];then
		smart_type=$(smartctl -a -d megaraid,$device_id $ldev | grep "Read_Error_Rate" | awk '{print $7}')
			echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: Device megaraid,$device_id $ldev's Raw_Read_Error_Rate is ${curRawReadErrorRate}, it is $smart_type\e[0m" | tee -a ${errFilePath}
		fi
		# check Write_Error_Rate
		curWriteErrorRate=$(smartctl -a -d megaraid,$device_id $ldev | grep "Write_Error_Rate" | awk '{print $10}')
		if [[ -z $curRawReadErrorRate ]];then
			return
		elif [[ `echo "${curRawReadErrorRate} < ${Write_Error_Rate}" | bc` -eq 1 ]];then
		smart_type=$(smartctl -a -d megaraid,$device_id $ldev | grep "Write_Error_Rate" | awk '{print $7}')
			echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: Device megaraid,$device_id $ldev's Raw_Read_Error_Rate is ${curRawReadErrorRate}, it is $smart_type\e[0m" | tee -a ${errFilePath}
		fi
	else
		echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Device megaraid,$device_id $ldev's health status is not OK, it may not work, please timely disk replacement\e[0m" | tee -a ${errFilePath}
		echo "[${hostname}] "$(${curDate})" INFO: $DOUBPLET Infomation for device megaraid,$device_id $ldev $DOUBPLET">>${errFilePath}
		smartctl -d $i -H /dev/sda | grep "SMART Health Status:">>${errFilePath}
		smartctl -d $1 -a /dev/sda | grep -A 9 "[E|e]rror">>${errFilePath}
		$megacli | grep -B 25 $serial_no | grep "Physical Disk:" | awk '{printf ("%-22s%s\n", "Physical Disk:",$NF)}'>>${errFilePath}
		$megacli | grep -B 25 $serial_no | grep "Enclosure Device ID:" | awk '{printf ("%-22s%s\n", "Enclosure Device ID:",$NF)}'>>${errFilePath}
		$megacli | grep -B 25 $serial_no | grep "Slot Number:" | awk '{printf ("%-22s%s\n", "Slot Number:",$NF)}'>>${errFilePath}
		$megacli | grep -B 25 $serial_no | grep "Device Id:" | awk '{printf ("%-22s%s\n", "Device Id:",$NF)}'>>${errFilePath}
		smartctl -i -d $1 /dev/sda | grep -A 15  "START OF INFORMATION SECTION" | grep -v "START OF INFORMATION SECTION">>${errFilePath}
		smartctl -a -d $1 /dev/sda | grep "hours powered up" | awk '{printf ("%-22s%s\n"), "Power Up Hours:",$NF}'>>${errFilePath}
		smartctl -d $1 -a /dev/sda | grep -A 9 "[E|e]rror">>${errFilePath}
		echo "[${hostname}] "$(${curDate})" INFO: $DOUBPLET">>${errFilePath}
	fi
}

checkModelInfo(){
	device_id=$1
	ldev=$2
	smartctl -i -d megaraid,$device_id $ldev | grep "${Device_Model}">/dev/null 2>&1
	if [[ "$?" == "0" ]];then
		curCapacity=$(smartctl -i -d megaraid,$device_id $ldev | grep -o "${User_Capacity_SSD}")
		if [[ $curCapacity != $User_Capacity_SSD ]];then
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Device megaraid,$device_id $ldev device model is ${Device_Model}, user capacity is ${curCapacity} not match your config ${User_Capacity_SSD}\e[0m" | tee -a ${errFilePath}
			return
		else
			echo "[${hostname}] "$(${curDate})" INFO: Device megaraid,$device_id $ldev device model is ${Device_Model}, user capacity is ${curCapacity}" | tee -a ${logFilePath}
		fi
	else
		smartctl -i -d megaraid,$device_id $ldev | grep "${Product}">/dev/null 2>&1
		if [[ "$?" == "0" ]];then
			curCapacity=$(smartctl -i -d megaraid,$device_id $ldev | grep -o "${User_Capacity_HDD}")
			# curVendor=$(smartctl -i -d megaraid,$device_id $ldev | grep -o "${Vendor}")
			if [[ $curCapacity != $User_Capacity_HDD ]];then
				echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Device megaraid,$device_id $ldev device model is ${Product}, user capacity is ${curCapacity} not match your config ${User_Capacity_HDD}\e[0m" | tee -a ${errFilePath}
				return
			else
				echo "[${hostname}] "$(${curDate})" INFO: Device megaraid,$device_id $ldev device model is ${Product}, user capacity is ${curCapacity}" | tee -a ${logFilePath}
			fi
		else
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Device megaraid,$device_id $ldev device model is ${Product} not match your config ${User_Capacity_HDD}\e[0m" | tee -a ${errFilePath}
			return
		fi
	fi
	funCheckDisk $device_id $ldev
}

# check disk is supported SMART or not
funCheckSmart(){
	for device_id in ${device_ids[@]}
	do
		disk_group=$($megacli | grep -C 5 "Device Id: ${device_id}$" | grep "DiskGroup:" | awk '{print $4}' | grep -o '[0-9]\{1,2\}')
		ldev=$(lsscsi | awk '{print $1" "$NF}' | grep "/dev" | awk -F ":" '{print $3" "$4}' | awk '{print $1" "$3}' | grep ^"${disk_group} " | awk '{print $2}')
		smartctl -i -d megaraid,$device_id $ldev | grep "SMART support is" | grep Available>/dev/null 2>&1
		if [[ "$?" != "0" ]]; then
			echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: Device megaraid,$device_id $ldev does not support SMART\e[0m" | tee -a ${errFilePath}
		else
			smartctl -i -d megaraid,$device_id $ldev | grep "SMART support is" | grep Enabled>/dev/null 2>&1
			if [[ "$?" != "0" ]]; then
				echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: Device megaraid,$device_id $ldev does not open SMART\e[0m" | tee -a ${errFilePath}
				smartctl --smart=on --offlineauto=on --saveauto=on -d mageraid,$device_id $ldev>/dev/null 2>&1
				if [[ "$?" != "0" ]]; then
					echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Device megaraid,$device_id $ldev's SMART can not open\e[0m" | tee -a ${errFilePath}
					exit 1
				fi
			else
				checkModelInfo $device_id $ldev
			fi
		fi
	done
	
}

if [[ "" == `echo $megaraids` && "" != `echo $diskDevices` ]]; then
	echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: Megaraid device is not found\e[0m" | tee -a ${errFilePath}
	exit 1
elif [[ "" != `echo $megaraids` && "" != `echo $diskDevices` ]]; then
	funCheckSmart
else
	echo "[${hostname}] "$(${curDate})" INFO: No disk found" | tee -a ${logFilePath}
fi

echo "[${hostname}] "$(${curDate})" INFO: disk-check is completed on machine ${hostname}." | tee -a ${logFilePath}

exit 0

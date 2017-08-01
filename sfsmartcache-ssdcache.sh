#!/bin/bash
#
#This script is used to install ssdcache

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"
module="sfsmartcache"
kernel_source_version=$(uname -r)
sfsmartcachemod=/lib/modules/`uname -r`/extra/sfsmartcache/sfsmartcache.ko

# sf-ssdcache package file path
ssdcache_path=/root/sf-ssdcache-1.0.0

# ssdcache mapping config file path
ssdcache_map_conf=$(cd "$(dirname "$0")"; pwd)/hdd-ssd-map.log

# log
logFolderPath=/var/log/cephenv
if [[ ! -d $logFolderPath ]]; then
        mkdir $logFolderPath
fi
logFilePath=${logFolderPath}/sfsmartcache-ssdcache${logDate}.log
errFilePath=${logFolderPath}/sfsmartcache-ssdcache-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

if [[ ! -d $ssdcache_path ]];then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Ssdcache install package is not found\e[0m" | tee -a ${errFilePath}
fi

sfsc=`sfsc_cli info`
if [[ $? -eq 0 ]];then
	if [[ $1 != "install" ]]; then
		opt=$1
	else
		echo "[${hostname}] "$(${curDate})" INFO: sfsmartcache have installed" | tee ${logFilePath}
		opt=""
	fi
else
	opt=install
fi

# check sfsmartcache status 
funStatus(){
	if [[ `lsmod | grep -o ^$module` ]];then
		echo "[${hostname}] "$(${curDate})" INFO: sfsmartcache is up" | tee -a ${logFilePath}
	else
		echo "[${hostname}] "$(${curDate})" INFO: sfsmartcache is down" | tee -a ${logFilePath}
		exit
	fi
	if [[ ! -f $sfsmartcachemod ]]; then
		echo "[${hostname}] "$(${curDate})" INFO: sfsmartcache not installed" | tee -a ${logFilePath}
		exit
	fi
}

# create ssdcache
funCreateSSDCache(){
	ssdcache_maps=$(cat $ssdcache_map_conf | grep "ssdcacheMapping =" | awk '{for(i=3;i<=NF;i++){print $i}}')
	ssdcache_seq=0
	if [[ "" == `echo ${ssdcache_maps[@]}` ]]; then
		echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Partition for ssdcache is not found,please create partition for ssdcache\e[0m" | tee -a ${errFilePath}
		exit
	fi
	for i in ${ssdcache_maps[@]}
	do 
		data_dev=`echo ${i} | awk -F ":" '{print $1}'`
		ssdcache_dev=`echo ${i} | awk -F ":" '{print $2}'`
		ssdcache_seq=`expr $ssdcache_seq + 1`
		echo "[${hostname}] "$(${curDate})" INFO: Create cache disk cachedisk${ssdcache_seq} for data disk ${data_dev} ssd disk ${ssdcache_dev} " | tee ${logFilePath}
		sfsc_cli info | grep "Source Device" | grep $data_dev>/dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Source device date disk ${data_dev} is already created\e[0m" | tee -a ${errFilePath}
			continue
		fi
		sfsc_cli info | grep "SSD Device" | grep $ssdcache_dev>/dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: SSD device ssd disk partition ${ssdcache_dev} is already created\e[0m" | tee -a ${errFilePath}
			continue
		fi
		sfsc_cli create -d /dev/${data_dev} -s /dev/${ssdcache_dev} -m wb -c cachedisk${ssdcache_seq}>>${logFilePath}
		sleep 1
		stats=$(sfsc_cli info | grep -A 7 cachedisk${ssdcache_dev} | tail -1f | awk '{print $3}')
		if [[ "normal" == "${stats}" ]]; then
			echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Cache disk cachedisk${ssdcache_seq} has an error\e[0m" | tee -a ${errFilePath}
			cat /proc/sfsmartcache/cachedisk${ssdcache_dev}/errors>>${errFilePath}
		else
			echo "[${hostname}] "$(${curDate})" INFO: Cache disk cachedisk${ssdcache_seq} create success" | tee -a ${logFilePath}
		fi
	done
}

case "$opt" in
	install)
		echo "[${hostname}] "$(${curDate})" INFO: sfsmartcache installing..." | tee ${logFilePath}
		chmod 700 ${ssdcache_path}/CLI/sfsc_cli*
		cp ${ssdcache_path}/CLI/sfsc_cli /sbin/
		cp ${ssdcache_path}/CLI/sfsc_cli.8 /usr/share/man/man8
		mkdir -p /lib/modules/${kernel_source_version}/extra/sfsmartcache/
		install -o root -g root -m 0755 -d /lib/modules/${kernel_source_version}/extra/sfsmartcache/
		install -o root -g root -m 0755 ${ssdcache_path}/Driver/enhanceio/sfsmartcache.ko /lib/modules/${kernel_source_version}/extra/sfsmartcache/
		install -o root -g root -m 0755 ${ssdcache_path}/Driver/enhanceio/sfsmartcache_rand.ko /lib/modules/${kernel_source_version}/extra/sfsmartcache/
		install -o root -g root -m 0755 ${ssdcache_path}/Driver/enhanceio/sfsmartcache_rand.ko /lib/modules/${kernel_source_version}/extra/sfsmartcache/
		install -o root -g root -m 0755 ${ssdcache_path}/Driver/enhanceio/sfsmartcache_fifo.ko /lib/modules/${kernel_source_version}/extra/sfsmartcache/
		install -o root -g root -m 0755 ${ssdcache_path}/Driver/enhanceio/sfsmartcache_lru.ko /lib/modules/${kernel_source_version}/extra/sfsmartcache/
		depmod -a
		cd ${ssdcache_path}/Driver/enhanceio/
		modprobe sfsmartcache_fifo
		modprobe sfsmartcache_lru
		modprobe sfsmartcache_rand
		modprobe sfsmartcache
		echo "[${hostname}] "$(${curDate})" INFO: sfsmartcache install end" | tee -a ${logFilePath}
		;;
	uninstall)
		sfsc_cli info | grep "Cache Name">/dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			echo "ssdcache is in use, please remove it first"
			exit
		fi
		rmmod sfsmartcache_lru
       		rmmod sfsmartcache_fifo
        	rmmod sfsmartcache_rand
        	rmmod sfsmartcache
        	rm /sbin/sfsc_cli
		echo "[${hostname}] "$(${curDate})" INFO: sfsmartcache uninstalled" | tee -a ${logFilePath}
		exit 0
		;;
	status)
		funStatus
		exit 0
		;;
	create)
		funStatus
        funCreateSSDCache
		exit 0
		;;
	remove)
		echo "[${hostname}] "$(${curDate})" WARNING: You will delete ssdcache ,which would be already used" | tee -a ${logFilePath}
		endssdcacheseq=`ls /proc/sfsmartcache/ | grep cachedisk | tail -1 | grep -o '[0-9]\{1,2\}'`
		if [[ -z $endssdcacheseq ]]; then
			echo -e "\e[1;33m[${hostname}] "$(${curDate})" WARNING: SSD cache is not found\e[0m" | tee -a ${logFilePath}
			exit
		fi
		for i in `seq 1 $endssdcacheseq`
		do
			sfsc_cli delete -c cachedisk${i} | tee -a ${logFilePath}
		done
		exit 0
		;;
	list)
		ls -l /proc/sfsmartcache/ | grep 'cachedisk' | awk '{print $9}'
		exit 0
		;;
	*)
		echo $"Usage: $0 {install|uninstall|status|create|remove|list}"
		exit 1
esac
echo "[${hostname}] "$(${curDate})" INFO: ssdcache-install is completed on machine ${hostname}." | tee -a ${logFilePath}

exit 0

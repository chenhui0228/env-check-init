#!/bin/bash
#
#This script is used to part disk
#version 1.0.0
#author chenhui
#data 2016-12-19

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"

# config file
conf_path=$(cd "$(dirname "$0")"; pwd)/cephenv-check.conf
part_conf=$(cd "$(dirname "$0")"; pwd)/parted.conf
hdd_ssd_map_log=$(cd "$(dirname "$0")"; pwd)/hdd-ssd-map.log

# log
logFolderPath=$(cat ${conf_path} | grep "logFolderPath" | awk -F " = " '{print $2}')
if [[ ! -d $logFolderPath ]]; then
        mkdir $logFolderPath
fi
logFilePath=${logFolderPath}/disk-partition${logDate}.log
errFilePath=${logFolderPath}/disk-partition-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

slot_num=$(cat ${part_conf} | grep "slot_number =" | awk '{print $3}')
# hdd_list=$(cat ${part_conf} | grep "hdd_list" | awk '{for(i=1;i<=NF;i++){print $i}}' | grep "${hostname}:" | awk -F ":" '{print $2}')
# ssd_list=$(cat ${part_conf} | grep "ssd_list" | awk '{for(i=1;i<=NF;i++){print $i}}' | grep "${hostname}:" | awk -F ":" '{print $2}')
hdd_list=$(cat ${part_conf} | grep "hdd_list =" | awk '{print $3}')
ssd_list=$(cat ${part_conf} | grep "ssd_list =" | awk '{print $3}')
ssdcache_only=$(cat ${part_conf} | grep "ssdcache_only =" | awk '{print $3}')
dj=$(cat ${part_conf} | grep "dj =" | awk '{print $3}')
journal_size=$(cat ${part_conf} | grep "journal_size" | awk '{print $3}')
ssdcache_min_size=$(cat ${part_conf} | grep "ssdcache_min_size" | awk '{print $3}')
ssd_num=$(echo $ssd_list | awk -F "," '{print NF}')
hdd_num=$slot_num
start_line_num=$(expr `cat $hdd_ssd_map_log | grep -n ^"# disk mapping" | grep -o '[0-9]*'` + 1)
sed -i "${start_line_num},\$d" $hdd_ssd_map_log

echo "[${hostname}] "$(${curDate})" INFO: disk-partition is starting to do on machine ${hostname}..." | tee ${logFilePath}

if [[ $hdd_num == "0" ]]; then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: No disk found, must have disk\e[0m" | tee -a ${errFilePath}
	exit
fi

if [[ $ssd_num == "0" ]]; then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: No ssd found\e[0m" | tee -a ${errFilePath}
	exit
fi

if [[ $slot_num == "0" ]]; then
	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Machine slot is 0, it is not allowed\e[0m" | tee -a ${errFilePath}
	exit
fi

echo "[${hostname}] "$(${curDate})" INFO: Number of HDD is $hdd_num, Number of SSD is $ssd_num " | tee -a ${logFilePath}
hdd_devs=$(echo $hdd_list | awk -F "," '{for(i=1;i<=NF;i++){print $i}}')
ssd_devs=$(echo $ssd_list | awk -F "," '{for(i=1;i<=NF;i++){print $i}}')
ssd_partition_count=$(expr $hdd_num / $ssd_num)
ssdLast_partition_count=$ssd_partition_count
tmpTotal=$(expr $ssd_num \* $ssd_partition_count)
if [[ $tmpTotal != $hdd_num ]];then
	ssd_partition_count=$(expr $ssd_partition_count + 1)
	ssdLast_partition_count=$(expr $ssd_partition_count - $hdd_num + $tmpTotal)
fi

partition_flag=0

# remove partitions on disk
funRmdPartition(){
	for i in $@
	do
		disk_partition_count=$(parted /dev/${i} print | tail -2f | awk '{print $1}' | grep '[0-9]\{1,2\}')
		if [[ -z $disk_partition_count ]];then
			disk_partition_count=0
		fi
		while (( $disk_partition_count>0  ))
		do
			echo "[${hostname}] "$(${curDate})" INFO: Remove partition $disk_partition_count on /dev/${i}" | tee -a ${logFilePath}
			parted /dev/${i} -s rm $disk_partition_count>>${logFilePath}
			sleep 1
			disk_partition_count=`expr $disk_partition_count - 1`
		done
		partprobe /dev/${i}>/dev/null 2>&1
		partition_num=$(lsblk | grep ${i}${disk_partition_count} | awk '{print $1}' | grep -o '[0-9]\{1,2\}')
		devs=$(lsblk | grep ${i} | awk '{print $1}' | grep -o '[0-9]\{1,2\}')
                if [[ "" != $devs ]]; then
                       	echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Partition(s) `echo $devs` on /dev/${i} has been written, but we have been unable to inform the kernel of the change, probably because it/they are in use\e[0m" | tee -a ${errFilePath}
						exit
                fi
		partition_map=$(cat $hdd_ssd_map_log | grep "journalMapping = ")
		partition_map_byuuid=$(cat $hdd_ssd_map_log | grep "journalMappingByuuid = ")
		sed -i "s/${partition_map}/journalMapping = /g" $hdd_ssd_map_log
		sed -i "s/${partition_map_byuuid}/journalMappingByuuid = /g" $hdd_ssd_map_log
		partition_map=$(cat $hdd_ssd_map_log | grep "ssdcacheMapping = ")
		partition_map_byuuid=$(cat $hdd_ssd_map_log | grep "ssdcacheMappingByuuid = ")
		sed -i "s/${partition_map}/ssdcacheMapping = /g" $hdd_ssd_map_log
		sed -i "s/${partition_map_byuuid}/ssdcacheMappingByuuid = /g" $hdd_ssd_map_log
	done
}

# format diskette & make file system on hdds
funMklabelGPT(){
	for i in $@
	do
		parted /dev/${i} -s mklabel gpt>/dev/null 2>&1
		# parted /dev/${i} -s mkpart primary xfs 0GB 100%>/dev/null 2>&1
		partprobe /dev/${i}>/dev/null 2>&1
		mkfs.xfs -f /dev/${i}>/dev/null 2>&1
	done
}

# make partitions for ssdcache or journal on disk, then add journal and ssdcache partition mapping to config file part.conf
funMkPartition(){
	start_index=0
	end_index=0
	flag=$partition_flag
	if [[ $flag -eq 0 ]]; then
		partition_map=$(cat $hdd_ssd_map_log | grep "journalMapping = ")
		partition_map_byuuid=$(cat $hdd_ssd_map_log | grep "journalMappingByuuid = ")
		sed -i "s/${partition_map}/journalMapping = /g" $hdd_ssd_map_log
		sed -i "s/${partition_map_byuuid}/journalMappingByuuid = /g" $hdd_ssd_map_log
		partition_map=$(cat $hdd_ssd_map_log | grep "journalMapping = ")
		partition_map_byuuid=$(cat $hdd_ssd_map_log | grep "journalMappingByuuid = ")
	else
		partition_map=$(cat $hdd_ssd_map_log | grep "ssdcacheMapping = ")
		partition_map_byuuid=$(cat $hdd_ssd_map_log | grep "ssdcacheMappingByuuid = ")
		sed -i "s/${partition_map}/ssdcacheMapping = /g" $hdd_ssd_map_log
		sed -i "s/${partition_map_byuuid}/ssdcacheMappingByuuid = /g" $hdd_ssd_map_log
		partition_map=$(cat $hdd_ssd_map_log | grep "ssdcacheMapping = ")
		partition_map_byuuid=$(cat $hdd_ssd_map_log | grep "ssdcacheMappingByuuid = ")
	fi
	mid_value=1
	curLoop=0
	for i in $@
	do
		unit=$(parted /dev/${i} print | grep "Disk /" | awk '{print $3}' | grep -o '[A-Za-z]\{1,2\}')
		disk_total_size=$(parted /dev/${i} unit GB print | grep "Disk /" | awk '{print $3}' | grep -o '[0-9.]\{1,5\}')
		partition_num=$(parted /dev/${i} print | tail -2f | awk '{print $1}' | grep '[0-9]\{1,2\}')
		start_size=$(parted /dev/${i} unit GB print | tail -2f | awk '{print $3}' | grep -o '[0-9.]\{1,5\}')
		curLoop=$(expr $curLoop + 1)
		if [[ $curLoop == $ssd_num ]];then
			ssd_partition_count=$ssdLast_partition_count
		fi
		if [[ -z $start_size ]];then
			start_size=0
		fi
		if [[ -z $partition_num ]];then
			partition_num=0
		fi
		available_max_size=$(awk -v value1=$disk_total_size 'BEGIN{print value1*0.8}')
		if [[ $flag -eq 0 ]]; then
			requirement_size=$(awk -v value1=$ssd_partition_count -v value2=$journal_size 'BEGIN{print value1*value2}')
			if [[ `echo "$start_size > $available_max_size" | bc` -eq 1 || `echo "$requirement_size > $available_max_size" | bc` -eq 1 ]]; then
				echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Disk /dev/${i} size is insufficient\e[0m" | tee -a ${errFilePath}
				exit
			fi
			increment_size=$journal_size
			parted /dev/${i} -s mklabel gpt>/dev/null 2>&1
		else
			if [[ `echo "$start_size > $available_max_size" | bc` -eq 1 ]]; then
				echo -e "\e[1;31m[${hostname}] "$(${curDate})" ERROR: Disk /dev/${i} size is insufficient\e[0m" | tee -a ${errFilePath}
				exit
			fi
			increment_size=$(awk -v total=$disk_total_size -v used=$start_size -v count=$ssd_partition_count 'BEGIN{print (total-used)*0.8/count}')
		fi
		end_size=$(awk -v value1=$start_size -v value2=$increment_size 'BEGIN{print value1+value2}')
		current_partition_count=$ssd_partition_count
		partition_start_num=`echo "${partition_num} + 1" | bc`
		while (( $current_partition_count>0  ))
		do
			if [[ $flag -eq 0 ]]; then
				echo "[${hostname}] "$(${curDate})" INFO: Make partition ${current_partition_count} on /dev/${i} for journal" | tee -a ${logFilePath}
			else
				echo "[${hostname}] "$(${curDate})" INFO: Make partition "`echo "${current_partition_count}+${ssd_partition_count}" | bc`" on /dev/${i} for ssdcache " | tee -a ${logFilePath}
			fi
			parted /dev/${i} -s mkpart primary xfs ${start_size}${unit} ${end_size}${unit}>/dev/null 2>&1
			partprobe /dev/${i}>/dev/null 2>&1
			start_size=$end_size
			end_size=$(awk -v value1=$start_size -v value2=$increment_size 'BEGIN{print value1+value2}')
			current_partition_count=`expr $current_partition_count - 1`
		done
		partprobe>/dev/null 2>&1		
		# hdd,ssd mapping ralation
		hdds=($hdd_devs)
		end_index=`echo "${ssd_partition_count} * ${mid_value} - 1" | bc`
		k=0
		#set -x
                for j in `seq $start_index $end_index`
		do
			current_partition_num=`echo "${k}+${partition_start_num}" | bc`
			if [[ ${hdds[$j]} != "" ]];then
			        hdd_uuid=`blkid /dev/${hdds[$j]} | awk '{print $2}' | awk -F "=" '{print $2}' | grep -o '[^\"]*'`
                                #echo "hdd_uuid : $hdd_uuid | hdd : ${hdds[$j]}"
				#hdd_uuid=`ls -l /dev/disk/by-uuid/ | grep "${hdds[$j]}" | awk '{print $9}'`
				#ssd_partuuid=`ls -l /dev/disk/by-partuuid/ | grep "${i}${current_partition_num}" | awk '{print $9}'`
                                ssd_partuuid=`blkid /dev/${i}${current_partition_num} | awk '{print $3}' | awk -F "=" '{print $2}' | grep -o '[^\"]*'`
				partition_map=${partition_map}${hdds[$j]}:${i}${current_partition_num}" "
                                #echo "hdd_uuid : $ssd_partuuid | ssd : ${i}${current_partition_num}"
				#if [[ $hdd_uuid != "" && $ssd_partuuid != "" ]]; then
				#	partition_map_byuuid=${partition_map_byuuid}${hdd_uuid}:${ssd_partuuid}" "
				#	echo "${hdd_uuid} -> ${hdds[$j]}">>${hdd_ssd_map_log}
				#	echo "${ssd_partuuid} -> ${i}${current_partition_num}">>${hdd_ssd_map_log}
				#fi
				#echo "${hdd_uuid} : ${ssd_partuuid}"
				while [[ $hdd_uuid == "" ]]
				do
					echo "$start_index | $end_index | j=$j  | ${hdds[$j]} | $hdd_uuid | $ssd_partuuid | 1212000"
					#hdd_uuid=`ls -l /dev/disk/by-uuid/ | grep "${hdds[$j]}" | awk '{print $9}'`
                                        hdd_uuid=`blkid /dev/${hdds[$j]} | awk '{print $2}' | awk -F "=" '{print $2}' | grep -o '[^\"]*'`
				done
				while [[ $ssd_partuuid == "" ]]
				do
                                	#ssd_partuuid=`ls -l /dev/disk/by-partuuid/ | grep "${i}${current_partition_num}" | awk '{print $9}'`
					#echo "$start_index | $end_index | ${hdds[$j]} | $hdd_uuid | $ssd_partuuid | 12121111"
                                        ssd_partuuid=`blkid /dev/${i}${current_partition_num} | awk '{print $3}' | awk -F "=" '{print $2}' | grep -o '[^\"]*'`
				done
				#echo "$start_index | $end_index | ${hdds[$j]} | $hdd_uuid | $ssd_partuuid | 12124444"
				#echo "${hdd_uuid} : ${ssd_partuuid}"
				partition_map_byuuid=${partition_map_byuuid}${hdd_uuid}:${ssd_partuuid}" "
				echo "${hdd_uuid} -> ${hdds[$j]}">>${hdd_ssd_map_log}
				echo "${ssd_partuuid} -> ${i}${current_partition_num}">>${hdd_ssd_map_log}
			fi
			k=`expr ${k} + 1`
		done
                #set +x
		start_index=`expr $start_index + $ssd_partition_count`
		mid_value=`expr $mid_value + 1`
	done
	if [[ $flag -eq 0 ]]; then
		sed -i "s/journalMapping = /${partition_map}/g" $hdd_ssd_map_log
		sed -i "s/journalMappingByuuid = /${partition_map_byuuid}/g" $hdd_ssd_map_log
	else
		sed -i "s/ssdcacheMapping = /${partition_map}/g" $hdd_ssd_map_log
		sed -i "s/ssdcacheMappingByuuid = /${partition_map_byuuid}/g" $hdd_ssd_map_log
	fi
	
}

if [[ $ssdcache_only -eq 0 ]]; then
	echo "[${hostname}] "$(${curDate})" INFO: Parted for journal and ssdcache" | tee ${logFilePath}
	echo "[${hostname}] "$(${curDate})" INFO: If disk was parted, remove partitions first" | tee ${logFilePath}
	funRmdPartition ${hdd_devs[@]}
	funRmdPartition ${ssd_devs[@]}
	funMklabelGPT ${hdd_devs[@]}
	partition_flag=0
	funMkPartition ${ssd_devs[@]}
	partition_flag=1
	funMkPartition ${ssd_devs[@]}
elif [[ $ssdcache_only -eq 1 ]]; then
	echo "[${hostname}] "$(${curDate})" INFO: Parted for ssdcache" | tee ${logFilePath}
	partition_flag=1
	funMkPartition ${ssd_devs[@]}
elif [[ $ssdcache_only -eq 9999 ]]; then
        echo "[${hostname}] "$(${curDate})" INFO: Remove disk partition" | tee ${logFilePath}
	funRmdPartition ${hdd_devs[@]}
        funRmdPartition ${ssd_devs[@]}
fi
echo "[${hostname}] "$(${curDate})" INFO: disk-partition is completed on machine ${hostname}." | tee -a ${logFilePath}

exit 0

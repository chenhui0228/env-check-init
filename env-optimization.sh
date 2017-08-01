#!/bin/sh
#
#This script is used to optimize environment

logDate=$(date +%Y%m%d)
curDate="date +%Y-%m-%d%t%H:%M:%S"

# config file
part_conf=$(cd "$(dirname "$0")"; pwd)/parted.conf


# log
logFolderPath=/var/log/sfcould-storage
if [[ ! -d $logFolderPath ]]; then
        mkdir $logFolderPath
fi
logFilePath=${logFolderPath}/disk-partition${logDate}.log
errFilePath=${logFolderPath}/disk-partition-error${logDate}.log
hostname=$(hostname)
MONGLINE="----------"
DOUBPLET="=========="

# 设置文件句柄数  
ulimit -n 102400    
ulimit -i 2066202    
# 配置limits.conf
echo "* soft core unlimited" >> /etc/security/limits.conf    
echo "* hard core unlimited" >> /etc/security/limits.conf    
echo "* soft nofile 102400" >> /etc/security/limits.conf    
echo "* hard nofile 131072" >> /etc/security/limits.conf    
# 配置sysctl.conf    
echo "net.ipv4.ip_local_port_range = 10000 65000" >> /etc/sysctl.conf    
echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.conf    
echo "net.ipv4.tcp_tw_recycle = 1" >> /etc/sysctl.conf    
echo "net.ipv4.tcp_fin_timeout = 30" >> /etc/sysctl.conf    
echo "net.ipv4.tcp_keepalive_time = 1800" >> /etc/sysctl.conf    
echo "net.ipv4.tcp_retries2 = 5" >> /etc/sysctl.conf    
echo "net.core.rmem_default = 1048576" >> /etc/sysctl.conf    
echo "net.core.rmem_max = 1048576" >> /etc/sysctl.conf    
echo "net.core.wmem_default = 262144" >> /etc/sysctl.conf    
echo "net.core.wmem_max = 262144" >> /etc/sysctl.conf    
echo "net.core.somaxconn = 1024" >> /etc/sysctl.conf    
echo "vm.min_free_kbytes = 3145728" >>/etc/sysctl.conf    
echo "kernel.pid_max = 4194303" >> /etc/sysctl.conf    
echo "vm.zone_reclaim_mode = 0" >> /etc/sysctl.conf

sysctl -p>/dev/null 2>&1

#set ulimit max open files
#ulimit -SHn 655350
#echo "ulimit -SHn 655350" >> /etc/rc.local

echo "*      soft     nofile   655350" >> /etc/security/limits.conf
echo "*      hard     nofile   655350" >> /etc/security/limits.conf
echo "export TCMALLOC_MAX_TOTAL_THREAD_CACHE_BYTES=134217728" >> /etc/profile
echo "export TCMALLOC_LARGE_ALLOC_REPORT_THRESHOLD=8589934592" >> /etc/profile

#close disk cache
#set disk sectors for prepare  read
#set queue length for disk read/write

node=`hostname`
ssd_list=$(cat ${part_conf} | grep "ssd_list" | awk '{for(i=1;i<=NF;i++){print $i}}' | grep "${hostname}:" | awk -F ":" '{print $2}')
hdd_list=$(cat ${part_conf} | grep "hdd_list" | awk '{for(i=1;i<=NF;i++){print $i}}' | grep "${hostname}:" | awk -F ":" '{print $2}')
hdd_num=`echo $hdd_list | awk -F "," '{print NF}'`
ssd_num=`echo $ssd_list | awk -F "," '{print NF}'`
#echo "........hdd:$hdd_num ssd:$ssd_num ............"

for hdd in `echo $hdd_list |awk -F "," '{for (k=1;k<=NF;k++){print $k}}'`;do
        hdd_dev=$hdd
#        echo ".....disk: $hdd_dev ......"
#        hdparm -W 0 /dev/$hdd_dev
        blockdev --setra 4096 /dev/$hdd_dev
        echo 1024 > /sys/block/${hdd_dev}/queue/nr_requests
        echo "deadline" > /sys/block/${hdd_dev}/queue/scheduler
	res=`hdparm -W 0 /dev/$hdd_dev`
done

for ssd in `echo $ssd_list |awk -F "," '{for (k=1;k<=NF;k++){print $k}}'`;do
        ssd_dev=$ssd
#        echo "..... ssd: $ssd_dev ......"
#        hdparm -W 0 /dev/$ssd_dev
        blockdev --setra 4096 /dev/$ssd_dev
        echo 1024 > /sys/block/${ssd_dev}/queue/nr_requests
        echo "noop" > /sys/block/${ssd_dev}/queue/scheduler
	res=`hdparm -W 0 /dev/$hdd_dev`
done

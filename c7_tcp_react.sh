#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

kernel_version=`uname -r | awk -F "-" '{print $1}'`

if [ ${kernel_version} = "5.9.6" ]; then
	mkdir /root/tcp
	cd /root/tcp
	if [[ -e /root/tcp/tcp_react_rc2.ko ]]; then
	insmod /root/tcp/tcp_react_rc2.ko
	sysctl -w net.ipv4.tcp_congestion_control=react_rc2
	else
		yum remove kernel-headers -y
		wget -O kernel-headers-c7.rpm https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-ml-headers-5.9.6-1.el7.elrepo.x86_64.rpm
		wget -O kernel-c7.rpm https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-ml-5.9.6-1.el7.elrepo.x86_64.rpm			
		wget -O kernel-devel-c7.rpm https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-ml-devel-5.9.6-1.el7.elrepo.x86_64.rpm
		yum install -y kernel-c7.rpm
		yum install -y kernel-headers-c7.rpm
		yum install -y kernel-devel-c7.rpm
		yum -y install centos-release-scl-rh
		yum -y install devtoolset-8-gcc make && source /opt/rh/devtoolset-8/enable && wget -O ./tcp_react_rc2.c https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcp_react_rc2.c && echo "obj-m:=tcp_react_rc2.o" > Makefile && make -C /lib/modules/$(uname -r)/build M=`pwd`
		insmod /root/tcp/tcp_react_rc2.ko
		sysctl -w net.ipv4.tcp_congestion_control=react_rc2
	fi
	cd
	exit 0
else
	wget -O kernel-c7.rpm https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-ml-5.9.6-1.el7.elrepo.x86_64.rpm	
	yum install -y kernel-c7.rpm
	grub2-mkconfig  -o   /boot/grub2/grub.cfg
	grub2-set-default 0
	echo -e "重启切换下内核，确认当前内核是5.9.6再运行本脚本"
fi	
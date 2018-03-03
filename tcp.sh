#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS 6+,Debian7+,Ubuntu12+
#	Description: BBR+BBR魔改版+Lotserver
#	Version: 1.1.0
#	Author: 千影
#	Blog: https://www.94ish.me/
#=================================================

sh_ver="1.1.0"
github="raw.githubusercontent.com/chiakge/Linux-NetSpeed/master"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

#安装BBR内核
installbbr(){
	kernel_version="4.11.8"
	if [[ "${release}" == "centos" ]]; then
		rpm --import http://${github}/bbr/${release}/RPM-GPG-KEY-elrepo.org
		yum install -y http://${github}/bbr/${release}/${version}/${bit}/kernel-ml-${kernel_version}.rpm
		yum remove -y kernel-headers
		yum install -y http://${github}/bbr/${release}/${version}/${bit}/kernel-ml-headers-${kernel_version}.rpm
		yum install -y http://${github}/bbr/${release}/${version}/${bit}/kernel-ml-devel-${kernel_version}.rpm
	elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
		mkdir bbr && cd bbr
		wget -N --no-check-certificate http://${github}/bbr/debian-ubuntu/linux-headers-${kernel_version}-all.deb
		wget -N --no-check-certificate http://${github}/bbr/debian-ubuntu/${bit}/linux-headers-${kernel_version}.deb
		wget -N --no-check-certificate http://${github}/bbr/debian-ubuntu/${bit}/linux-image-${kernel_version}.deb
	
		dpkg -i linux-headers-${kernel_version}-all.deb
		dpkg -i linux-headers-${kernel_version}.deb
		dpkg -i linux-image-${kernel_version}.deb
		cd .. && rm -rf bbr
	fi
	detele_kernel
	BBR_grub
	echo -e "${Tip} 重启VPS后，请重新运行脚本开启${Red_font_prefix}BBR/BBR魔改版${Font_color_suffix}"
	stty erase '^H' && read -p "需要重启VPS后，才能开启BBR/BBR魔改版，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "${Info} VPS 重启中..."
		reboot
	fi
}

#安装Lotserver内核
installlot(){
	if [[ "${release}" == "centos" ]]; then
		rpm --import http://${github}/lotserver/${release}/RPM-GPG-KEY-elrepo.org
		yum remove -y kernel-firmware
		yum install -y http://${github}/lotserver/${release}/${version}/${bit}/kernel-firmware-${kernel_version}.rpm
		yum install -y http://${github}/lotserver/${release}/${version}/${bit}/kernel-${kernel_version}.rpm
		yum remove -y kernel-headers
		yum install -y http://${github}/lotserver/${release}/${version}/${bit}/kernel-headers-${kernel_version}.rpm
		yum install -y http://${github}/lotserver/${release}/${version}/${bit}/kernel-devel-${kernel_version}.rpm
	elif [[ "${release}" == "ubuntu" ]]; then
		mkdir bbr && cd bbr
		wget -N --no-check-certificate http://${github}/lotserver/${release}/${bit}/linux-headers-${kernel_version}-all.deb
		wget -N --no-check-certificate http://${github}/lotserver/${release}/${bit}/linux-headers-${kernel_version}.deb
		wget -N --no-check-certificate http://${github}/lotserver/${release}/${bit}/linux-image-${kernel_version}.deb
	
		dpkg -i linux-headers-${kernel_version}-all.deb
		dpkg -i linux-headers-${kernel_version}.deb
		dpkg -i linux-image-${kernel_version}.deb
		cd .. && rm -rf bbr
	elif [[ "${release}" == "debian" ]]; then
		mkdir bbr && cd bbr
		wget -N --no-check-certificate http://${github}/lotserver/${release}/${bit}/linux-image-${kernel_version}.deb
	
		dpkg -i linux-image-${kernel_version}.deb
		cd .. && rm -rf bbr
	fi
	detele_kernel
	BBR_grub
	echo -e "${Tip} 重启VPS后，请重新运行脚本开启${Red_font_prefix}Lotserver${Font_color_suffix}"
	stty erase '^H' && read -p "需要重启VPS后，才能开启Lotserver，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "${Info} VPS 重启中..."
		reboot
	fi
}

#启用BBR
startbbr(){
	remove_all
	echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
	sysctl -p
	echo -e "${Info}BBR启动成功！"
}

#编译并启用BBR魔改
startbbrmod(){
	remove_all
	if [[ "${release}" == "centos" ]]; then
		yum install -y make gcc
		mkdir bbrmod && cd bbrmod
		wget -N --no-check-certificate https://raw.githubusercontent.com/chiakge/tcp_nanqinlang-test/master/tcp_nanqinlang.c
		echo "obj-m := tcp_nanqinlang.o" > Makefile
		make -C /lib/modules/$(uname -r)/build M=`pwd` modules CC=/usr/bin/gcc
		chmod +x ./tcp_nanqinlang.ko
		cp -rf ./tcp_nanqinlang.ko /lib/modules/$(uname -r)/kernel/net/ipv4
		insmod tcp_tsunami.ko
		depmod -a
	else
		apt-get update
		if [[ "${release}" == "ubuntu" && "${version}" = "14" ]]; then
			apt-get -y install build-essential
			apt-get -y install software-properties-common
			add-apt-repository ppa:ubuntu-toolchain-r/test -y
			apt-get update
		fi
		apt-get -y install make gcc-4.9
		mkdir bbrmod && cd bbrmod
		wget -N --no-check-certificate https://raw.githubusercontent.com/chiakge/tcp_nanqinlang-test/master/tcp_nanqinlang.c
		echo "obj-m := tcp_nanqinlang.o" > Makefile
		make -C /lib/modules/$(uname -r)/build M=`pwd` modules CC=/usr/bin/gcc-4.9
		install tcp_nanqinlang.ko /lib/modules/$(uname -r)/kernel
		cp -rf ./tcp_nanqinlang.ko /lib/modules/$(uname -r)/kernel/net/ipv4
		depmod -a
	fi
	

	echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
	echo "net.ipv4.tcp_congestion_control=nanqinlang" >> /etc/sysctl.conf
	sysctl -p
	echo -e "${Info}魔改版BBR启动成功！"
}

#启用Lotserver
startlotserver(){
	remove_all
	wget --no-check-certificate -O appex.sh https://raw.githubusercontent.com/0oVicero0/serverSpeeder_Install/master/appex.sh && chmod +x appex.sh && bash appex.sh install
	rm -f appex.sh
	memory=`cat /proc/meminfo |grep 'MemTotal' |awk -F : '{print $2}' |sed 's/^[ \t]*//g' | awk  '{print $1}'`
	memory1=`expr ${memory} / 1024`
	memory2=`expr ${memory1} \* 8`
	cpucore=`cat /proc/cpuinfo | grep “processor” | wc -l`
	ping1=`ping 140.205.230.3  -s 1000 -c 10 | awk -F"[= ]*"   '/from/{sum+=$(NF-1);}END{print sum/10;}' | awk -F "." '{print $1}'`
	sed -i '/initialCwndWan/d' /appex/etc/config
	sed -i '/l2wQLimit/d' /appex/etc/config
	sed -i '/w2lQLimit/d' /appex/etc/config
	sed -i '/SmBurstMS/d' /appex/etc/config
	sed -i '/engineNum/d' /appex/etc/config
	sed -i '/shortRttMS/d' /appex/etc/config
	initialCwndWan=`expr ${ping1} / 3`
	SmBurstMS=`expr ${ping1} / 9`
	l2wQLimit="${memory1} ${memory2}"
	echo -e "initialCwndWan=\"${initialCwndWan}\"
l2wQLimit=\"${l2wQLimit}\"
w2lQLimit=\"${l2wQLimit}\"
SmBurstMS=\"${SmBurstMS}\"
engineNum=\"${cpucore}\"
shortRttMS=\"${initialCwndWan}\"">>/appex/etc/config
	bash /appex/bin/serverSpeeder.sh restart
	start_menu
}

#卸载全部加速
remove_all(){
	sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
	if [[ -e /appex/bin/serverSpeeder.sh ]]; then
		wget --no-check-certificate -O appex.sh https://raw.githubusercontent.com/0oVicero0/serverSpeeder_Install/master/appex.sh && chmod +x appex.sh && bash appex.sh uninstall
		rm -f appex.sh
	fi
	clear
	echo -e "${Info}:清除加速完成。"
	sleep 1s
}

#优化系统配置
optimizing_system(){
	sed -i '/fs.file-max/d' /etc/sysctl.conf
	sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
	sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
	sed -i '/net.core.rmem_default/d' /etc/sysctl.conf
	sed -i '/net.core.wmem_default/d' /etc/sysctl.conf
	sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
	sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_tw_recycle/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_mtu_probing/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
	echo "# max open files
fs.file-max = 1024000
# max read buffer
net.core.rmem_max = 67108864
# max write buffer
net.core.wmem_max = 67108864
# default read buffer
net.core.rmem_default = 65536
# default write buffer
net.core.wmem_default = 65536
# max processor input queue
net.core.netdev_max_backlog = 4096
# max backlog
net.core.somaxconn = 4096

# resist SYN flood attacks
net.ipv4.tcp_syncookies = 1
# reuse timewait sockets when safe
net.ipv4.tcp_tw_reuse = 1
# turn off fast timewait sockets recycling
net.ipv4.tcp_tw_recycle = 0
# short FIN timeout
net.ipv4.tcp_fin_timeout = 30
# short keepalive time
net.ipv4.tcp_keepalive_time = 1200
# outbound port range
net.ipv4.ip_local_port_range = 10000 65000
# max SYN backlog
net.ipv4.tcp_max_syn_backlog = 4096
# max timewait sockets held by system simultaneously
net.ipv4.tcp_max_tw_buckets = 5000
# TCP receive buffer
net.ipv4.tcp_rmem = 4096 87380 67108864
# TCP write buffer
net.ipv4.tcp_wmem = 4096 65536 67108864
# turn on path MTU discovery
net.ipv4.tcp_mtu_probing = 1

# forward ipv4
net.ipv4.ip_forward = 1">>/etc/sysctl.conf
	sysctl -p
	echo "*               soft    nofile           512000
*               hard    nofile          1024000">/etc/security/limits.conf
	echo "session required pam_limits.so">>/etc/pam.d/common-session
	echo "ulimit -SHn 1024000">>/etc/profile
	read -p "需要重启VPS后，才能生效系统优化配置，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "${Info} VPS 重启中..."
		reboot
	fi
}
#更新脚本
Update_Shell(){
	echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "http://${github}/tcp.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败 !" && start_menu
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
		read -p "(默认: y):" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			wget -N --no-check-certificate http://${github}/tcp.sh && chmod +x tcp.sh
			echo -e "脚本已更新为最新版本[ ${sh_new_ver} ] !"
		else
			echo && echo "	已取消..." && echo
		fi
	else
		echo -e "当前已是最新版本[ ${sh_new_ver} ] !"
		sleep 5s
	fi
}

#开始菜单
start_menu(){
clear
echo && echo -e " TCP加速 一键安装管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
  -- 就是爱生活 | 94ish.me --
  
 ${Green_font_prefix}0.${Font_color_suffix} 升级脚本
————————————内核管理————————————
 ${Green_font_prefix}1.${Font_color_suffix} 安装 BBR/BBR魔改版内核
 ${Green_font_prefix}2.${Font_color_suffix} 安装 Lotserver(锐速)内核
————————————加速管理————————————
 ${Green_font_prefix}3.${Font_color_suffix} 使用BBR加速
 ${Green_font_prefix}4.${Font_color_suffix} 使用BBR魔改版加速
 ${Green_font_prefix}5.${Font_color_suffix} 使用Lotserver(锐速)加速
————————————杂项管理————————————
 ${Green_font_prefix}6.${Font_color_suffix} 卸载全部加速
 ${Green_font_prefix}7.${Font_color_suffix} 系统配置优化
 ${Green_font_prefix}8.${Font_color_suffix} 退出脚本
————————————————————————————————" && echo

	check_status
	if [[ ${kernel_status} == "noinstall" ]]; then
		echo -e " 当前状态: ${Green_font_prefix}未安装${Font_color_suffix} 加速内核 ${Red_font_prefix}请先安装内核${Font_color_suffix}"
	else
		echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix} ${_font_prefix}${kernel_status}${Font_color_suffix} 加速内核 , ${Green_font_prefix}${run_status}${Font_color_suffix}"
		
	fi
echo
read -p " 请输入数字 [0-8]:" num
case "$num" in
	0)
	Update_Shell
	;;
	1)
	check_sys_bbr
	;;
	2)
	check_sys_Lotsever
	;;
	3)
	startbbr
	;;
	4)
	startbbrmod
	;;
	5)
	startlotserver
	;;
	6)
	remove_all
	;;
	7)
	optimizing_system
	;;
	8)
	exit 1
	;;
	*)
	clear
	echo -e "${Error}:请输入正确数字 [0-8]"
	sleep 5s
	start_menu
	;;
esac
}
#############内核管理组件#############

#删除多余内核
detele_kernel(){
	if [[ "${release}" == "centos" ]]; then
		rpm_total=`rpm -qa | grep kernel | grep -v "${kernel_version}" | grep -v "noarch" | wc -l`
		if [ "${rpm_total}" > "1" ]; then
			echo -e "检测到 ${rpm_total} 个其余内核，开始卸载..."
			for((integer = 1; integer <= ${rpm_total}; integer++)); do
				rpm_del=`rpm -qa | grep kernel | grep -v "${kernel_version}" | grep -v "noarch" | head -${integer}`
				echo -e "开始卸载 ${rpm_del} 内核..."
				yum remove -y ${rpm_del}
				echo -e "卸载 ${rpm_del} 内核卸载完成，继续..."
			done
			echo -e "内核卸载完毕，继续..."
		else
			echo -e " 检测到 内核 数量不正确，请检查 !" && exit 1
		fi
	elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
		deb_total=`dpkg -l | grep linux-image | awk '{print $2}' | grep -v "${kernel_version}" | wc -l`
		if [ "${deb_total}" > "1" ]; then
			echo -e "检测到 ${deb_total} 个其余内核，开始卸载..."
			for((integer = 1; integer <= ${deb_total}; integer++)); do
				deb_del=`dpkg -l|grep linux-image | awk '{print $2}' | grep -v "${kernel_version}" | head -${integer}`
				echo -e "开始卸载 ${deb_del} 内核..."
				apt-get purge -y ${deb_del}
				echo -e "卸载 ${deb_del} 内核卸载完成，继续..."
			done
			echo -e "内核卸载完毕，继续..."
		else
			echo -e " 检测到 内核 数量不正确，请检查 !" && exit 1
		fi
	fi
}

#更新引导
BBR_grub(){
	if [[ "${release}" == "centos" ]]; then
        if [[ ${version} = "6" ]]; then
            if [ ! -f "/boot/grub/grub.conf" ]; then
                echo -e "${Error} /boot/grub/grub.conf 找不到，请检查."
                exit 1
            fi
            sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
        elif [[ ${version} = "7" ]]; then
            if [ ! -f "/boot/grub2/grub.cfg" ]; then
                echo -e "${Error} /boot/grub2/grub.cfg 找不到，请检查."
                exit 1
            fi
            grub2-set-default 0
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        /usr/sbin/update-grub
    fi
}

#############内核管理组件#############



#############系统检测组件#############

#检查系统
check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
}

#检查Linux版本
check_version(){
	if [[ -s /etc/redhat-release ]]; then
		version=`grep -oE  "[0-9.]+" /etc/redhat-release | cut -d . -f 1`
	else
		version=`grep -oE  "[0-9.]+" /etc/issue | cut -d . -f 1`
	fi
	bit=`uname -m`
	if [[ ${bit} = "x86_64" ]]; then
		bit="x64"
	else
		bit="x32"
	fi
}

#检查安装bbr的系统要求
check_sys_bbr(){
	check_version
	if [[ "${release}" == "centos" ]]; then
		if [[ ${version} -ge "6" ]]; then
			installbbr
		else
			echo -e "${Error} BBR内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	elif [[ "${release}" == "debian" ]]; then
		if [[ ${version} -ge "8" ]]; then
			installbbr
		else
			echo -e "${Error} BBR内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	elif [[ "${release}" == "ubuntu" ]]; then
		if [[ ${version} -ge "14" ]]; then
			installbbr
		else
			echo -e "${Error} BBR内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	else
		echo -e "${Error} BBR内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
	fi
}


#检查安装Lotsever的系统要求
check_sys_Lotsever(){
	check_version
	if [[ "${release}" == "centos" ]]; then
		if [[ ${version} == "6" ]]; then
			kernel_version="2.6.32-504"
			installlot
		elif [[ ${version} == "7" ]]; then
			yum -y install net-tools
			kernel_version="3.10.0-327"
			installlot
		else
			echo -e "${Error} Lotsever不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	elif [[ "${release}" == "debian" ]]; then
		if [[ ${version} -ge "7" ]]; then
			if [[ ${bit} == "x64" ]]; then
				kernel_version="3.16.0-4"
				installlot
			elif [[ ${bit} == "x32" ]]; then
				kernel_version="3.2.0-4"
				installlot
			fi
		else
			echo -e "${Error} Lotsever不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	elif [[ "${release}" == "ubuntu" ]]; then
		if [[ ${version} -ge "12" ]]; then
			if [[ ${bit} == "x64" ]]; then
				kernel_version="4.4.0-47"
				installlot
			elif [[ ${bit} == "x32" ]]; then
				kernel_version="3.13.0-29"
				installlot
			fi
		else
			echo -e "${Error} Lotsever不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	else
		echo -e "${Error} Lotsever不支持当前系统 ${release} ${version} ${bit} !" && exit 1
	fi
}

check_status(){
	kernel_version=`uname -r | awk -F "-" '{print $1}'`
	if [[ ${kernel_version} = "4.11.8" ]]; then
		kernel_status="BBR"
	elif [[ ${kernel_version} = "3.10.0" || ${kernel_version} = "3.16.0" || ${kernel_version} = "3.2.0" || ${kernel_version} = "4.4.0" || ${kernel_version} = "3.13.0"  || ${kernel_version} = "2.6.32" ]]; then
		kernel_status="Lotserver"
	else 
		kernel_status="noinstall"
	fi
	if [[ ${kernel_status} == "Lotserver" ]]; then
		if [[ -e /appex/bin/serverSpeeder.sh ]]; then
			run_status=`bash /appex/bin/serverSpeeder.sh status | grep "ServerSpeeder" | awk  '{print $3}'`
			if [[ ${run_status} = "running!" ]]; then
				run_status="启动成功"
			else 
				run_status="启动失败"
			fi
		else 
			run_status="未安装加速模块"
		fi
	elif [[ ${kernel_status} == "BBR" ]]; then
		run_status=`grep "net.ipv4.tcp_congestion_control" /etc/sysctl.conf | awk -F "=" '{print $2}'`
		if [[ ${run_status} == "bbr" ]]; then
			run_status=`lsmod | grep "bbr" | awk '{print $1}'`
			if [[ ${run_status} == "tcp_bbr" ]]; then
				run_status="BBR启动成功"
			else 
				run_status="BBR启动失败"
			fi
		elif [[ ${run_status} == "nanqinlang" ]]; then
			run_status=`lsmod | grep "nanqinlang" | awk '{print $1}'`
			if [[ ${run_status} == "tcp_nanqinlang" ]]; then
				run_status="BBR魔改版启动成功"
			else 
				run_status="BBR魔改版启动失败"
			fi
		else 
			run_status="未安装加速模块"
		fi
	fi
}

#############系统检测组件#############
check_sys
check_version
[[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "centos" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1
start_menu


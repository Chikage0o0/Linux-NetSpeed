# Linux-NetSpeed
```
不卸载内核版本
wget -N "https://github.000060000.xyz/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
卸载内核版本
wget -N "https://github.000060000.xyz/tcp.sh" && chmod +x tcp.sh && ./tcp.sh

支持 Focal Ubuntu 20.04 的一键重装脚本
from https://www.hostloc.com/thread-696865-1-1.html

wget https://github.000060000.xyz/InstallNET.sh && chmod a+x InstallNET.sh && bash InstallNET.sh -u focal -v 64 -a

5.5内核及BBR2内核支持cake队列

双持bbr+锐速
bbr 添加
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

编辑锐速文件
nano /appex/etc/config

检测代码有BUG，如果锐速正常 运行查看
bash /appex/bin/lotServer.sh status | grep "LotServer"

检查bbr 内核默认bbr算法不会有输出
lsmod | grep bbr

检查centos安装内核
grubby --info=ALL|awk -F= '$1=="kernel" {print i++ " : " $2}'

查看当前支持TCP算法
cat /proc/sys/net/ipv4/tcp_allowed_congestion_control
查看当前运行的算法
cat /proc/sys/net/ipv4/tcp_congestion_control
查看当前队列算法
sysctl net.core.default_qdisc

命令： uname -a
作用： 查看系统内核版本号及系统名称

命令： cat /proc/version
作用： 查看目录"/proc"下version的信息，也可以得到当前系统的内核版本号及系统名称

真实队列查看？ 更改队列算法可能需要重启生效
tc -s qdisc show

ylx2016与chiakge、cx9208无任何关系
bbsplus算法原作者
https://blog.csdn.net/dog250/article/details/80629551
bbrplus首用名 ？
https://github.com/cx9208/bbrplus
xanmod官网
https://xanmod.org
Zen官网
https://liquorix.net/
锐速
https://moeclub.org/2017/03/09/14/

#!/bin/bash

deb_issue="$(cat /etc/issue)"
deb_relese="$(echo $deb_issue |grep -io 'Ubuntu\|Debian' |sed -r 's/(.*)/\L\1/')"
os_ver="$(dpkg --print-architecture)"
[ -n "$os_ver" ] || exit 1

if [ "$deb_relese" == 'ubuntu' ]; then
  deb_ver="$(echo $deb_issue |grep -o '[0-9]*\.[0-9]*' |head -n1)"
  if [ "$deb_ver" == "14.04" ]; then
    item="3.16.0-77-generic" && ver='trusty'
  elif [ "$deb_ver" == "16.04" ]; then
    item="4.8.0-36-generic" && ver='xenial'
  elif [ "$deb_ver" == "18.04" ]; then
    item="4.15.0-30-generic" && ver='bionic'
  else
    exit 1
  fi
  url='archive.ubuntu.com'
  urls='security.ubuntu.com'
elif [ "$deb_relese" == 'debian' ]; then
  deb_ver="$(echo $deb_issue |grep -o '[0-9]*' |head -n1)"
  if [ "$deb_ver" == "7" ]; then
    item="3.2.0-4-${os_ver}" && ver='wheezy' && url='archive.debian.org' && urls='archive.debian.org'
  elif [ "$deb_ver" == "8" ]; then
    item="3.16.0-4-${os_ver}" && ver='jessie' && url='archive.debian.org' && urls='deb.debian.org'
  elif [ "$deb_ver" == "9" ]; then
    item="4.9.0-4-${os_ver}" && ver='stretch' && url='deb.debian.org' && urls='deb.debian.org'
  else
    exit 1
  fi
else
  exit 1
fi

[ -n "$item" ] && [ -n "$urls" ] && [ -n "$url" ] && [ -n "$ver" ] || exit 1

if [ "$deb_relese" == 'ubuntu' ]; then
  echo "deb http://${url}/${deb_relese} ${ver} main restricted universe multiverse" >/etc/apt/sources.list
  echo "deb http://${url}/${deb_relese} ${ver}-updates main restricted universe multiverse" >>/etc/apt/sources.list
  echo "deb http://${url}/${deb_relese} ${ver}-backports main restricted universe multiverse" >>/etc/apt/sources.list
  echo "deb http://${urls}/${deb_relese} ${ver}-security main restricted universe multiverse" >>/etc/apt/sources.list
elif [ "$deb_relese" == 'debian' ]; then
  echo "deb http://${url}/${deb_relese} ${ver} main" >/etc/apt/sources.list
  echo "deb-src http://${url}/${deb_relese} ${ver} main" >>/etc/apt/sources.list
  echo "deb http://${urls}/${deb_relese}-security ${ver}/updates main" >>/etc/apt/sources.list
  echo "deb-src http://${urls}/${deb_relese}-security ${ver}/updates main" >>/etc/apt/sources.list
fi

apt-get update
apt-get install --no-install-recommends -y linux-image-${item}
if [ $? -ne 0 ]; then
  if [ "$deb_ver" == "8" ]; then
    dpkg -l |grep -q 'linux-base' || {
      wget --no-check-certificate -qO '/tmp/linux-base_3.5_all.deb' 'http://snapshot.debian.org/archive/debian/20120304T220938Z/pool/main/l/linux-base/linux-base_3.5_all.deb'
      dpkg -i '/tmp/linux-base_3.5_all.deb'
    } 
    wget --no-check-certificate -qO '/tmp/linux-image-3.16.0-4-amd64_3.16.43-2+deb8u5_amd64.deb' 'http://snapshot.debian.org/archive/debian/20171008T163152Z/pool/main/l/linux/linux-image-3.16.0-4-amd64_3.16.43-2+deb8u5_amd64.deb'
    dpkg -i '/tmp/linux-image-3.16.0-4-amd64_3.16.43-2+deb8u5_amd64.deb'
    if [ $? -ne 0 ]; then
      exit 1
    fi
  elif [ "$deb_ver" == "9" ]; then
    dpkg -l |grep -q 'linux-base' || {
      wget --no-check-certificate -qO '/tmp/linux-base_4.5_all.deb' 'http://snapshot.debian.org/archive/debian/20160917T042239Z/pool/main/l/linux-base/linux-base_4.5_all.deb'
      dpkg -i '/tmp/linux-base_4.5_all.deb'
    } 
    wget --no-check-certificate -qO '/tmp/linux-image-4.9.0-4-amd64_4.9.65-3+deb9u1_amd64.deb' 'http://snapshot.debian.org/archive/debian/20171224T175424Z/pool/main/l/linux/linux-image-4.9.0-4-amd64_4.9.65-3+deb9u1_amd64.deb'
    dpkg -i '/tmp/linux-image-4.9.0-4-amd64_4.9.65-3+deb9u1_amd64.deb'
    if [ $? -ne 0 ]; then
      exit 1
    fi
  else
    exit 1
  fi
else
  exit 1
fi
while true; do
  List_Kernel="$(dpkg -l |grep 'linux-image\|linux-modules\|linux-generic\|linux-headers' |grep -v "$item")"
  Num_Kernel="$(echo "$List_Kernel" |sed '/^$/d' |wc -l)"
  [ "$Num_Kernel" -eq "0" ] && break
  for kernel in `echo "$List_Kernel" |awk '{print $2}'`
    do
      if [ -f "/var/lib/dpkg/info/${kernel}.prerm" ]; then
        sed -i 's/linux-check-removal/#linux-check-removal/' "/var/lib/dpkg/info/${kernel}.prerm"
        sed -i 's/uname -r/echo purge/' "/var/lib/dpkg/info/${kernel}.prerm"
      fi
      dpkg --force-depends --purge "$kernel"
    done
  done
apt-get autoremove -y
[ -d '/var/lib/apt/lists' ] && find /var/lib/apt/lists -type f -delete


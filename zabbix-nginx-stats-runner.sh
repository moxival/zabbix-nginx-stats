#!/bin/bash

KEY=${2:-default}
LOG=${1:-access.log}
DAT1=/tmp/zbxngxoff$KEY.dat
ACCESSLOG=/var/log/nginx/$LOG
dir=`dirname $0`

echo "=========" >> $dir/log.txt
date >> $dir/log.txt
/usr/sbin/logtail2 -f$ACCESSLOG -o$DAT1 | perl $dir/zabbix-nginx-stats.pl $KEY >> $dir/log.txt
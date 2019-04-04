#!/bin/bash

LOG=${1:-access.log}
KEY=${2:-default}

DAT1=/tmp/zbxngxoff$KEY.dat
ACCESSLOG=/var/log/nginx/$LOG
dir=`dirname $0`

/usr/sbin/logtail2 -f$ACCESSLOG -o$DAT1 | perl $dir/zabbix-nginx-stats.pl $KEY
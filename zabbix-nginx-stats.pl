#!/usr/bin/perl -w

# Script to parse nginx log file to calculate request counts and average request times.

#         log_format timed_combined '$remote_addr $host $remote_user [$time_local]  '
#                    '"$request" $status $body_bytes_sent '
#                    '"$http_referer" "$http_user_agent" $request_time $upstream_response_time $pipe';
#
# apt-get install libstatistics-descriptive-perl libtimedate-perl

use strict;
use File::Basename;
use Statistics::Descriptive;
use Date::Parse;
use File::Temp ();

use lib dirname($0);

our $DRYRUN = 0;
our $ZABBIX_SENDER = '/usr/bin/zabbix_sender';
our $ZABBIX_CONF = '/etc/zabbix/zabbix_agentd.conf';
# MAXAGE is the maximum age of log entries to process, all older lines are ignored
# Since this script is meant to be run every 10 minutes, make sure we don't process more logfile lines.
our $MAXAGE = (2 + 10) * 60 * 60;

our $CONFIG = [
    {},
];

eval "require '_config.pl'";

my $reqcount = 0;
my $oldcount = 0;
my $parseerrors = 0;
my $request_time_total = 0;
my $upstream_time_total = 0;
my $statuscount = {
    '2XX'   => 0,
    '3XX'   => 0,
    '4XX'   => 0,
    '5XX'   => 0,
    '403'   => 0,
    'other' => 0,
};
my $log_key = $ARGV[0];

if (not defined $log_key) {
    $log_key = 'default';
}

$log_key .= ',';

my $datafh = File::Temp->new();
my $results = [];

for my $cfg (@$CONFIG) {
    push(@$results, {
        s_request_time  => Statistics::Descriptive::Full->new(),
        s_upstream_time => Statistics::Descriptive::Full->new(),
        body_bytes_sent => Statistics::Descriptive::Full->new(),
        statuscount     => \%$statuscount,
        oldcount        => 0,
        reqcount        => 0,
        ignored         => 0,
    });
}

while (<STDIN>) {
    if (
        my (
            $remote_addr,
            $remote_user,
            $time_local,
            $request,
            $status,
            $body_bytes_sent,
            $http_referer,
            $http_user_agent,
            $is_cf,
            $city,
            $country,
            $request_time,
            $upstream_response_time) = m/(\S+) (\S+) \[(.*?)\]\s+"(.*?)" (\S+) (\S+) "(.*?)" "(.*?)" "(.*?)" "(.*?)" "(.*?)" ([\d\.]+)(?: ([\d\.]+|-))?/
    ) {
        my $l = $_;
        my $time = str2time($time_local);
        my $diff = time() - $time;

        my $i = 0;
        my ($method, $path) = split(' ', $request, 3);
        foreach my $cfg (@$CONFIG) {
            my $r = $results->[$i];
            $i += 1;
            if (!defined $path) {
                $path = '';
            }
            if ($diff > $MAXAGE) {
                $r->{oldcount} += 1;
            }
            if ($status != '403') {
                $status =~ s/^([0-9]{1})[0-9]{2}$/$1XX/;
            }
            $r->{statuscount}->{defined $r->{statuscount}->{$status} ? $status : 'other'} += 1;
            my $reqms = int($request_time * 1000);
            $r->{s_request_time}->add_data($reqms);
            if (defined $upstream_response_time && $upstream_response_time ne '-') {
                $r->{s_upstream_time}->add_data(int($upstream_response_time * 1000));
            }
            $r->{body_bytes_sent}->add_data($body_bytes_sent);
            $r->{reqcount} += 1;
        }
    }
    else {
        $parseerrors += 1;
    }
}

sub sendstat {
    my ($key, $value, $cfg) = @_;

    my $hostparam = defined $cfg->{host} ? ' -s "' . $cfg->{host} . '" ' : '';

    print $datafh (defined $cfg->{host} ? $cfg->{host} : '-') . " nginx[$log_key$key] $value\n";
}
sub sendstatint {
    my ($key, $value, $cfg) = @_;
    sendstat($key, int((defined $value ? $value : 0) + 0.5), $cfg);
}

sub sendstatpercentile {
    my ($key, $obj, $percentile, $cfg) = @_;
    my ($val, $index) = $obj->percentile($percentile);
    sendstatint("${key}${percentile}", $val, $cfg);
}

sub printstats {
    my ($obj, $prefix, $cfg) = @_;
    if ($obj->count() == 0) {
        return;
    }

    sendstatint("${prefix}_avg", $obj->sum() / $obj->count(), $cfg);
    sendstat("${prefix}_count", $obj->count(), $cfg);
    sendstatint("${prefix}_mean", $obj->mean(), $cfg);
    sendstatpercentile("${prefix}_percentile", $obj, 25, $cfg);
    sendstatpercentile("${prefix}_percentile", $obj, 80, $cfg);
    sendstatpercentile("${prefix}_percentile", $obj, 90, $cfg);
    sendstatint("${prefix}_median", $obj->median(), $cfg);
    sendstatint("${prefix}_sum", $obj->sum(), $cfg);
}
sub printbytestats {
    my ($obj, $prefix, $cfg) = @_;
    if ($obj->count() == 0) {
        return;
    }
    sendstatint("${prefix}_avg", $obj->sum() / $obj->count(), $cfg);
    #sendstat("${prefix}_count", $obj->count(), $cfg);
    sendstatint("${prefix}_sum", $obj->sum(), $cfg);
}

my $j = 0;
foreach my $cfg (@$CONFIG) {
    my $r = $results->[$j];
    $j++;
    sendstat('oldcount', $r->{oldcount}, $cfg);
    sendstat('requestcount', $r->{reqcount}, $cfg);
    sendstat('ignored', $r->{ignored}, $cfg);
    printstats($r->{s_request_time}, 'request_time', $cfg);
    printstats($r->{s_upstream_time}, 'upstream_time', $cfg);
    printbytestats($r->{body_bytes_sent}, 'body_bytes_sent', $cfg);
    sendstat("parseerrors", $parseerrors, $cfg);

    for my $status (keys %{$r->{statuscount}}) {
        sendstat("status_$status", $statuscount->{$status}, $cfg);
    }
}

my $cmd = "$ZABBIX_SENDER -c $ZABBIX_CONF -i " . $datafh->filename() . " 2>&1";
print $cmd . "\n";

system "cp " . $datafh->filename() . " /tmp/test.txt";
system $cmd unless $DRYRUN;

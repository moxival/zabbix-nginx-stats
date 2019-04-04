#!/usr/bin/perl

our $LOG_KEYS = ['default'];

eval "require './_config.pl'";

$first = 1;

print "[";

foreach my $log_key (@$LOG_KEYS)
{
        print "," if not $first;
        $first = 0;

        print "{\"{#LOGKEY}\":\"$log_key\"}";
}

print "]";

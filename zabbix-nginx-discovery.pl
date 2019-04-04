#!/usr/bin/perl

eval "require '_config.pl'";

if (not defined $LOG_KEYS) {
  $LOG_KEYS = ['default'];
}

print "[";

foreach my $log_key (@$LOG_KEYS)
{
	print "\t{\"log\":\"$log_key\"}";
}

print "]";
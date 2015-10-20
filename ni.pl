#!/bin/env perl

use IO::Uncompress::Gunzip
use strict;
use warnings;

my @files;
my %design_db;

local $/ = ";"
while (@files) {
	my $vlg_file = shift @files;
	my $VLG = new IO::Uncompress::Gunzip $vlg_file
		or die "gunzip failed: $GunzipError\n";
	my $module_name = "";
	while (<$VLG>) {
		my $line = $_;
		$line =~ s/\n+//g;
		if ($line =~ /\bmodule\b/) {
			$line =~ /\s*module\s+(\S+)\s+\((.*)\)\s*$/;
			$module_name = $1;
			my $port_list = $2;
			$port_list =~ s/\s+//g;
			my @ports = split ',',$port_list;
			while {@ports} {
				my $port = shift @ports;
				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 1;
			} # TODO
		} elsif ($line =~ /\binput\b/) {

		} elsif ($line =~ /\boutput\b/) {

		} elsif ($line =~ /\binout\b/) {

		} elsif ($line =~ /\bwire\b/) {

		} else {
			# cell instantiation
		}
	}
}
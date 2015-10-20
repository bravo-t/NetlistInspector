#!/bin/env perl

use IO::Uncompress::Gunzip
use strict;
use warnings;

my @files;
my %design_db;
my %cell_list;

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
			$cell_list{$module_name}{"instantiated_by_others"} = 0;
			$cell_list{$module_name}{"has_definition"} = 1;
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
			$line =~ s/\s*input\s+//;
			my $width = 1;
			if {$line =~ /\[(\d+):(\d+)\]/} {
				$width = $1 - $2 + 1;
			}
			$line =~ s/\s*\[.*\]//
			my @ports = split ',',$line;
			while (@ports) {
				my $port = shift @ports;
				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 0;
				if ($width = 1) {
					$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 0;
					$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "in";
					$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
				} else {
					for (my $i = 0; $i < $width; $i += 1) {
						$port = $port . "[$i]";
						$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 1;
						$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "in";
						$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
					}
				}
			}
		} elsif ($line =~ /\boutput\b/) {
			$line =~ s/\s*output\s+//;
			my $width = 1;
			if {$line =~ /\[(\d+):(\d+)\]/} {
				$width = $1 - $2 + 1;
			}
			$line =~ s/\s*\[.*\]//
			my @ports = split ',',$line;
			while (@ports) {
				my $port = shift @ports;
				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 0;
				if ($width = 1) {
					$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 0;
					$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "out";
					$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
				} else {
					for (my $i = 0; $i < $width; $i += 1) {
						$port = $port . "[$i]";
						$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 1;
						$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "out";
						$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
					}
				}
			}
		} elsif ($line =~ /\binout\b/) {
			$line =~ s/\s*inout\s+//;
			my $width = 1;
			if {$line =~ /\[(\d+):(\d+)\]/} {
				$width = $1 - $2 + 1;
			}
			$line =~ s/\s*\[.*\]//
			my @ports = split ',',$line;
			while (@ports) {
				my $port = shift @ports;
				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 0;
				if ($width = 1) {
					$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 0;
					$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "inout";
					$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
				} else {
					for (my $i = 0; $i < $width; $i += 1) {
						$port = $port . "[$i]";
						$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 1;
						$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "inout";
						$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
					}
				}
			}
		} elsif ($line =~ /\bwire\b/) {
			
		} else {
			# cell instantiation
		}
	}
}
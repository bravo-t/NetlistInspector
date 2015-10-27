#!/bin/env perl

use strict;
use warnings;
#use re::engine::RE2;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Clone qw(clone);
use Data::Dumper;

### GLOBAL VARIABLES ###
my $SEQ_PATTERN = "DFF";
### GLOBAL VARIABLES ###
my @files;

### DEBUG ###
push @files,"./test.v";
### DEBUG ###
#my %design_db;

#my %cell_list;
my %connections;
my $std_cell;

print "start to read verilog files\n";
my ($design_db,$cell_list,$fullname_refname_map) = &read_verilog(\@files);
print "Finished reading verilog\n";
my $top_module = &find_top_cell($cell_list);
print "top_module = $top_module\n";

#print Dumper $cell_list;
#print "\n=== After read_verilog ===\n";
#print Dumper $design_db;


&reorg_design_db(\%{$design_db->{$top_module}},$fullname_refname_map);


#print "\n=== After reorg ===\n";
#print Dumper $design_db;



&link("",$top_module,\%{$design_db->{$top_module}},$design_db,$fullname_refname_map);

print "\n=== After link ===\n";
print Dumper $design_db;

# %design_db structure after read_verilog and before link 
# %design_db => {
#	$module_name => {
#		"port" => {
#			$port_name =>{
#				'direction' => 'out|in|inout',
#	            'connections' => [
#	            	...
#	            ],
#	            'is_clock_network' => 0|1,
#	            'is_bus' => 0|1,
#	            'full_name' => ...
#			},
#			...
#		}
#		"net" => {
#			$net_name => {
#				'is_clock_network' => 0|1,
#                'full_name' => '...',
#                'ref_name' => '...',
#                'leaf_drivers' => [
#                    ...
#                ],
#                'leaf_loads' => [
#                    ...
#                ]
#			},
#			...
#		}
#		"cell" => {
#			$cell_name => {
#				'pin' => {
#					$pin => {
#                       'direction' => 'in|out|inout',
#                       'fanin_nets' => [
#                                         '...'
#                                       ],
#                       'is_clock_pin' => 0|1,
#                       'is_data_pin' => 0|1,
#                       'ref_name' => '...',
#                       'full_name' => '....'
#		            },
#		            ...
#                   'is_sequential' => 0|1,
#                   'full_name' => '...',
#                   'ref_name' => '...',
#                   'is_combinational' => 0|1
#			},
#			...
#		}
#	},
#	...
# }
sub read_verilog {
    my $files = $_[0];
    my %design_db;
    my %cell_list;
    my %fullname_refname_map;
    local $/ = ";";
    while (@$files) {
    	my $vlg_file = shift @files;
        my $file_lines;
        my $VLG;
        if ($vlg_file =~ /\.v\.gz/) {
    	    $VLG = new IO::Uncompress::Gunzip $vlg_file or die "gunzip failed: $GunzipError\n";
            $file_lines = `zgrep ";" $vlg_file | wc -l`;
            chomp $file_lines;
        } else {
            open $VLG,"<",$vlg_file;
            $file_lines = `grep ";" $vlg_file | wc -l`;
            chomp $file_lines;
        }
        my $percent_count = 10;
    	my $module_name = "";
    	while (<$VLG>) {
            my $percent = $. / $file_lines * 100;
            if ($percent >= $percent_count) {
                print "Reading $vlg_file: $percent_count% completed\n";
                $percent_count += 10;
            }
            next if /^\/\//;
            next if /^\s*$/;
            my $line = $_;
    		$line =~ s/\n+//g;
    		$line =~ s/;\s*$//;
    		$line =~ s/^\s*//;
            if ($line =~ /endmodule/) {
                $module_name = "";
                $line =~ s/endmodule//;
                next if $line =~ /^\s*$/;
            }
    		if ($line =~ /\bmodule\b/) {
    			$line =~ /\s*module\s+(\S+)\s+\((.*)\)/;
    			$module_name = $1;
    			my $port_list = $2;
    			if (not defined $cell_list{$module_name}{"instantiated_by_others"}) {
                    $cell_list{$module_name}{"instantiated_by_others"} = 0;
                }
    			$cell_list{$module_name}{"has_definition"} = 1;
    			$port_list =~ s/\s+//g;
    			my @ports = split ',',$port_list;
    			while (@ports) {
    				my $port = shift @ports;
    				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 1;
    			} 
    		} elsif ($line =~ /\binput\b/) {
    			$line =~ s/\s*input//;
    			$line =~ s/\s+//g;
    			my $width = 1;
    			if ($line =~ /\[(\d+):(\d+)\]/) {
    				$width = $1 - $2 + 1;
    			}
    			$line =~ s/\s*\[.*\]//;
    			my @ports = split ',',$line;
    			while (@ports) {
    				my $port = shift @ports;
    				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 0;
    				if ($width == 1) {
    					$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 0;
    					$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "in";
    					$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
    				} else {
    					for (my $i = 0; $i < $width; $i += 1) {
    						my $bus_port = $port . "[$i]";
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"is_bus"} = 1;
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"direction"} = "in";
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"full_name"} = $bus_port;
    
    					}
    				}
    			}
    		} elsif ($line =~ /\boutput\b/ or $line =~ /\btri\b/) {
    			$line =~ s/\s*output//;
    			$line =~ s/\s*tri//;
    			$line =~ s/\s+//g;
    			my $width = 1;
    			if ($line =~ /\[(\d+):(\d+)\]/) {
    				$width = $1 - $2 + 1;
    			}
    			$line =~ s/\s*\[.*\]//;
    			my @ports = split ',',$line;
    			while (@ports) {
    				my $port = shift @ports;
    				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 0;
    				if ($width == 1) {
    					$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 0;
    					$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "out";
    					$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
    				} else {
    					for (my $i = 0; $i < $width; $i += 1) {
    						my $bus_port = $port . "[$i]";
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"is_bus"} = 1;
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"direction"} = "out";
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"full_name"} = $bus_port;
    					}
    				}
    			}
    		} elsif ($line =~ /\binout\b/) {
    			$line =~ s/\s*inout//;
    			$line =~ s/\s+//g;
    			my $width = 1;
    			if ($line =~ /\[(\d+):(\d+)\]/) {
    				$width = $1 - $2 + 1;
    				$line =~ s/\s*\[.*\]//;
    			}
    			my @ports = split ',',$line;
    			while (@ports) {
    				my $port = shift @ports;
    				$design_db{"$module_name"}{"port"}{"$port"}{"unused"} = 0;
    				if ($width == 1) {
    					$design_db{"$module_name"}{"port"}{"$port"}{"is_bus"} = 0;
    					$design_db{"$module_name"}{"port"}{"$port"}{"direction"} = "inout";
    					$design_db{"$module_name"}{"port"}{"$port"}{"full_name"} = $port;
    				} else {
    					for (my $i = 0; $i < $width; $i += 1) {
                            my $bus_port = $port . "[$i]";
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"is_bus"} = 1;
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"direction"} = "inout";
    						$design_db{"$module_name"}{"port"}{"$bus_port"}{"full_name"} = $bus_port;
    					}
    				}
    			}
    		} elsif ($line =~ /\bwire\b/) {
    			$line =~ s/\s*wire//;
    			$line =~ s/\s+//g;
    			my $width = 1;
    			if ($line =~ /\[(\d+):(\d+)\]/) {
    				$width = $1 - $2 + 1;
    				$line =~ s/\s*\[.*\]//;
    			}
                my @nets = split ",",$line;
                while (@nets) {
                    my $net = shift @nets;
                    $design_db{"$module_name"}{"net"}{"$net"}{"ref_name"} = $net;
                    $design_db{"$module_name"}{"net"}{"$net"}{"full_name"} = $net;
                    if ($width == 1) {
                    	$design_db{"$module_name"}{"net"}{"$net"}{"ref_name"} = $net;
                    	$design_db{"$module_name"}{"net"}{"$net"}{"full_name"} = $net;
    				} else {
    					for (my $i = 0; $i < $width; $i += 1) {
                            my $bus_net = $net . "[$i]";
                            $design_db{"$module_name"}{"net"}{"$bus_net"}{"ref_name"} = $bus_net;
                    		$design_db{"$module_name"}{"net"}{"$bus_net"}{"full_name"} = $bus_net;
    					}
    				}
                }
    		} else {
    			# cell instantiation
                my ($cell,$inst,$rest) = split /\s+/,$line,3;
                $cell_list{$cell}{"instantiated_by_others"} = 1;
                if ($cell_list{$cell}{"instantiated_by_others"} and $cell_list{$cell}{"has_definition"}) {
                    $design_db{"$module_name"}{"cell"}{"$inst"}{"is_hierarchical_cell"} = 1;
                }
                $design_db{"$module_name"}{"cell"}{"$inst"}{"ref_name"} = $cell;
                $design_db{"$module_name"}{"cell"}{"$inst"}{"full_name"} = $inst;
                $fullname_refname_map{$inst} = $cell;
                my $seq_flag = &is_sequential_cell($cell);
                $design_db{"$module_name"}{"cell"}{"$inst"}{"is_sequential"} = $seq_flag;
                $design_db{"$module_name"}{"cell"}{"$inst"}{"is_combinational"} = ($seq_flag == 1)? 0 : 1;
                $rest =~ s/\s+//g;
                my @connect_list = split ",",$rest;
                while (@connect_list) {
                	my $connect_seg = shift @connect_list;
    	            while($connect_seg =~ /\.(\S+)\((\S+?)\)/g) {
    	                my $pin = $1;
    	                my $net = $2;
    	                if ($net =~ /\d+'b\d+/) {
    	                	if ($net =~ /\d+'b0+/) {
    	                		$net = "CONSTANT0";
    	                	} elsif ($net =~ /\d+'b1+/) {
    	                		$net = "CONSTANT1";
    	                	} else {
    	                		$net = "CONSTANTS";
    	                	}
    	                }
    	                my $is_clock_pin = 0;
    	                if ($pin =~ /\bCLK\b|\bCK\b|\bclk\b|\bck\b/) {
    	                	$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"is_clock_pin"} = 1;
    	                	$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"is_data_pin"} = 0;
    	                	$is_clock_pin = 1;
    	                } else {
    	                	$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"is_clock_pin"} = 0;
    	                	$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"is_data_pin"} = 1;
    	                	$is_clock_pin = 0;
    	                }
    	                my $ref_name = $pin;
    	                my $full_name = "$inst/$pin";
    	                $design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"full_name"} = $full_name;
    	                $design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"ref_name"} = $ref_name;
    	                my $pin_direction = &get_pin_direction($cell,$pin);
    	                $design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"direction"} = $pin_direction;
    	                if ($pin_direction eq "in") {
    	                    push @{$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"fanin_nets"}},$net;
    	                    if (defined $design_db{"$module_name"}{"net"}{"$net"}) {
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_loads"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                    } elsif (defined $design_db{"$module_name"}{"port"}{$net}) {
    	                        push @{$design_db{"$module_name"}{"port"}{$net}{"connections"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"port"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"port"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                    } else {
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_loads"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                        #print STDERR "Cannot find definition of net or port $net, connected to $full_name in module $module_name\n" if ($net !~ /CONSTANT/);
    	                    }
    	                } elsif ($pin_direction eq "out") {
    	                    push @{$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"fanout_nets"}},$net;
    	                    if (defined $design_db{"$module_name"}{"net"}{"$net"}) {
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_drivers"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                    } elsif (defined $design_db{"$module_name"}{"port"}{$net}) {
    	                        push @{$design_db{"$module_name"}{"port"}{$net}{"connections"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"port"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"port"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                    } else {
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_drivers"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                        #print STDERR "Cannot find definition of net or port $net, connected to $full_name in module $module_name\n" if ($net !~ /CONSTANT/);
    	                    }
    	                } else {
    	                    push @{$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"fanin_nets"}},$net;
    	                    push @{$design_db{"$module_name"}{"cell"}{$inst}{"pin"}{$pin}{"fanout_nets"}},$net;
    	                    if (defined $design_db{"$module_name"}{"net"}{"$net"}) {
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_drivers"}},$full_name;
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_loads"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                    } elsif (defined $design_db{"$module_name"}{"port"}{$net}) {
    	                        push @{$design_db{"$module_name"}{"port"}{$net}{"connections"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"port"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"port"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                    } else {
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_drivers"}},$full_name;
    	                        push @{$design_db{$module_name}{"net"}{$net}{"leaf_loads"}},$full_name;
    	                        if ($is_clock_pin) {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 1;
    	                        } else {
    	                        	$design_db{$module_name}{"net"}{$net}{"is_clock_network"} = 0;
    	                        }
    	                        #print STDERR "Cannot find definition of net or port $net, connected to $full_name in module $module_name\n" if ($net !~ /CONSTANT/);
    	                    }
    	                }
    	            }
    	        }
    		}
    	}
    }
    return (\%design_db,\%cell_list,\%fullname_refname_map);
}


# %design_db structure after link 
# %design_db => {
#	$top_module => {
#		"port" => {
#			$port_name =>{
#				'direction' => 'out|in|inout',
#	            'connections' => [
#	            	...
#	            ],
#	            'is_clock_network' => 0|1,
#	            'is_bus' => 0|1,
#	            'full_name' => ...
#			},
#			...
#		}
#		"net" => {
#			$net_name => {
#				'is_clock_network' => 0|1,
#                'full_name' => '...',
#                'ref_name' => '...',
#                'leaf_drivers' => [
#                    ...
#                ],
#                'leaf_loads' => [
#                    ...
#                ]
#			},
#			...
#		}
#		"cell" => {
#			$cell_name => {
#				'is_hierarchical_cell = 0',
#               'is_sequential' => 0|1,
#               'full_name' => '...',
#               'ref_name' => '...',
#               'is_combinational' => 0|1,
#				'pin' => {
#					$pin => {
#                       'direction' => 'in|out|inout',
#                       'fanin_nets' => [
#                                         '...'
#                                       ],
#                       'is_clock_pin' => 0|1,
#                       'is_data_pin' => 0|1,
#                       'ref_name' => '...',
#                       'full_name' => '....',
#		            },
#		            ...
#				},
#			$cell_name => {
#				'is_hierarchical_cell' => 1,
#				'is_sequential' => 0|1,
#               'full_name' => '...',
#               'ref_name' => '...',
#               'is_combinational' => 0|1
#				'pin' => {
#					$pin => {
#                   	'direction' => 'in|out|inout',
#                    	'fanin_nets' => [
#                                       '...'
#                                    	],
#                    	'is_clock_pin' => 0|1,
#                    	'is_data_pin' => 0|1,
#                    	'ref_name' => '...',
#                    	'full_name' => '....'
#		         	},
#		         	...
#				},
#				'net' => {...},
#				'cell' => {...},
#			},
#			...
#		}
#	},
# }

# sub

sub get_pin_direction {
    my ($cell,$pin) = @_;
    my $direction;
    if (defined $std_cell->{$cell} && not defined $std_cell->{$cell}{$pin}) {
        print STDERR "$cell is defined in std lib, but cannot find definition for pin $pin\n";
    } elsif (not defined $std_cell->{$cell} && not defined $std_cell->{$cell}{$pin}) {
        if ($pin =~ /DATA\d*|CLK|clk|ISON|ison|[A-F]\d*|EN|en|TE|SEL|SDI|SEN|SET|RESET/) {
            $direction = "in";
        } elsif ($pin =~ /Q\d*|OUT|out|Z\d*|QB\d*|ZB\d*|SDO|z\d*|zb\d*/) {
            $direction = "out";
        } else {
            $direction = "inout";
        }
    } else {
        $direction = $std_cell->{$cell}{$pin}{"direction"};
    }
    return $direction;
}

sub is_sequential_cell {
	my $cell = $_[0];
	if (defined $std_cell->{$cell}) {
		return $std_cell->{$cell}{"is_sequential_cell"};
	} else {
		if ($cell =~ /$SEQ_PATTERN/) {
			return 1;
		} else {
			return 0;
		}
	}
}

sub find_top_cell {
    my $cell_list = $_[0];
    my $topcell;
    foreach my $cell (keys %$cell_list) {
        if ($cell_list->{$cell}{"instantiated_by_others"} == 0 and $cell_list->{$cell}{"has_definition"} == 1) {
            if (defined $topcell and $topcell ne $cell) {
                print STDERR "ERROR: Multiple top modules found, previously $topcell, and now $cell.\n";
            }
            $topcell = $cell;
        }
    }
    return $topcell;
}

sub reorg_design_db {
    my ($input_db,$fullname_refname_map) = @_;
    foreach my $cell_full_name (keys %{$input_db->{"cell"}}) {
        if ($input_db->{"cell"}{$cell_full_name}{"is_hierarchical_cell"}) {
            my $cell_ref_name = $fullname_refname_map->{$cell_full_name};
            if (not defined $design_db->{$cell_ref_name}) {
            	die "ERROR: Cannot find module definition for $cell_ref_name\n";
            } else {
            	$input_db->{"cell"}{$cell_full_name}{"port"} = clone($design_db->{$cell_ref_name}{"port"});
            	$input_db->{"cell"}{$cell_full_name}{"net"} = clone($design_db->{$cell_ref_name}{"net"});
            	$input_db->{"cell"}{$cell_full_name}{"cell"} = clone($design_db->{$cell_ref_name}{"cell"});
            }
            print Dumper $input_db;
            if (defined $design_db->{$cell_ref_name}) {
                print "DEBUG: merging ports and pin info\n";
                # merge port info and pin info of current hier
                foreach my $pin (keys %{$input_db->{"cell"}{$cell_full_name}{"pin"}}) { ### HERE is WRONG!!! ###

                    print "DEBUG: pin = $pin\n";
                    print Dumper $input_db->{"pin"};
                    $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"direction"} = $input_db->{"cell"}{$cell_full_name}{"port"}{$pin}{"direction"};
                    $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"is_bus_pin"} = $input_db->{"cell"}{$cell_full_name}{"port"}{$pin}{"is_bus"};
                    #merge @connection
                    if ($input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"direction"} eq "in") {
                        print "DEBUG: before merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanout_nets"};
                        $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanout_nets"} = clone($input_db->{"cell"}{$cell_full_name}{"port"}{$pin}{"connections"});
                        print "DEBUG: after merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanout_nets"};
                    } elsif ($input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"direction"} eq "out") {
                        print "DEBUG: before merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanin_nets"};
                        $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanin_nets"} = clone($input_db->{"cell"}{$cell_full_name}{"port"}{$pin}{"connections"});
                        print "DEBUG: after merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanin_nets"};
                    } else {
                        print "DEBUG: before merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanout_nets"};
                        print "DEBUG: before merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanin_nets"};
                        &merge_array(\@{$input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanin_nets"}},\@{$input_db->{"cell"}{$cell_full_name}{"port"}{$pin}{"connections"}});
                        &merge_array(\@{$input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanout_nets"}},\@{$input_db->{"cell"}{$cell_full_name}{"port"}{$pin}{"connections"}});
                        print "DEBUG: after merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanout_nets"};
                        print "DEBUG: after merge:\n";
                        print Dumper $input_db->{"cell"}{$cell_full_name}{"pin"}{$pin}{"fanin_nets"};
                    }
                }
            }
            delete $input_db->{"cell"}{$cell_full_name}{"port"};
            my $recursive_db = \%{$input_db->{"cell"}{$cell_full_name}};
            &reorg_design_db($recursive_db,$fullname_refname_map);
        }
    }
}

# call this sub like &link("",$top_module,\$design_db{$top_module},\%connections);
# TODO:
# Now port full_name is not processed
# For a input port:
#   fanin_net doesnot need any process, fanout_nets has to add prefix

sub link {
	my ($prefix,$inst_full_name,$input_db,$design_db,$fullname_refname_map) = @_;
    # First build $full_name for all nets in the current hier, because net are not hierarchical
    # if $prefix equal to "", then we are probably in $top_module, no need to build full_names for nets
    # if $prefix are not equal to "", but %design_db{$inst_full_name} is not defined, then this cell is probably a std cell, then we treat it as a black box, there's no net inside
    my $inst_ref_name = $fullname_refname_map->{$inst_full_name};
    if ($prefix ne "" and defined $design_db->{$inst_ref_name}) {
        foreach my $net (keys %{$input_db->{"net"}}) {
            # first build the full_name of $net and don't touch anything
            # then for all leaf_drivers and leaf_loads:
            #    find the corresponding cell and pin, then trace the connected nets
            #    change the name of nets
            # change the net name in net definition area
            my $net_full_name = $prefix . "/" . $net;
            my @leaf_drivers = @{$input_db->{"net"}{$net}{"leaf_drivers"}};
            my @leaf_loads = @{$input_db->{"net"}{$net}{"leaf_loads"}};
            # change the net name in pin connection area
            my @leaf_connections;
            push @leaf_connections,@leaf_drivers;
            push @leaf_connections,@leaf_loads;
            foreach my $pin_name (@leaf_connections) {
                print "DEBUG: pin_name = $pin_name\n";
                my ($cell,$pin) = &extract_basename($pin_name);
                print "DEBUG: cell = $cell\n";
                if (defined $cell and $cell ne "") {
                    my $net_collection;
                    if ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "in") {
                        my $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}};
                        print Dumper $input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"};
                        print "prefix = $prefix\n";
                        print "net = $net\n";
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                    } elsif ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "out") {
                        my $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}};
                        print Dumper $input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"};
                        print "prefix = $prefix\n";
                        print "net = $net\n";
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                    } else {
                        my $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}};
                        print Dumper $input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"};
                        print "prefix = $prefix\n";
                        print "net = $net\n";
                        print Dumper $input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"};
                        print "prefix = $prefix\n";
                        print "net = $net\n";
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                        $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}};
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                    }
                } else {
                    # $pin_name is actually a port name
                    # Modify the info source, i.e. %design_db{$module_name}{"port"} directly
                    # The modified info will be copied under $top_module later, so no data will be lost
                    my $net_collection = \@{$design_db->{$inst_ref_name}{"port"}{$pin}{"connections"}};
                    &add_prefix_to_array_element($prefix,$net,$net_collection);
                } 
            }
            # change net name in definition area
            $input_db->{"net"}{$net}{"full_name"} = $net_full_name;
        }
    }
    # Then build full_name for all cells
    foreach my $cell (keys %{$input_db->{"cell"}}) {
        if ($input_db->{"cell"}{$cell}{"is_hierarchical_cell"}) {
            ###################
            # my $recursive_db = \%{$input_db->{"cell"}{$cell}}
            # recursively call &link($recursive_db);
            ##################
            my $recursive_db = \%{$input_db->{"cell"}{$cell}};
            &link($cell,$cell,$recursive_db,$design_db,$fullname_refname_map);
        } else {
            #########################
            # build $full_name and %connections
            #########################
            # build full_name for cells and change the names accordingly.
            # names need to be changed in the following order:
            # first build the full_name of this cell and don't change anything yet.
            # then for each pin in this current cell:
            # 	build the full_name for this pin, store it, don't change anything yet, again.
            #	for every net connected to this pin:
            #		trace the net, and CHANGE the name of the pin that the net connected to.
            #	CHANGE the name of the pin
            # after all info of the pins have been changed, change the full_name of the cell.
            #########################
            # skip $top_module because we don't need to change anything is it
            if ($prefix ne "") {
            	my $cell_full_name = $prefix . "/" . $input_db->{"cell"}{$cell}{"full_name"};
            	foreach my $pin (keys %{$input_db->{"cell"}{$cell}{"pin"}}) {
            		my $pin_full_name = $prefix . "/" . $input_db->{"cell"}{$cell}{"pin"}{$pin}{"full_name"};
            		if ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "in") {
            			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}}) {
                            if (defined $input_db->{"net"}{$net}) {
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"net"}{$net}{"leaf_loads"}});
                            } elsif (defined $input_db->{"pin"}{$net}) {
                                # This is connected to a port,which is now a pin for this current cell
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"pin"}{$net}{"fanout_nets"}});
                            }
            			}
            		} elsif ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "out") {
            			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}}) {
                            if (defined $input_db->{"net"}{$net}) {
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"net"}{$net}{"leaf_drivers"}});
                            } elsif (defined $input_db->{"pin"}{$net}) {
                                # This is connected to a port,which is now a pin for this current cell
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"pin"}{$net}{"fanin_nets"}});
                            }
            			}
            		} else {
            			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}}) {
                            if (defined $input_db->{"net"}{$net}) {
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"net"}{$net}{"leaf_loads"}});
                            } elsif (defined $input_db->{"pin"}{$net}) {
                                # This is connected to a port,which is now a pin for this current cell
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"pin"}{$net}{"fanout_nets"}});
                            }
            			}
            			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}}) {
                            if (defined $input_db->{"net"}{$net}) {
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"net"}{$net}{"leaf_drivers"}});
                            } elsif (defined $input_db->{"pin"}{$net}) {
                                # This is connected to a port,which is now a pin for this current cell
                                &add_prefix_to_array_element($prefix,$cell,\@{$input_db->{"pin"}{$net}{"fanin_nets"}});
                            }
            			}
            		}
            		$input_db->{"cell"}{$cell}{"pin"}{$pin}{"full_name"} = $pin_full_name;
            	}
            	$input_db->{"cell"}{$cell}{"full_name"} = $cell_full_name;
            }
        }
    }
}

sub delete_useless_db {
    my ($top_module,$design_db) = @_;
    foreach my $module (keys %$design_db) {
        next if ($module eq $top_module);
        delete $design_db->{$module};
    }
}

sub build_connections {
	my ($inst_full_name,$input_db,$connections) = @_;
    foreach my $cell (keys %{$input_db->{"cell"}}) {
        if ($input_db->{"cell"}{$cell}{"is_hierarchical_cell"}) {
			foreach my $pin (keys %{$input_db->{"cell"}{$cell}{"pin"}}) {
          		if ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "in") {
          			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}}) {
          				foreach my $driver (\@{$input_db->{"net"}{$net}{"leaf_drivers"}}) {
          					my ($driver_cell,$driver_pin) = &extract_basename($driver);
                            push @{$connections->{$driver_cell}{$pin}},$net;
                            $connections->{$driver_cell}{"is_hierarchical_cell"} = 1;
                            $connections->{$driver_cell}{"is_sequantial_cell"} = 0;
          				}
          			}
          		} elsif ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "out") {
          			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}}) {
          				my ($dummy,$pin_name) = &extract_basename($pin);
                        push @{$connections->{$cell}{$pin_name}},\@{$input_db->{"net"}{$net}{"leaf_loads"}};
                        $connections->{$cell}{"is_hierarchical_cell"} = 1;
                        $connections->{$cell}{"is_sequantial_cell"} = 0;
          			}
          		} else {
                    foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}}) {
          				foreach my $driver (\@{$input_db->{"net"}{$net}{"leaf_drivers"}}) {
          					my ($driver_cell,$driver_pin) = &extract_basename($driver);
                            push @{$connections->{$driver_cell}{$pin}},$net;
                            $connections->{$driver_cell}{"is_hierarchical_cell"} = 1;
                            $connections->{$driver_cell}{"is_sequantial_cell"} = 0;
          				}
          			}
                    foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}}) {
          				my ($dummy,$pin_name) = &extract_basename($pin);
                        push @{$connections->{$cell}{$pin_name}},\@{$input_db->{"net"}{$net}{"leaf_loads"}};
                        $connections->{$cell}{"is_hierarchical_cell"} = 1;
                        $connections->{$cell}{"is_sequantial_cell"} = 0;
          			}
          		}
          	}
            my $recursive_db = \%{$input_db->{"cell"}{$cell}};
            &build_connections($cell,$recursive_db,$connections);
        } else {

                foreach my $pin (keys %{$input_db->{"cell"}{$cell}{"pin"}}) {
          		if ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "in") {
          			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}}) {
          				foreach my $driver (\@{$input_db->{"net"}{$net}{"leaf_drivers"}}) {
          					my ($driver_cell,$driver_pin) = &extract_basename($driver);
                            push @{$connections->{$driver_cell}{$pin}},$pin;
                            $connections->{$driver_cell}{"is_hierarchical_cell"} = 0;
                            $connections->{$driver_cell}{"is_sequantial_cell"} = $input_db->{"cell"}{$driver_cell}{"is_sequential_cell"};
          				}
          			}
          		} elsif ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "out") {
          			foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}}) {
          				my ($dummy,$pin_name) = &extract_basename($pin);
                        push @{$connections->{$cell}{$pin_name}},\@{$input_db->{"net"}{$net}{"leaf_loads"}};
                        $connections->{$cell}{"is_hierarchical_cell"} = 0;
                        $connections->{$cell}{"is_sequantial_cell"} = $input_db->{"cell"}{$cell}{"is_sequential_cell"};
          			}
          		} else {
                    foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}}) {
          				foreach my $driver (\@{$input_db->{"net"}{$net}{"leaf_drivers"}}) {
          					my ($driver_cell,$driver_pin) = &extract_basename($driver);
                            push @{$connections->{$driver_cell}{$pin}},$pin;
                            $connections->{$driver_cell}{"is_hierarchical_cell"} = 0;
                            $connections->{$driver_cell}{"is_sequantial_cell"} = $input_db->{"cell"}{$driver_cell}{"is_sequential_cell"};
          				}
          			}
                    foreach my $net (@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}}) {
          				my ($dummy,$pin_name) = &extract_basename($pin);
                        push @{$connections->{$cell}{$pin_name}},\@{$input_db->{"net"}{$net}{"leaf_loads"}};
                        $connections->{$cell}{"is_hierarchical_cell"} = 0;
                        $connections->{$cell}{"is_sequantial_cell"} = $input_db->{"cell"}{$cell}{"is_sequential_cell"};
          			}
          		}
          	}
        }
    }
}

sub uniq {keys { map { $_ => 1} @_}};

sub add_prefix_to_array_element {
    my ($prefix,$ori_val,$array) = @_;
    my @new_array;
    for (0 .. $#{$array}) {
        if ($array->[$_] eq $ori_val) {
            my $new_val = $prefix . '/' . $ori_val;
            push @new_array,$new_val;
        } else {
            push @new_array,$array->[$_]
        }
    }
    @{$array} = ();
    push @$array,$new_array[$_] for 0 .. $#new_array;
}


# avoid using regex as much as possible in reasonable places to increase run time
# more than 1.5x faster than using regex
sub extract_basename {
    my $str = $_[0];
    my @seg = split "/",$str;
    my $base_name = $seg[-1];
    pop @seg;
    if ((scalar @seg) == 0) {
        return (undef,$base_name);
    } else {
        my $path = join("/",@seg);
        return ($path,$base_name);
    }
}

sub merge_array {
    my ($source_arr,$extra_arr) = @_;
    for (0 .. $#{$extra_arr}) {
        push @{$source_arr},$extra_arr->[$_];
    }
    return $source_arr;
}


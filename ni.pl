#!/bin/perl

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
my %design_db;

my %cell_list;
my %connections;
my %std_cell;

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

local $/ = ";";
while (@files) {
	my $vlg_file = shift @files;
    my $file_lines;
    my $VLG;
    if ($vlg_file =~ /\.v\.gz/) {
        #open $VLG,"gunzip -c $vlg_file | " or die $!;
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
            my $seq_flag = &is_sequential_cell($cell);
            $design_db{"$module_name"}{"cell"}{"$inst"}{"is_sequential"} = $seq_flag;
            $design_db{"$module_name"}{"cell"}{"$inst"}{"is_combinational"} = not $seq_flag;
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
	                my $ref_name = "$cell/$pin";
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

print "Finished reading verilog\n";
my $top_module = &find_top_cell(\%cell_list);
print "top_module = $top_module\n";
#print Dumper \%cell_list;

#print Dumper \%design_db;


# sub

sub get_pin_direction {
    my ($cell,$pin) = @_;
    my $direction;
    if (defined $std_cell{$cell} && not defined $std_cell{$cell}{$pin}) {
        print STDERR "$cell is defined in std lib, but cannot find definition for pin $pin\n";
    } elsif (not defined $std_cell{$cell} && not defined $std_cell{$cell}{$pin}) {
        if ($pin =~ /DATA\d*|CLK|clk|ISON|ison|[A-F]\d*|EN|en|TE|SEL|SDI|SEN|SET|RESET/) {
            $direction = "in";
        } elsif ($pin =~ /Q\d*|OUT|out|Z\d*|QB\d*|ZB\d*|SDO|z\d*|zb\d*/) {
            $direction = "out";
        } else {
            $direction = "inout";
        }
    } else {
        $direction = $std_cell{$cell}{$pin}{"direction"};
    }
    return $direction;
}

sub is_sequential_cell {
	my $cell = $_[0];
	if (defined $std_cell{$cell}) {
		return $std_cell{$cell}{"is_sequential_cell"};
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

# call this sub like &link("",$top_module,\$design_db{$top_module},\%connections);
sub link {
	my ($prefix,$inst_full_name,$input_db,$connections,$design_db) = @_;
    # First build $full_name for all nets in the current hier, because net are not hierarchical
    # if $prefix equal to "", then we are probably processing top_module, no need to build full_names for nets
    # if $prefix are not equal to "", but %design_db{$inst_full_name} is not defined, then this cell is probably a std cell, then we treat it as a black box, there's no net inside
    if ($prefix ne "" and defined $design_db->{$inst_full_name}) {
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
            foreach my $pin_name (@leaf_drivers @leaf_loads) {
                my ($cell,$pin) = &extract_basename($pin_name);
                if (defined $cell) {
                    my $net_collection;
                    if ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "in") {
                        my $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}};
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                    } elsif ($input_db->{"cell"}{$cell}{"pin"}{$pin}{"direction"} eq "out") {
                        my $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}};
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                    } else {
                        my $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanin_nets"}};
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                        my $net_collection = \@{$input_db->{"cell"}{$cell}{"pin"}{$pin}{"fanout_nets"}};
                        &add_prefix_to_array_element($prefix,$net,$net_collection);
                    }
                } else {
                    # TODO
                    # $pin_name is actually a port name
                    # Modify the info source, i.e. %design_db{$module_name}{"port"} directly
                    # The modified info will be copied under $top_module later, so no data will be lost
                    my $net_collection = \@{$design_db{$cell}{"port"}{$pin}{"connections"}};
                    &add_prefix_to_array_element($prefix,$net,$net_collection);
                } 
            }
            # change net name in definition area
            $input_db->{"net"}{$net_full_name} = clone($input_db->{"net"}{$net});
            $input_db->{"net"}{$net_full_name}{"full_name"} = $net_full_name;
            delete $input_db->{"net"}{$net};
        }
    }
    # Then build full_name for all cells
    foreach my $cell (keys %{$input_db->{"cell"}}) {
        if ($input_db->{"cell"}{$cell}{"is_hierarchical_cell"}) {
            ###################
            # copy "net", "cell" and "port" category from module $cell to $top_mdule/$cell
            ### IMPORTANT ###
            # DO NOT forget to merge port info and pin info !!!
            ### IMPORTANT ###
            # and delete the info source to save memory
            # my $recursive_db = \%{$input_db->{"cell"}{$cell}}
            # recursively call &link($recursive_db);
            ##################
            ## TODO
            # First to copy info

            ##### AFTER net, cell and port info is copied, merge port info to pin ######
            if ($prefix ne "" and defined $design_db->{$inst_full_name}) {
                # merge port info and pin info of current hier, and then delete port definition to save memory;
                #		"port" => {
                #			$port_name =>{
                #				'direction' => 'out|in|inout',
                #	            'connections' => [
                #	            	...
                #	            ],
                #	            'is_clock_network' => 0|1,
                #	            'is_bus' => 0|1,
                #	            'full_name' => ...

                foreach my $pin (keys %{$input_db->{"pin"}}) {
                    $input_db->{"pin"}{$pin}{"direction"} = $input_db->{"port"}{$pin}{"direction"};
                    $input_db->{"pin"}{$pin}{"is_bus_pin"} = $input_db->{"port"}{$pin}{"is_bus"};
                    #merge @connection
                    if ($input_db->{"pin"}{$pin}{"direction"} eq "in") {
                        $input_db->{"pin"}{$pin}{"fanout_nets"} = clone($input_db->{"port"}{$pin}{"connections"});
                    } elsif ($input_db->{"pin"}{$pin}{"direction"} eq "out") {
                        $input_db->{"pin"}{$pin}{"fanin_nets"} = clone($input_db->{"port"}{$pin}{"connections"});
                    } else {
                        &merge_array(\@{$input_db->{"pin"}{$pin}{"fanin_nets"}},\@{$input_db->{"port"}{$pin}{"connections"}});
                        &merge_array(\@{$input_db->{"pin"}{$pin}{"fanout_nets"}},\@{$input_db->{"port"}{$pin}{"connections"}});
                    }
                }
            }
            delete $input_db->{"port"};
            ############################################################################


            # First deal with pins, add an attribute called "is_hierarchical_pin = 1" in %connection
        } else {
            ###
            # build $full_name and %connections
            ###

            # deal with pins. These are actual pins, so is_hierarchical = 0
            
            
        }
    }
	# TODO
	# if $inst is not hier cell then
	#	build full_name for every cell in current hier
	#	build corresponding %connect entries
	# else
	#	copy corresponding entry from %design_db
	#	$prefix = $inst_full_name . "/" . $prefix;
	#	&link($prefix)
}

sub add_prefix_to_array_element {
    my ($prefix,$ori_val,$array) = @_;
    for (0 .. $#array) {
        if ($array->[$_] eq $ori_val) {
            my $new_val = $prefix . '/' . $ori_val;
            delete $array->[$_];
            push @$array,$new_val;
            last;
        }
    }
}

# avoid using regex as much as possible in reasonable places to increase run time
# more than 1.5x faster than using regex
sub extract_basename {
    my $str = $_[0];
    my @seg = split "/",$str;
    my $base_name = $seg[-1];
    pop @seg;
    if ($#seg == 0) {
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

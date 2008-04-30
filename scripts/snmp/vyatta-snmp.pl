#!/usr/bin/perl
#
# Module: vyatta-snmp.pl
# 
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: October 2007
# Description: Script to glue vyatta cli to snmp daemon
# 
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use VyattaConfig;
use VyattaMisc;
use Getopt::Long;

use strict;
use warnings;

my $mibdir    = '/opt/vyatta/share/snmp/mibs';
my $snmp_init = '/opt/vyatta/sbin/snmpd.init';
my $snmp_conf = '/etc/snmp/snmpd.conf';
my $snmp_snmpv3_user_conf = '/usr/share/snmp/snmpd.conf';
my $snmp_snmpv3_createuser_conf = '/var/lib/snmp/snmpd.conf';

sub snmp_init {
    #
    # This requires the iptables user module libipt_rlsnmpstats.so.
    # to get the stats from "show snmp".  For now we are disabling
    # this feature.
    #

    # system("iptables -A INPUT -m rlsnmpstats");
    # system("iptables -A OUTPUT -m rlsnmpstats");
}

sub snmp_restart {
    system("$snmp_init restart");
}

sub snmp_stop {
    system("$snmp_init stop");
}

sub snmp_get_constants {
    my $output;
    
    my $date = `date`;
    chomp $date;
    $output  = "#\n# autogenerated by vyatta-snmp.pl on $date\n#\n";
    $output .= "sysServices 14\n";
    $output .= "smuxpeer .1.3.6.1.4.1.3317.1.2.2\n"; 		# ospfd
    $output .= "smuxpeer .1.3.6.1.4.1.3317.1.2.5\n";		# bgpd
    $output .= "smuxpeer .1.3.6.1.4.1.3317.1.2.3\n";		# ripd
    return $output;
}

sub snmp_get_values {
    my $output = '';
    my $config = new VyattaConfig;

    $config->setLevel("protocols snmp community");
    my @communities = $config->listNodes();
    
    foreach my $community (@communities) {
        my $authorization = $config->returnValue("$community authorization");
        my @clients = $config->returnValues("$community client");
        my @networks = $config->returnValues("$community network");

        if (scalar(@clients) == 0 and scalar(@networks) == 0){
           if (defined $authorization and $authorization eq "rw") {
               $output .= "rwcommunity $community\n";
           } else {
                  $output .= "rocommunity $community\n";
           }
        } else {
                if (scalar(@clients) != 0){
                   foreach my $client (@clients){
                        if (defined $authorization and $authorization eq "rw") {
                            $output .= "rwcommunity $community $client\n";
                        } else {
                                $output .= "rocommunity $community $client\n";
                        }
                   }
                }
                if (scalar(@networks) != 0){
                   foreach my $network (@networks){
                        if (defined $authorization and $authorization eq "rw") {
                            $output .= "rwcommunity $community $network\n";
                        } else {
                                $output .= "rocommunity $community $network\n";
                        }

                   }
                }
        }
    }

    $config->setLevel("protocols snmp");
    my $contact = $config->returnValue("contact");
    if (defined $contact) {
	$output .= "syscontact \"$contact\" \n";
    }
    my $description = $config->returnValue("description");
    if (defined $description) {
	$output .= "sysdescr \"$description\" \n";
    }
    my $location = $config->returnValue("location");
    if (defined $location) {
	$output .= "syslocation \"$location\" \n";
    }

    my @trap_targets = $config->returnValues("trap-target");
    if ($#trap_targets >= 0) {
    # code for creating a snmpv3 user, setting access-level for it and use user to do internal snmpv3 requests
    snmp_create_snmpv3_user();
    snmp_write_snmpv3_user();
    $output .= "iquerySecName vyatta\n";
    # code to activate link up down traps
    $output .= "linkUpDownNotifications yes\n";
    }
    foreach my $trap_target (@trap_targets) {
        $output .= "trap2sink $trap_target\n";
    }

    return $output;
}

sub snmp_create_snmpv3_user {

    my $createuser = "createUser vyatta MD5 \"vyatta\" DES";
    open(my $fh, '>>', $snmp_snmpv3_createuser_conf) || die "Couldn't open $snmp_snmpv3_createuser_conf - $!";
    print $fh $createuser;
    close $fh;
}

sub snmp_write_snmpv3_user {

    my $user = "rwuser vyatta";
    open(my $fh, '>', $snmp_snmpv3_user_conf) || die "Couldn't open $snmp_snmpv3_user_conf - $!";
    print $fh $user;
    close $fh;
}

sub snmp_write_file {
    my ($config) = @_;

    open(my $fh, '>', $snmp_conf) || die "Couldn't open $snmp_conf - $!";
    print $fh $config;
    close $fh;
}


#
# main
#
my $init_snmp;
my $update_snmp;
my $stop_snmp;

GetOptions("init-snmp!"   => \$init_snmp,
	   "update-snmp!" => \$update_snmp,
           "stop-snmp!"   => \$stop_snmp);

if (defined $init_snmp) {
    snmp_init();
}

if (defined $update_snmp) { 
    my $config;

    $config  = snmp_get_constants();
    $config .= snmp_get_values();
    snmp_write_file($config);
    snmp_restart();
}

if (defined $stop_snmp) {
    snmp_stop();
}

exit 0;

# end of file





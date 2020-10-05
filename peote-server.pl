#!/usr/bin/perl -w

# Author, Urheber:Sylvio Sell
# Copyright (C) 2008 by Sylvio Sell
# All Rights Reserved. Alle Rechte vorbehalten!

# . .  .
# .\.|:/ .
#  _.o .~ .
# . /:\ .. .
# .~~~~~~~~~ ~
# ~ ~ 00 ~ ~~~~ ~~
# --- -\__)= ~ -  
# - --- | --- ---- ~
# relax with peote-net


use strict;
#use Storable qw(freeze thaw);
#use Socket;
use POE qw( Wheel::ReadWrite Filter::Stream );
use Peote::Server;
use Peote::MaiConfig;
use Peote::MaiLogger;
# use Data::Dumper;



my $config = MaiConfig::read_config_('peote-server.conf');
my $logger = MaiLogger->new($config);

my $peote = Peote::Server->new($config, $logger);
$peote->server_create();

POE::Kernel->run();

#$poe_kernel->run_one_timeslice() while 1;
#${$poe_kernel->[POE::Kernel::KR_RUN]} |= POE::Kernel::KR_RUN_CALLED; # damit keine errormsg wegen run-flag 


exit(0);


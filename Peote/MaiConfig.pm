package MaiConfig;

# Author, Urheber:Sylvio Sell
# Copyright (C) 2008 by Sylvio Sell
# All Rights Reserved. Alle Rechte vorbehalten!

use strict;
use warnings;
our $VERSION = "0.1";

# DEFAULTS
our $config = {
	'address'=>'localhost',
	'port'=>7680,

	'forward_http_address'=>'localhost',
	'forward_http_port'=>80,
	'forward_https_address'=>'localhost',
	'forward_https_port'=>443,

	'flash_policy_domain'=>'localhost',
	'flash_policy_port'=>80,

	'max_connections_per_ip'=>13,

	'compress_min_bytes'=>50,
	'compress_level'=>6,

	'logging'=>'on',
    'error_logging'=>'on',
    'access_logging'=>'on',

	'logfile'=>'peote.log',
    'error_logfile'=>'',
    'access_logfile'=>'',

	'debug'=>0
};

# Aufbau der Config und moegliche Werte
our $config_struct = {
	'address'=>'(DOMAIN|IP)', # ACHTUNG, war vorher nur auf IP (checken falls auf bestimmten plattformen sonst nicht geht!)
	'port'=>'(NUMBER)',
	'forward_http_address'=>'(DOMAIN|IP)', # ACHTUNG, evtl. nur auf IP
	'forward_http_port'=>'(NUMBER)',
	'forward_https_address'=>'(DOMAIN|IP)', # ACHTUNG, evtl. nur auf IP
	'forward_https_port'=>'(NUMBER)',
	'flash_policy_domain'=>'(DOMAIN|IP)',
	'flash_policy_port'=>'(NUMBER)',
	'max_connections_per_ip'=>'(NUMBER)',
	'compress_min_bytes'=>'(NUMBER)',
	'compress_level'=>'(NUMBER)',
	'logging'=>['on','off'],
	'error_logging'=>['on','off'],
	'access_logging'=>['on','off'],
	'logfile'=>'(STRING)',
	'error_logfile'=>'(STRING)',
	'access_logfile'=>'(STRING)'
};

######################################################################################

sub read_config_ {
	my $fn = shift;
    if (open(FOU, "<".$fn))
    {
        while (<FOU>)
        {
            chomp;                  # zeilenumbruch
            s/#.*//;                # kommentare
            s/^\s+//;               # leerzeichen am anfang
            s/\s+$//;               # leerzeichen am ende
            next unless length;     # noch mehr uebrig?
            my ($var, $wert) = split(/\s*=\s*/, $_, 2);
            $var = lc($var); # TODO: nur buchstaben usw. zulassen
            $wert = lc($wert);
            if (defined($config_struct->{$var}))
            {   
                if (ref($config_struct->{$var}) eq 'ARRAY')
                {
                    if (grep {$_ eq $wert} @{$config_struct->{$var}})
                    {
                        $wert =~ /(.*)/;
                        $config->{$var} = $1; # untainting;
                    }
                    else
                    {
                        print "Error in config, possible values for \'$var\' = ".join(' | ',@{$config_struct->{$var}})."\n";
                    }
                }
                else
                {
                    if ($config_struct->{$var} eq '(NUMBER)')
                    {
                        if ($wert =~ /(\d+)/)
                        {
                            $config->{$var} = $1; # untainting;
                        }
                        else
                        {
                            print "Error in config, value for \'$var\' is not a number!\n";
                        }
                        
                    }
                    if ($config_struct->{$var} eq '(STRING)')
                    {
                        if ($wert =~ /['"]*([^'"]*)['"]*/)
                        {
							$config->{$var} = $1; # untainting;
                        }
                        else
                        {
                            print "Error in config, value for \'$var\' contains no string!\n";
                        }
                        
                    }
                    elsif ($config_struct->{$var} eq '(IP)')
                    {
                        if ($wert =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/)
                        {
                            $config->{$var} = $1; # untainting;
                        }
                        else
                        {
                            print "Error in config, value for \'$var\' is not an IP Adress!\n";
                        }
                    }
                    elsif ($config_struct->{$var} eq '(DOMAIN|IP)')
                    {
                        if ($wert =~ /([\d\w\-\.]+)/) # ACHTUNG, matcht nicht 100% domains bzw. ip
                        {
                            $config->{$var} = $1; # untainting;
                        }
                        else
                        {
                            print "Error in config, value for \'$var\' (no valid domain or ip)\n";
                        }
                    }
                }
            }
            else
            {
                print "Error in config, unknow param: \'$var\'\n";
            }
        }
    }
    return ($config);
}

1;


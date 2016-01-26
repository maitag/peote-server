package MaiLogger;

# Author, Urheber:Sylvio Sell
# Copyright (C) 2008 by Sylvio Sell
# All Rights Reserved. Alle Rechte vorbehalten!

use strict;
use warnings;
our $VERSION = "0.1";


my $config = {};

############################################################################# KONSTRUKTOR
sub new {
	my $class = shift;
	$config = shift;		# uebergebene parameter bei new (was vorher $config war)

	my $self = bless {} , $class;
	#$self->{'propertie'} = ...;		# uebergebene parameter bei new (was vorher $config war)
	return $self;
}


######################################################################################

sub log {
    my ($self, $msg, $typ) = @_;
    #my $typ;
    
    my $logfile = $config->{'logfile'};
    
    if ($config->{'logging'} eq 'on')
    {
        
        if (defined($typ))
        {

            if ($typ eq 'ACCESS' && $config->{'access_logging'} eq 'on')
            {
                $msg = $self->get_time()." ACCESS:\t".$msg;
                $logfile = $config->{'access_logfile'} if ($config->{'access_logfile'});
            }
            elsif ($typ eq 'ERROR' && $config->{'error_logging'} eq 'on')
            {
                $msg = $self->get_time()." ERROR :\t".$msg;
                $logfile = $config->{'error_logfile'} if ($config->{'error_logfile'});
            }
            else
            {
                $msg = $self->get_time()." ".$typ.":\t".$msg;
            }
            
        }
        
		if ($logfile ne '')
		{
			if (open(FOU, ">>".$logfile))
			{
				print FOU $self->get_time()."  ".$msg;
				close FOU;
			}
		}
		else
		{	print $self->get_time()."  ".$msg;
		}
        
    }
    
    
}

sub get_time {
    my $newmin=0;my $newh=0;my $newtag=0;my $newmonat=0;my $newjahr=0;
    ($newmin,$newh,$newtag,$newmonat,$newjahr) = (localtime(time()))[1,2,3,4,5];
    $newmonat++;$newjahr += 1900;
    $newmin = '0'.$newmin if ($newmin < 10);
    $newh = '0'.$newh if ($newh < 10);
    my $dasdatum = $newh.':'.$newmin.' '.$newjahr.'/'.$newmonat.'/'.$newtag;
    return($dasdatum);
}


1;
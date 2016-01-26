package Peote::Forwarder;

# Author, Urheber:Sylvio Sell
# Copyright (C) 2008 by Sylvio Sell
# All Rights Reserved. Alle Rechte vorbehalten!

use strict;
use warnings;
our $VERSION = "0.1";

use POE qw( Wheel::ReadWrite Wheel::SocketFactory Filter::Stream );
# use Storable qw(freeze thaw);
use Socket qw(inet_ntoa);
# use Data::Dumper;


my $config = {};
my $logger = {};

############################################################################# KONSTRUKTOR
sub new {
	my $class = shift;
	$config = shift;		# uebergebene parameter bei new (was vorher $config war)
	$logger = shift;
	
	my $self = bless {} , $class;
	
	return $self;
}



############################################################################# Methods
sub forwarder_create {
    my ($self, $heap, $input, $forward_address, $forward_port) = @_;

    # semmi: todo  hier evtl. neue session

    $heap->{queue} = [];
    push @{ $heap->{queue} }, $input;
    
    $heap->{wheel_client}->event(InputEvent => 'forward_client_input');
		    

    $heap->{state} = 'connecting';

    $heap->{wheel_server} = POE::Wheel::SocketFactory->new(
							    RemoteAddress => $forward_address, 
							    RemotePort    => $forward_port,
							    SuccessEvent  => 'forward_server_connect',
							    FailureEvent  => 'forward_server_error',
							    );
    #&forward_client_input(@_);
 

}


sub forward_server_connect {
    my ( $kernel, $session, $heap, $socket ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];

    #my ( $local_port, $local_addr ) = unpack_sockaddr_in( getsockname($socket) );
    #$local_addr = inet_ntoa($local_addr);
    #log_to_file_("[$heap->{log}] Established forward from local $local_addr:$local_port to remote $heap->{remote_addr}:$heap->{remote_port} \n");

    # Replace the SocketFactory wheel with a ReadWrite wheel.

	$config->{'debug'} && print "FORWARD_SERVER_CONNECT:\n------------------------------\n";

    $heap->{wheel_server} = POE::Wheel::ReadWrite->new(
        Handle     => $socket,
        Driver     => POE::Driver::SysRW->new,
        Filter     => POE::Filter::Stream->new,
        InputEvent => 'forward_server_input',
        ErrorEvent => 'forward_server_error',
    );

   
	if ( exists $heap->{wheel_server} &&  @{$heap->{queue}})
	{
		while (@{ $heap->{queue} })
		{
				$heap->{wheel_server}->put(shift @{ $heap->{queue} });
		}
		$heap->{queue} = [];
	}
    $heap->{state} = 'connected';
    
}

sub forward_server_input {
    my ( $heap, $input ) = @_[ HEAP, ARG0 ];
    $config->{'debug'} && print "FORWARD_SERVER_INPUT:\n------------------------------\n";
    # print $input."\n";
    
    exists( $heap->{wheel_client} ) and $heap->{wheel_client}->put($input);
    #$heap->{wheel_client}->put($input);
    
}

sub forward_client_input {
    my ( $heap, $input ) = @_[ HEAP, ARG0 ];

	$config->{'debug'} && print "FORWARD_CLIENT_INPUT:\n------------------------------\n";
	# print $input."\n";

	if ( $heap->{state} eq 'connecting' )
	{
		push @{ $heap->{queue} }, $input;		
	}
	else
	{
		$heap->{wheel_server}->put($input) if ( exists $heap->{wheel_server} );
	}
}


sub forward_server_error {
    my ( $kernel, $heap, $operation, $errnum, $errstr ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
    
    $config->{'debug'} && print "\n\nFORWARD_SERVER_ERROR:(".$operation.")\n";
    if ($errnum)
    {
	$logger->log("Server connection encountered $operation error $errnum: $errstr\n");
	
    }
    
    $logger->log("Server closed connection.\n");

    if ($heap->{wheel_server}->get_driver_out_octets() > 0 && !$errnum)
    {    
	$config->{'debug'} && print "server out octets:" . $heap->{wheel_server}->get_driver_out_octets()."\n";
		
	$heap->{wheel_server}->event( FlushedEvent => 'server_handle_flushed' );
	$heap->{wheel_server}->flush();
	#delete $heap->{wheel_server};
    }
    else
    {
	delete $heap->{wheel_server};
    }

    if ( exists $heap->{wheel_client} )
    {
	if ($heap->{wheel_client}->get_driver_out_octets() > 0 && !$errnum)
	{
	    $config->{'debug'} && print "client out octets:" . $heap->{wheel_client}->get_driver_out_octets()."\n";
	    $heap->{wheel_client}->event( FlushedEvent => 'client_handle_flushed' );
	    $heap->{wheel_client}->flush();
	    #delete $heap->{wheel_client};
	}
	else
	{
	    delete $heap->{wheel_client};
	}
    }
    
}

sub server_handle_flushed {
    #my $wheel_id = $_[ARG0];
    #delete $_[HEAP]{wheel}{$wheel_id};
    $config->{'debug'} && print "LAST SERVER FLUSH!\n";
    my ( $heap ) = $_[ HEAP ];
    delete $heap->{wheel_server};
    
}


1;
package Peote::Server;

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
use Peote::Client;

my $client;

my $config = {};
my $logger = {};

############################################################################# KONSTRUKTOR
sub new {
    my $class = shift;
    $config = shift;    # uebergebene parameter bei new (was vorher $config war)
    $logger = shift;

    my $self = bless {}, $class;

    return $self;
}

############################################################################# Methods
sub server_create {

    $client = Peote::Client->new( $config, $logger );

    POE::Session->create(
        inline_states => {
            _start                => \&server_start,
            _stop                 => \&server_stop,
            server_accept_success => \&server_accept_success,
            server_accept_failure => \&server_accept_failure,
        },

        # Pass this function's parameters to the server_start().
        #         ARG0,  ARG1
        args => [ $config->{'address'}, $config->{'port'} ]
    );
}

sub server_start {
    my ( $heap, $addr, $port ) = @_[ HEAP, ARG0, ARG1 ];

    $logger->log("+ server $addr:$port started\n");

    $heap->{addr} = $addr;
    $heap->{port} = $port;

    $heap->{server_wheel} = POE::Wheel::SocketFactory->new(
        BindAddress => $addr,    # bind to this address
        BindPort    => $port,    # and bind to this port
        Reuse       => 'yes',    # reuse immediately
        SuccessEvent =>
          'server_accept_success',    # generate this event on connection
        FailureEvent => 'server_accept_failure',  # generate this event on error
    );
    $_[KERNEL]->alias_set(__PACKAGE__);

}

sub server_stop {
    my $heap = $_[HEAP];
    $logger->log("- server $heap->{addr}:$heap->{port} stopped.\n");
}

sub server_accept_success {
    my ( $heap, $socket, $client_addr, $client_port ) =
      @_[ HEAP, ARG0, ARG1, ARG2 ];
    $client->client_create( $socket, $client_addr, $client_port );
}

sub server_accept_failure {
    my ( $heap, $operation, $errnum, $errstr ) = @_[ HEAP, ARG0, ARG1, ARG2 ];
    $logger->log("Connection from $heap->{addr}:$heap->{port} encountered $operation error $errnum: $errstr\n", 'ERROR');

    #delete $heap->{server_wheel} if $errnum == ENFILE or $errnum == EMFILE;
}

1;

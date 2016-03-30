package Peote::Client;

# Author, Urheber:Sylvio Sell
# Copyright (C) 2008 by Sylvio Sell
# All Rights Reserved. Alle Rechte vorbehalten!

use strict;
use warnings;
our $VERSION = "0.1";

use POE qw( Wheel::ReadWrite Filter::Stream );

# use Storable qw(freeze thaw);
use Socket qw(inet_ntoa);
use Data::Dumper;
use Peote::Forwarder;
use Peote::Joints;


my $forwarder;

my $config = {};
my $logger = {};

my $ipcount = {};    # enthaelt max. numbers of connections per ip


my $joints = Peote::Joints->new($config, $logger);


############################################################################# KONSTRUKTOR
sub new {
    my $class = shift;
    $config = shift;    # uebergebene parameter bei new (was vorher $config war)
    $logger = shift;

    my $self = bless {}, $class;

    return $self;
}

############################################################################# Methods
sub client_create {
    my ( $self, $socket, $client_addr, $client_port ) = @_;

    $forwarder = Peote::Forwarder->new( $config, $logger );

    $client_addr = inet_ntoa($client_addr);

    $logger->log( "client create " . $client_addr . ":" . $client_port . "\n" );

    # ip dem hash hinzufuegen (port ist key)
    $ipcount->{$client_port} = $client_addr;

    my $anz_connections_per_ip = 0;
    foreach my $key ( keys %{$ipcount} ) {
        $anz_connections_per_ip++ if ( $ipcount->{$key} eq $client_addr );
    }

    if ( $anz_connections_per_ip <= $config->{'max_connections_per_ip'} ) {

        POE::Session->create(
            object_states => [
                $forwarder => {
                    forward_client_input =>  'forward_client_input',    # forwardet client-inputs zum andern server
                    forward_server_connect =>'forward_server_connect',    # Connected to server
                    forward_server_input =>  'forward_server_input',      # Server sent something
                    forward_server_error =>  'forward_server_error',      # Error on server socket
                    server_handle_flushed => 'server_handle_flushed'    # FLUSH
                }
            ],
            inline_states => {
                _start => \&client_start,
                _stop  => \&client_stop,
                client_input_policy        => \&client_input_policy,        # am anfang policy checken
                #client_input_cmd           => \&client_input_cmd,           # auf ein gueltiges commando checken
                client_input               => \&client_input,               # ES KOMMT WAS AN
                client_error               => \&client_error,               # Error on client socket.
                client_send                => \&client_send,                # sendet daten zum client
                client_check_login_timeout => \&client_check_login_timeout, # delay nach starten der verbindung
                client_send_alife_message  => \&client_send_alife_message,   # nach delay send alife command

		#forward_client_input  => \&forward_client_input,   # forwardet client-inputs zum andern server
		#forward_server_connect => \&forward_server_connect, # Connected to server.
		#forward_server_input => \&forward_server_input,  # Server sent something.
		#forward_server_error => \&forward_server_error,  # Error on server socket.

                client_handle_flushed => \&client_handle_flushed

            },

            # Pass some things to client_start():
            #         ARG0,    ARG1,       ARG2
            args => [ $socket, $client_addr, $client_port ]
        );

    }
    else {
        $logger->log("Verbindung von $client_addr:$client_port abgelehnt ($anz_connections_per_ip mal verbunden, $config->{'max_connections_per_ip'} erlaubt) \n");
        delete( $ipcount->{$client_port} );
    }
}


###################################################################################### client_start
sub client_start {
    my ( $heap, $session, $socket, $client_addr, $client_port ) = @_[ HEAP, SESSION, ARG0, ARG1, ARG2 ];

    $heap->{'sid'}         = $session->ID;
    $heap->{'client_addr'} = $client_addr;
    $heap->{'client_port'} = $client_port; 
    $heap->{'input_left'} = ""; # hier wird immer der REST gespeichert falls nicht alles in einem STUECK kam
    $heap->{'bytes_left'} = 0; # wieviel Bytes noch kommen muessen bis neue joint_nr/control-byte kommt
    $heap->{'joint_nr'} = undef;
    $heap->{'reciever_id'} = undef; 
    $heap->{'first'} = "";
    $heap->{'command'} = undef;
    $heap->{'command_nr'} = undef;
	

    $logger->log("[$heap->{sid}] Accepted connection from $client_addr:$client_port\n");

    $heap->{wheel_client} = POE::Wheel::ReadWrite->new(
        Handle     => $socket,
        Driver     => POE::Driver::SysRW->new,
        Filter     => POE::Filter::Stream->new,
        InputEvent => 'client_input_policy',    # nur beim ersten mal, danach wird auf client_input umgeschaltet
        ErrorEvent => 'client_error',
    );

    # checken ob nach einer gewissen zeit auch policy und login kam
    $poe_kernel->delay( client_check_login_timeout => 5 );

}

###################################################################################### client_input_policy
sub client_input_policy {
    my ( $heap, $input ) = @_[ HEAP, ARG0 ];

    #my @myArray = unpack( 'C*', $input );
    #my $myStringHex = '';
    #foreach my $c (@myArray) { $myStringHex .= "," . sprintf( "%lx", $c ); }
    #print "$myStringHex\n";
	#print $input;
    if ( $input eq ( '<policy-file-request/>' . pack( "b", 0 ) ) ) {  # TODO: hier koennten noch RESTE vom eigentlichem $input hinten dran haengen?
        my $policy = '<?xml version="1.0"?>'
          . '<!DOCTYPE cross-domain-policy SYSTEM "/xml/dtds/cross-domain-policy.dtd">'
          . '<cross-domain-policy>'
          . '<site-control permitted-cross-domain-policies="master-only"/>'
          . '<allow-access-from domain="'
          . $config->{'flash_policy_domain'}
          . '" to-ports="'
          . $config->{'flash_policy_port'} . '" />'
          . '</cross-domain-policy>'
          . pack( "b", 0 );
        if ( exists( $heap->{wheel_client} ) ) {
            $logger->log("[$heap->{sid}] Flashclient from $heap->{client_addr}:$heap->{client_port} gets his policy\n");
            $heap->{wheel_client}->put($policy);
        }
        
        $heap->{wheel_client}->event( InputEvent => 'client_input' );
		# delay loeschen
        $poe_kernel->delay( client_check_login_timeout => undef ); 		
    }
    elsif ( $input =~ /^GET/ ) {                # TODO: hier als Alternative noch einen Webserver.pm integrieren!
    #    $forwarder->forwarder_create(
    #        $heap, $input,
    #        $config->{'forward_http_address'},
    #        $config->{'forward_http_port'}
    #    );
        
        if ( exists( $heap->{wheel_client} ) ) {
			my $answer = '';
            $logger->log("[$heap->{sid}] Websocket from $heap->{client_addr}:$heap->{client_port} gets his answer\n");
            $heap->{wheel_client}->put($answer);
        }
 		$heap->{wheel_client}->event( InputEvent => 'client_input' ); #vorerst
		# delay loeschen
        $poe_kernel->delay( client_check_login_timeout => undef ); 

    }
    #elsif (substr($input,0,3) eq "\x16\x03\x01")
    #{
    #print "FORWARDING ZUM HTTPS SERVER \n";
    #$forwarder -> forwarder_create($heap, $input, $config->{'forward_https_address'}, $config->{'forward_https_port'});
    #}
    else {
        $logger->log("[$heap->{sid}] Flashclient $heap->{client_addr}:$heap->{client_port} has already his policy\n");

        # SEMMI: evtl. kam '<policy-file-request/>' nicht in einem Stueck !!!!!

        #&client_input(@_);
		client_input( @_ );
		# $heap->{'input_left'} . $input;
		
		$heap->{wheel_client}->event( InputEvent => 'client_input' );
		# delay loeschen
        $poe_kernel->delay( client_check_login_timeout => undef ); # TODO.. nur wenn was sinnvolles reinkommt DOS-ATTACK!
    }
}

###################################################################################### client_input
sub client_input {
    my ( $heap, $input ) = @_[ HEAP, ARG0 ];
    $config->{'debug'} && print "\nCLIENT INPUT \n\n";
   
    my $user_id = $heap->{sid};
	
    #$input .= $heap->{'input_left'}; # TODO: hier sicherheitshalber mal checken ob nicht so: $input = $heap->{'input_left'}.$input;
    $input = $heap->{'input_left'} . $input;
	$heap->{'input_left'} = ""; 
    
    while (length($input) > 0)  # solange noch input vorhanden ist
    {   
		$config->{'debug'} && print 'length($input):'.length($input)."\n";
		
		if (defined($heap->{'command'})) # ========================================== COMMAND CHUNK ==========================================
		{ 	
		# TODO: evtl. commands ohne ANTWORT + CHUNK-Size 
		# ... die hier zuerst abarbeiten und wenn nicht dann die andern commands die chunk haben
		# if ($heap->{'command'} < 4)
		# {...}
		# else {
			
			if (! defined( $heap->{'command_nr'} )) # noch keine command_nr und chunksize ermittelt
			{
				if (length($input) >= 2) 
				{
					($heap->{'command_nr'}, $input) = unpack("C1 a*", $input); #command_nr
					($heap->{'bytes_left'}, $input) = unpack("C1 a*", $input); #chunksize
					$config->{'debug'} && print "COMMAND_NR: ".$heap->{'command_nr'}."  CHUNK-SIZE: ".$heap->{'bytes_left'}."\n";
				}
				else
				{  # es fehlt noch mehr um ueberhaupt erst loszulegen, also 
					$heap->{'input_left'} = $input;
					$input = "";
				}
			}
			else # command_nr und chunksize sind ermittelt (damit der empfaenger diese ANTWORT Seinem Gesendetem Command ZUORDNEN kann)
			{
				
				# nun aber erst weitermachen wenn CommandChunk vollstaendig geladen wurde
				if (length($input) >= $heap->{'bytes_left'})
				{	
					if ($heap->{'command'} == 0) # CREATE OWN JOINT ----------------------------
					{	
						my $joint_id;
						($joint_id, $input) = unpack("a".$heap->{'bytes_left'}." a*", $input); # joint_id vom input abziehen
												
						$joints->addUser($user_id); #User anlegen (legt nur an wenns den nicht schon gibt)
						
						my $joint_nr = $joints->create($user_id,$joint_id);

						if ($joint_nr > -1)
						{	$logger->log("[$heap->{sid}] Client $heap->{client_addr}:$heap->{client_port} GIVE JOINT: '$joint_id'\n");
							# dem Clienten die command_nr und Joint-Nummer senden!                 -> 0 heisst OK (kein fehler)
							_send_command_chunk( $user_id, pack("C1",$heap->{'command_nr'}).pack("C1",0).pack("C1",$joint_nr));
						}
						else
						{	# dem Clienten Fehlermsg als Antwort senden                            -> 1 heisst fehler, danach kommt die Fehlernummer
							_send_command_chunk( $user_id, pack("C1",$heap->{'command_nr'}).pack("C1",1).pack("C1",-$joint_nr));
							$logger->log("[$heap->{sid}] Client $heap->{client_addr}:$heap->{client_port} FAILS TO CREATE JOINT $joint_nr\n");
						}
						
					}
					elsif ($heap->{'command'} == 1) # ENTER IN JOINT ------------------------------
					{
						my $joint_id;
						($joint_id, $input) = unpack("a".$heap->{'bytes_left'}." a*", $input); # joint_id vom input abziehen
						
						$joints->addUser($user_id); # User anlegen! (legt nur an wenns den nicht schon gibt)

						my ($user_nr, $joint_nr, $user_id_OWN, $joint_nr_OWN) = $joints->connect($user_id,$joint_id);

						if ($user_nr > -1)
						{
							$logger->log("[$heap->{sid}] Client $heap->{client_addr}:$heap->{client_port} GET JOINT $joint_id\n");
							# dem Clienten die joint -Nummern senden!
							_send_command_chunk( $user_id, pack("C1",$heap->{'command_nr'}).pack("C1",0).pack("C1",$joint_nr));
							
							# dem OWNER ein command senden das da ein neuer user ist:
							                             # servercommand   #userConnects 
							_send_command_chunk( $user_id_OWN, pack("C1",0).pack("C1",0).pack("C1",$joint_nr_OWN).pack("C1",$user_nr));
						}
						else
						{
							$logger->log("[$heap->{sid}] Client $heap->{client_addr}:$heap->{client_port} FAILS TO ENTER $joint_id\n");
							_send_command_chunk( $user_id, pack("C1",$heap->{'command_nr'}).pack("C1",1).pack("C1",-$user_nr));
							#delete $heap->{wheel_client};
						}
						
					}
					elsif ($heap->{'command'} == 2) # LEAVE JOINT ------------------------------
					{
						my $joint_nr_IN;
						($joint_nr_IN, $input) = unpack("C1 a*", $input); # joint_nr_IN vom input abziehen
						
						my ($user_id_OWN, $joint_nr_OWN, $user_nr) = $joints->disconnect($user_id, $joint_nr_IN); # User aus dem joint entfernen
						
						if ($user_id_OWN > -1)
						{	                              # servercommand   #userDisconnects                                     # reason
							_send_command_chunk( $user_id_OWN, pack("C1",0).pack("C1",1).pack("C1",$joint_nr_OWN).pack("C1",$user_nr).pack("C1",0)); # owner benachrichtigen
						}
					}
					elsif ($heap->{'command'} == 3) # DELETE JOINT ------------------------------
					{
						my $joint_nr_OWN;
						($joint_nr_OWN, $input) = unpack("C1 a*", $input); # joint_nr vom input abziehen
						
						my $disconnect_list = $joints->deleteJoint($user_id, $joint_nr_OWN); # joint loeschen
						
						if (defined($disconnect_list))
						{
							foreach my $user_id_joint_nr (@{$disconnect_list})
							{
								my ($user_id_IN, $joint_nr_IN) = @{$user_id_joint_nr}; # TODO: optimieren und unten gleich $user_id_joint_nr->[0] usw
																   # servercommand   #Disconnects                       # reason
								_send_command_chunk( $user_id_IN, pack("C1",0).pack("C1",2).pack("C1",$joint_nr_IN).pack("C1",0)); # user benachrichtigen
							}
						}
						else
						{	# TODO: bei undef FEHLERBEHANDLUNG (joint konnte nicht geloescht werden)
						}
					}
					else # kein bekanntes command!!! FEHLER oder DOS-ATTACK -----------------------
					{	$logger->log("[$heap->{sid}] Client $heap->{client_addr}:$heap->{client_port} COMMAND FAILURE: $input\n");
						delete $heap->{wheel_client};
						$input = "";
					}
					
					# am Ende wieder commandmode verlassen:
					$heap->{'bytes_left'} = 0;
					$heap->{'command'}=undef; $heap->{'command_nr'}=undef;
					
				}
				else
				{  # es fehlt noch command_nr und chunksize, um ueberhaupt erst loszulegen
					$heap->{'input_left'} = $input;
					$input = "";
				}
			}

			
		}
		elsif ($heap->{'bytes_left'} == 0) # bei chunk-ende, also =================== neuer DATEN CHUNK ======================================
        {
		   # da neuer chunk kommt, gibts noch keine joint_nr und empfaenger 
           $heap->{'joint_nr'} = undef;
           $heap->{'$reciever_id'} = undef;
    
           # zuerst Chunk-Size laden
           if(length($input) >= 2 )
           { 
              # Chunk-Size erstes Byte laden
              my $size_1; my $size_2;
              ($size_1, $input)=unpack("C1 a*", $input); # erstes Byte fuer Chunk-Size grabben
              
              if ($size_1 < 128)
              {   # TODO: da IMMER die joint_nr mit im chunk ist, koennte bei if ($size_ ==1) noch ein spezialkommando kommen (evtl. ein "alive ping" ?)
                  	# TODO: wenn die (size_1 == 1) ist, kann dies VORKOMMEN?
					# evtl. nun special-case, also dann ist es eine ANTWORT
					# auf ein COMMAND vom SERVER, z.b. wenn neuer joint eroeffnet wurde ???

				  if ($size_1 == 0) # --> CONTROL COMMAND  ----------------------
                  {    
                      # in den COMMAND_MODE WECHSELN und abbrechen (die while-loop macht es ja eh dann nochmal ->solange input!!!)
					  ($heap->{'command'}, $input) = unpack("C1 a*", $input); # ein Byte fuer COMMAND grabben 
					  # TODO: hier schon abbrechen wenn kein gueltiges command (siehe oben beim command-auswerten hiterm letzten!!!
                  }
                  else 
                  {
                       $heap->{'bytes_left'} = $size_1; # -->  kleiner Chunk!
					   $config->{'debug'} && print "DEBUG KLEINER CHUNK VOM CLIENT <----------- : chunksize=".$heap->{'bytes_left'}."\n";
                  } 
              }
              else
              {   
                  ($size_2, $input) = unpack("C1 a*", $input); # noch ein Byte fuer Chunk-Size grabben
                  $heap->{'bytes_left'} = ($size_1 - 128) * 256 + $size_2;   # --> grosser Chunk!
                  $config->{'debug'} && print "DEBUG GROSSER CHUNK VOM CLIENT <----------- : chunksize=".$heap->{'bytes_left'}."\n";
              }
           }
           else
           {  # es fehlt noch mehr um ueberhaupt erst loszulegen, also 
              $heap->{'input_left'} = $input;
              $input = "";
           }
        }
        else # -------------- Daten Chunk-Size ist uebermittelt, hier nurnoch Daten auswerten und weiterleiten ------------
        {
    
    
            if(! defined( $heap->{'joint_nr'} ))  # noch keine joint_nr ermittelt
            {
                if (length($input) > 0) # TODO: kann dieser check nicht entfallen (muss da nicht immer was sein wegen while-bedingung?)
                {  
					($heap->{'joint_nr'}, $input)=unpack("C1 a*", $input); # grab joint_nr ----------
                    $config->{'debug'} && print "joint_nr vom CLIENT <----: ".$heap->{'joint_nr'}."\n";
					
					$heap->{'bytes_left'}--;
                     
                    if ( $heap->{'joint_nr'} < 128 )
                    {
						my $user_nr_IN;
						my $joint_nr_OWN;
						
						($heap->{'$reciever_id'}, $joint_nr_OWN, $user_nr_IN) = $joints->toJoint($user_id, $heap->{'joint_nr'});
						$config->{'debug'} && print "joint_nr GESENDET (joint_nr_OWN)---->: ".$joint_nr_OWN."\n";
						$config->{'debug'} && print "user_nr GESENDET (user_nr_IN  )---->: ".$user_nr_IN."\n";
						
						if ($joint_nr_OWN > -1) # kein fehler: nur wenn es zu Dieser joint_nr moegliche in_joints gibt
						{
							$heap->{'first'} =  pack("C1", $joint_nr_OWN + 128 ) . pack("C1", $user_nr_IN);

							($heap->{'bytes_left'}, $input) = _send_anz_bytes( $heap->{'bytes_left'} , $heap->{'first'},  $input, $heap->{'$reciever_id'});
							$config->{'debug'} && print "[$user_id]RecieverID:".$heap->{'$reciever_id'}."\n";
						}
						else
						{
							# TODO: bei Fehler hier evtl. client disconnecten (moegliche DOS-Attack)!
							# aber: dann muss der client auch eine msg bekommen und wissen das joint weg ist
						}
					}
                 
                }
            }
            else # joint_nr wurde schon ermittelt
            {
               if (! defined( $heap->{'$reciever_id'} ))  # wurde schon der empfaenger ermittelt
               {    
					#TODO: evtl. Fehlerquelle: kann $input == "" sein?
					my $reciever_nr;
					my $joint_nr_IN;
					
					($reciever_nr, $input) = unpack("C1 a*", $input); #  grab $reciever_nr -----------
					$heap->{'bytes_left'}--;

					($heap->{'$reciever_id'}, $joint_nr_IN) = $joints->fromJoint($user_id, $heap->{'joint_nr'} - 128, $reciever_nr);
					$config->{'debug'} && print "joint_nr GESENDET (joint_nr_IN)---->: ".$joint_nr_IN."\n";
					
					if ($joint_nr_IN > -1) # kein fehler: nur wenn es zu Dieser joint_nr moegliche users_in
					{    
						$heap->{'first'} = pack("C1", $joint_nr_IN);
						
						( $heap->{'bytes_left'} , $input ) = _send_anz_bytes( $heap->{'bytes_left'} , $heap->{'first'} ,  $input, $heap->{'$reciever_id'});
						#print "[$user_id]RecieverID:".$heap->{'$reciever_id'}."\n";
						$config->{'debug'} && print "gesendet: bytes_left=".$heap->{'bytes_left'}.'  length($input):'.length($input)."\n";
					}
					else
					{
						# TODO: bei Fehler hier evtl. client disconnecten (moegliche DOS-Attack)!
						# aber: dann muss der client auch eine msg bekommen und wissen das user weg ist
					}
    
               }
               else
               {
                  # wenn joint_nr und reciever_id schon da sind, dann kann es nur ein Rest sein vom vorherigen MAle 
                  ( $heap->{'bytes_left'} , $input ) = _send_anz_bytes( $heap->{'bytes_left'}, $heap->{'first'} , $input, $heap->{'$reciever_id'});
                  #print "[$user_id]RecieverID:".$heap->{'$reciever_id'}."\n";
				  $config->{'debug'} && print "REST gesendet: bytes_left=".$heap->{'bytes_left'}.'  length($input):'.length($input)."\n";
               }
            }
    
    
        }
    
    
    } # end while

    

}

sub _send_anz_bytes
{
    my ( $bytes_left, $first, $input, $reciever_id ) = @_;
    my $input_send;
    if ($bytes_left >= length($input))
    {       # gesammten $input abziehen
            $input_send = $input;
            $bytes_left -= length($input_send);
            $input = '';
    }
    else
    {
		($input_send, $input) = unpack("a".$bytes_left." a*", $input); # chunk vom input abziehen TODO->FEHLER===???
        $bytes_left = 0;
    }
    
	_send_chunk($reciever_id, $first.$input_send);
     
    return($bytes_left, $input);
}

sub _send_chunk
{
	my ($reciever_id, $input) = @_;
    #TODO: kleinen ODER grossen Chunk erzeugen!
	my $chunk_size = length($input);
	if ($chunk_size<128)
	{
		$poe_kernel->post($reciever_id => client_send => pack("C1", $chunk_size).$input );
		$config->{'debug'} && print "DEBUG SEND TO CLIENT KLEINER CHUNK -----------> chunksize=".$chunk_size."\n";
	}
	else
	{	# TODO: Kann es vorkommen das chunksize mal groesser als 2 Byte wird? (eigentlich nicht, da ja auch nur so eingelesen wird)
		if ($chunk_size > 32767) {$config->{'debug'} && print "ACHTUNG, chunksize zu gross (zeile 500) chunksize=".$chunk_size; die; }
		$config->{'debug'} && print "DEBUG SEND TO CLIENT GROSSER CHUNK -----------> chunksize=".$chunk_size."\n";
		$poe_kernel->post($reciever_id => client_send => pack("C1", ($chunk_size >> 8) + 128 ).pack("C1", $chunk_size & 255).$input );
	}
}

sub _send_command_chunk
{
	my ($reciever_id, $input) = @_;
	
	my $chunk_size = length($input); #TODO:sicherstellen das < 255
	
	$poe_kernel->post($reciever_id => client_send => pack("C1",0).pack("C1", $chunk_size).$input); # 0 leitet command chunk ein
}

sub _deleteUser
{
	my $user_id = $_[0];
	
    my ($disconnect_list_IN, $disconnect_list_OWN) = $joints->deleteUser($user_id);
	$config->{'debug'} && print "---- disconnect_list_IN ----".Dumper($disconnect_list_IN);
	$config->{'debug'} && print "---- disconnect_list_OWN ---".Dumper($disconnect_list_OWN);
	
	if (defined($disconnect_list_IN))
	{
		foreach my $user_id_joint_nr (@{$disconnect_list_IN})
		{
			my ($user_id_OWN, $joint_nr_OWN) = @{$user_id_joint_nr}; # TODO: optimieren und unten gleich $user_id_joint_nr->[0] usw
											   # servercommand   #Disconnects                       # reason
			_send_command_chunk( $user_id_OWN, pack("C1",0).pack("C1",2).pack("C1",$joint_nr_OWN).pack("C1",1)); # user benachrichtigen
		}
	}
	else
	{	# TODO: Fehler -> user konnte nicht geloescht werden (war wohl schon) -> TODO: loggen
	}	
	
	if (defined($disconnect_list_OWN))
	{
		foreach my $user_id_joint_nr (@{$disconnect_list_OWN})
		{
			my ($user_id_IN, $joint_nr_IN, $user_nr_IN) = @{$user_id_joint_nr}; # TODO: optimieren und unten gleich $user_id_joint_nr->[0] usw
											   # servercommand   #userDisconnects                                       # reason
			_send_command_chunk( $user_id_IN, pack("C1",0).pack("C1",1).pack("C1",$joint_nr_IN).pack("C1",$user_nr_IN).pack("C1",1)); # user benachrichtigen
		}
	}

}

###################################################################################### client_send
sub client_send {
    my ( $heap, $message ) = @_[ HEAP, ARG0 ];
    if ( exists( $heap->{wheel_client} ) )
    { 
    	$poe_kernel->delay( client_send_alife_message => undef );
    	$heap->{wheel_client}->put($message);
    	$poe_kernel->delay( client_send_alife_message => 5 );
    }
}

###################################################################################### client_stop
sub client_stop {
    my $heap = $_[HEAP];
    my $user_id = $heap->{sid};

	$config->{'debug'} && print "CLIENT STOP\n";
	
    delete( $ipcount->{ $heap->{client_port} } );

    $logger->log("[$heap->{sid}] Closing session from $heap->{client_addr}:$heap->{client_port}\n");
}

###################################################################################### client_check_login_timeout
sub client_check_login_timeout {
    my $heap = $_[HEAP];
    my $user_id = $heap->{sid};
    
    
    $logger->log("[$heap->{sid}] CHECKLogin-Timeout for $heap->{client_addr}:$heap->{client_port}\n");
    $logger->log("[$heap->{sid}] Login-Timeout for $heap->{client_addr}:$heap->{client_port}\n");
    
    
    # TODO ???
    
    _deleteUser($user_id);
	
    delete( $ipcount->{ $heap->{client_port} } );
    delete $heap->{wheel_client};
    
}

###################################################################################### client_check_login_timeout
sub client_send_alife_message {
    my $heap = $_[HEAP];
    my $user_id = $heap->{sid};
    
    _send_command_chunk( $user_id, pack("C1",0).pack("C1",255).pack("C1",0).pack("C1",0) );
    
    #$logger->log("[$heap->{sid}] Send alife message for $heap->{client_addr}:$heap->{client_port}\n");
    
}

###################################################################################### client_error
sub client_error {
    my ( $kernel, $heap, $operation, $errnum, $errstr ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
    my $user_id = $heap->{sid};
	
	$config->{'debug'} && print "\n\nCLIENT_ERROR:(" . $operation . ")\n";
    
    _deleteUser($user_id); # TODO: errnmr mit uebergeben, damit user noch informiert werden kann ob socket-close oder socket-error
    delete( $ipcount->{ $heap->{client_port} } );
	

    # delay loeschen
    $poe_kernel->delay( client_check_login_timeout => undef );

    if ($errnum) {
        $logger->log("[$heap->{sid}] Client $heap->{client_addr}:$heap->{client_port} connection encountered $operation error $errnum: $errstr\n");
    }

    $logger->log("[$heap->{sid}] Client $heap->{client_addr}:$heap->{client_port} closed connection.\n");

    if ( $heap->{wheel_client}->get_driver_out_octets() > 0 && !$errnum ) {
        $config->{'debug'} && print "client out octets:" . $heap->{wheel_client}->get_driver_out_octets() . "\n";
        $heap->{wheel_client}->event( FlushedEvent => "client_handle_flushed" );
        $heap->{wheel_client}->flush();

        #delete $heap->{wheel_client};
    }
    else {
        delete $heap->{wheel_client};
    }

    if ( exists( $heap->{wheel_server} ) ) {
        if ( $heap->{wheel_server}->get_driver_out_octets() > 0 && !$errnum ) {
            $config->{'debug'} && print "server out octets:" . $heap->{wheel_server}->get_driver_out_octets() . "\n";
            $heap->{wheel_server}->event( FlushedEvent => 'server_handle_flushed' );
            $heap->{wheel_server}->flush();

            #delete $heap->{wheel_server};
        }
        else {
            delete $heap->{wheel_server};
        }
    }

}

###################################################################################### client_handle_flushed
sub client_handle_flushed {

    #my $wheel_id = $_[ARG0];
    #delete $_[HEAP]{wheel}{$wheel_id};
    $config->{'debug'} && print "LAST CLIENT FLUSH!\n";
    my ($heap) = $_[HEAP];
    delete $heap->{wheel_client};

}



1;

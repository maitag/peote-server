package Peote::Joints;

# Author, Urheber:Sylvio Sell
# Copyright (C) 2008 by Sylvio Sell
# All Rights Reserved. Alle Rechte vorbehalten!

use strict;
use warnings;
use Data::Dumper;
our $VERSION = '0.1';

my $config = {};
my $logger = {};
my $users = {    # Session_ids und Anzahl der Portale pro eingeloggtem Clienten
                 #               'in_joints'=>{ joint_nr_IN => [user_id_OWN, joint_nr_OWN, user_nr_IN]                   },  'joints' => {joint_nr_OWN => ...}
                 #  'user1' => { 'in_joints'=>{ 0           => ['user6'    , 0           , 0         ]                   },  'joints' => { 0           => 'Karls Hof', 1=>'neue Welt' }  },
                 #  'user6' => { 'in_joints'=>{ 0           => ['user1'    , 0           , 0         ], 1=>['user1',1,0] },  'joints' => { 0           => 'mehr Raum'                 }  }
            };
my $joints = {  # Joint-name bzw -key  und ob sichtbar ist, welcher user server ist und welche clients verbunden sind
                
				#                                             'users_in'=>{ user_nr_IN => [user_id_IN, joint_nr_IN], ... }
				#  'Karls Hof' => {'nr'=>0, 'owner'=>'user1', 'users_in'=>{ 0          => ['user6'   , 0          ], ... } },
                #  'neue Welt' => {'nr'=>1, 'owner'=>'user1', 'users_in'=>{ 0          => ['user6'   , 1          ], ... } },
                #  'mehr Raum' => {'nr'=>0, 'owner'=>'user6', 'users_in'=>{ 0          => ['user1'   , 0          ], ... } },
             };

sub new {
	my $class = shift;
	$config = shift;    # uebergebene parameter bei new (was vorher $config war)
	$logger = shift;
	#my $self  = bless { @_ }, $class;
	my $self = bless {}, $class;
	return $self;
}

=pod

=head2 dummy

This method does something... apparently.

=cut
sub addUser {
	my ($self, $user_id) = @_;
	$users->{$user_id} = { 'in_joints'=>{}, 'joints' => {} } unless (exists($users->{$user_id}));
	$config->{'debug'} && print "---------------------- addUser($user_id) ----------------------\n";
	$config->{'debug'} && print "---- USER ----------------------".Dumper($users);
	$config->{'debug'} && print "---- JOINTS ----------------------".Dumper($joints);
}

sub toJoint {
	my ($self, $user_id, $joint_nr) = @_;
	if (exists($users->{$user_id}->{'in_joints'}->{$joint_nr}))
	{	 
		return @{ $users->{$user_id}->{'in_joints'}->{$joint_nr} }; # liefert (user_id_OWN, joint_nr_OWN, user_nr_IN)
	}
	else {
		return (-1,-1,-1); # kein in_joints mit dieser joint_nr
	}
}

sub fromJoint {
	my ($self, $user_id, $joint_nr, $reciever_nr) = @_;
	
	if ( exists($users->{$user_id}->{'joints'}->{$joint_nr}) ) # wenn der owner so eine joint_nr hat
	{	
		my $joint_id = $users->{$user_id}->{'joints'}->{$joint_nr};
		if ( exists($joints->{ $joint_id  }->{'users_in'}->{$reciever_nr}) ) {
			return @{ $joints->{ $joint_id  }->{'users_in'}->{$reciever_nr}  };  # liefert user_id_IN, joint_nr_IN
		}
		else {
			return (-1,-1); # es gibt keine uebereinstimmende nr der mit diesem joint verbundenen user_in
		}
	}
	else {
		return (-2,-2); #user ist KEIN OWNER von diesem JOINT
	}
}

# gets all reciever ids to send to more then one
sub fromJointBroadcast {
	my ($self, $user_id, $joint_nr) = @_;
	
	if ( exists($users->{$user_id}->{'joints'}->{$joint_nr}) ) # wenn der owner so eine joint_nr hat
	{	
		return $joints->{ $users->{$user_id}->{'joints'}->{$joint_nr}  }->{'users_in'};  # liefert hash aller [user_id_IN, joint_nr_IN] arrays		
	}
	else
	{
		return undef; #user ist KEIN OWNER von diesem JOINT
	}
}



sub getPortalList {
	my $message = "[";
        foreach my $joint_id ( keys %{$joints} ) {
            unless ($joints->{$joint_id}->{'hidden'}) {
                $message .= "," if ($message ne "[");                            
                #$message .= "'".Dumper($portals->{$portal_name})."'";
                $message .= "'".$joint_id."'";
                #$message .= "(" . Dumper($portals->{$portal_name}->{'user'}) . ")";
            }
        }
        $message .= "]";
        return $message;
}

sub deleteUser {
	my ($self, $user_id) = @_;
	
	if (exists($users->{$user_id})) # nur wenn der user existiert
	{
		$config->{'debug'} && print "---------------------- deleteUser($user_id) ----------------------\n";
		
		my $disconnect_list_OWN = [];
		my $disconnect_list_IN = [];
		
		foreach my $joint_nr_OWN ( keys %{ $users->{$user_id}->{ 'joints' } } ) #fuer jede joint_nr_OWN des owners
		{
			push @{$disconnect_list_IN}, @{deleteJoint($self, $user_id, $joint_nr_OWN)}; # liste aller user die zu einem joint dieses users connected sind
		}
		foreach my $joint_nr_IN ( keys %{ $users->{$user_id}->{ 'in_joints' } } ) #fuer jede joint_nr_IN des users diesen disconnecten
		{
			my ($user_id_OWN, $joint_nr_OWN, $user_nr_IN) = disconnect($self, $user_id, $joint_nr_IN);
			
			# liste aller owner, in deren joints dieser user drinne war
			push @{$disconnect_list_OWN},[$user_id_OWN, $joint_nr_OWN, $user_nr_IN] if ($user_id_OWN > -1);
		}
		
		delete $users->{$user_id};
		$config->{'debug'} && print "---- USER ----".Dumper($users);
		$config->{'debug'} && print "---- JOINTS --".Dumper($joints);
		
		return($disconnect_list_IN, $disconnect_list_OWN);
	}
	
	return(undef, undef); # FEHLER, user ex. nicht!!!
}

sub deleteJoint {
	my ($self, $user_id, $joint_nr_OWN) = @_;
	
	my $joint_id = $users->{$user_id}->{ 'joints' }->{$joint_nr_OWN};
	
	if (exists($joints->{$joint_id})) # nur wenn der joint existiert
	{
		my $disconnect_list = [];
		
		$config->{'debug'} && print "---------------------- deleteJoint($joint_id) ----------------------\n";
		foreach my $user_nr ( keys %{ $joints->{$joint_id}->{ 'users_in' } } ) #fuer jeden zum joint connected user
		{   
			my ($user_id_IN, $joint_nr_IN) = @{  $joints->{$joint_id}->{ 'users_in' }->{ $user_nr }  };
			my @is_error = disconnect( $self, $user_id_IN, $joint_nr_IN );
			push @{$disconnect_list},[$user_id_IN, $joint_nr_IN] if ($is_error[0] != -1);
		}
		# den OWNER ermitteln und dort den joint rausloeschen
		if ( exists( $users->{ $joints->{$joint_id}->{ 'owner' } }->{ 'joints' }->{  $joints->{$joint_id}->{ 'nr' }  }  ) )
		{
			delete $users->{ $joints->{$joint_id}->{ 'owner' } }->{ 'joints' }->{  $joints->{$joint_id}->{ 'nr' }  };
		}
		
		delete $joints->{$joint_id};
		$config->{'debug'} && print "---- USER ---".Dumper($users);
		$config->{'debug'} && print "---- JOINTS -".Dumper($joints);
		
		return($disconnect_list); # gibt liste mit allen [$user_id_IN, $joint_nr_IN] zurueck die disconencted wurden
	}
	
	return(undef); # FEHLER, joint ex. nicht!!!
}

sub disconnect {
	my ($self, $user_id, $joint_nr) = @_;
	if ( exists( $users->{ $user_id }->{ 'in_joints' } )  &&  exists( $users->{ $user_id }->{ 'in_joints' }->{ $joint_nr } ) )
	{

		$config->{'debug'} && print "---------------------- disconnect($user_id, $joint_nr) ----------------------\n";
		
		my ($user_id_OWN, $joint_nr_OWN, $user_nr_IN) = @{ $users->{ $user_id }->{ 'in_joints' }->{ $joint_nr } };
		
		$config->{'debug'} && print 'delete $users->{ '.$user_id.' }->{ in_joints }->{ '.$joint_nr.' }'."\n";
		delete $users->{ $user_id }->{ 'in_joints' }->{ $joint_nr };
		
		$config->{'debug'} && print "OWNER_ID = ".$user_id_OWN."\n";
		
		if ( exists( $users->{ $user_id_OWN })
		&& exists($users->{ $user_id_OWN }->{'joints'}) # TODO: ist das nicht immer mind. vorhanden -> optimieren!
		&& exists($users->{ $user_id_OWN }->{'joints'}->{ $joint_nr_OWN })  )
		{
			my $joint_id = $users->{ $user_id_OWN }->{'joints'}->{ $joint_nr_OWN };
			
			$config->{'debug'} && print "JOINT_ID OK  = ".$joint_id."\n";
			
			if( exists( $joints->{ $joint_id }->{'users_in'})
			&&  exists( $joints->{ $joint_id }->{'users_in'}->{ $user_nr_IN } ) )
			{
				$config->{'debug'} && print 'delete $joints->{ '.$joint_id.' }->{ users_in }->{ '.$user_nr_IN.' }'."\n";
				delete $joints->{ $joint_id }->{ 'users_in' }->{ $user_nr_IN };
			}
		}
		$config->{'debug'} && print "---- USER ---".Dumper($users);
		$config->{'debug'} && print "---- JOINTS -".Dumper($joints);
		
		return ($user_id_OWN, $joint_nr_OWN, $user_nr_IN); # Todo: eigetnlich muss ja immer ein owner+ joint sein, wenn nciht -> fehler?
	}
	else
	{	return(-1,-1,-1);
	}

}
	

sub create {
	my ($self, $user_id, $joint_id) = @_;
	
        unless (exists($joints->{$joint_id}))
		{

			my $joint_nr = getKeyByInsert( $users->{$user_id}->{'joints'}, $joint_id, 0, 127 );
			
			if ($joint_nr > -1)
			{
				$joints->{$joint_id} = {'nr'=>$joint_nr, 'owner'=> $user_id , 'users_in'=>{} };
				$config->{'debug'} && print "---------------------- create:($user_id, $joint_id) ----------------------\n";
				$config->{'debug'} && print "---- USER ---".Dumper($users);
				$config->{'debug'} && print "---- JOINTS -".Dumper($joints);
				return $joint_nr;
			}
			else
			{
				return -1; #full, also mehr als 127 kann ein Joint-Owner nur gleichzeitig offen halten
			}
        }
        return -2; # es existiert schon ein gleichnamiger joint
}

sub connect {
	my ($self, $user_id, $joint_id) = @_;

	if (exists($joints->{$joint_id}))
	{
		return (-2,-2) if ($joints->{$joint_id}->{'owner'} == $user_id); # der joint gehoert einem selber
		
		foreach my $user_nr ( keys %{ $joints->{$joint_id}->{ 'users_in' } } )
		{	
			if ($joints->{$joint_id}->{ 'users_in' }->{$user_nr}->[0] eq $user_id )
			{	
				return (-3, -3, -3, -3); # nicht 2 mal in den selben joint
			}
		}
		
		# todo: vieleicht vorher die laenge der keys checken, um sicherzugehen das <=255 user pro joint und <=128 in-joints pro user
		
		my $user_nr_IN = getKeyByInsert( $joints->{$joint_id}->{ 'users_in' }, [], 0, 255);
		if ($user_nr_IN > -1)
		{
			my $joint_nr_IN = getKeyByInsert( $users->{$user_id}->{'in_joints'}, [], 0, 127);
			if ($joint_nr_IN > -1)
			{
				$joints->{$joint_id}->{ 'users_in' }->{$user_nr_IN} = [$user_id, $joint_nr_IN];
				$users->{$user_id}->{'in_joints'}->{ $joint_nr_IN } = [ $joints->{$joint_id}->{ 'owner' }, #user_id_OWN
																		$joints->{$joint_id}->{ 'nr' } ,   #joint_nr_OWN
																		$user_nr_IN ];                     #user_nr_IN
				$config->{'debug'} && print "---------------------- connect($user_id, $joint_id) ----------------------\n";
				$config->{'debug'} && print "---- USER ----------------------".Dumper($users);
				$config->{'debug'} && print "---- JOINTS ----------------------".Dumper($joints);
				return ($user_nr_IN, $joint_nr_IN, $joints->{$joint_id}->{ 'owner' }, $joints->{$joint_id}->{ 'nr' } );
			}
			else
			{
				delete $joints->{$joint_id}->{ 'users_in' }->{$user_nr_IN};
				return (-5, -5, -5, -5); # full, der user ist mit schon mit max. 128 joints verbunden
			}
		}
		else
		{	return (-4, -4, -4, -4); # full, also mehr als 256 user_nr sind schon mit diesem Joint verbunden
		}
		
	}
	return (-1, -1, -1, -1); # es gibt keinen joint mit dieser id 
}







sub getKeyByInsert {
	my ($hash, $id, $min, $max) = @_;
	my $nr= $min;
	while (exists($hash->{$nr}) && $nr <= $max)
	{
		$nr++;
	}
	if ($nr <= $max) {
		$hash->{$nr} = $id;
		return $nr;
	}
	else {
		return -1;
	}
}








1;

=pod

=head1 SUPPORT

No support is available

=head1 AUTHOR

Copyright 2012 Anonymous.

=cut

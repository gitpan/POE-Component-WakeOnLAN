package POE::Component::WakeOnLAN;

use strict;
use warnings;
use Socket;
use Carp;
use IO::Socket::INET;
use Net::IP;
use POE;
use vars qw($VERSION);

$VERSION = '1.02';

sub wake_up {
  my $package = shift;
  my %params = @_;
  $params{lc $_} = delete $params{$_} for keys %params;
  croak "$package wake_up requires a 'macaddr' parameter\n" unless $params{macaddr};
  croak "$package wake_up requires an 'event' parameter\n" unless $params{event};
  $params{macaddr} =~ s/://g;
  $params{port} = 9 unless $params{port} and $params{port} =~ /^\d+$/;
  $params{address} = '255.255.255.255' unless $params{address} and Net::IP::ip_get_version( $params{address} );
  my $options = delete $params{options};
  my $self = bless \%params, $package;
  $self->{session_id} = POE::Session->create(
	object_states => [
		$self => [qw(_start _ready)],
	],
	heap => $self,
	( ref($options) eq 'HASH' ? ( options => $options ) : () ),
  )->ID();
  return $self;
}

sub _start {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  $self->{session_id} = $_[SESSION]->ID();
  if ( $kernel == $sender and !$self->{session} ) {
	croak "Not called from another POE session and 'session' wasn't set\n";
  }
  my $sender_id;
  my $session = delete $self->{session};
  if ( $session ) {
    if ( my $ref = $kernel->alias_resolve( $self->{session} ) ) {
	$sender_id = $ref->ID();
    }
    else {
	croak "Could not resolve 'session' to a valid POE session\n";
    }
  }
  else {
    $sender_id = $sender->ID();
  }
  $kernel->refcount_increment( $sender_id, __PACKAGE__ );
  $self->{sender_id} = $sender_id;
  my $sock = new IO::Socket::INET(Proto=>'udp') || return;
  my $ip_addr = inet_aton( $self->{address} );
  my $sock_addr = sockaddr_in($self->{port}, $ip_addr);
  my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $self->{macaddr} x 16);
  $kernel->select_write( $sock, '_ready' );
  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1);
  send($sock, $packet, 0, $sock_addr);
  return;
}

sub _ready {
  my ($kernel,$self,$socket) = @_[KERNEL,OBJECT,ARG0];
  $kernel->select_write( $socket );
  my $response = { };
  $response->{$_} = $self->{$_} for keys %{ $self };
  delete $response->{session_id};
  my $sender_id = delete $response->{sender_id};
  my $event = delete $response->{event};
  $kernel->post( $sender_id, $event, $response );
  $kernel->refcount_decrement( $sender_id, __PACKAGE__ );
  return;
}

1;
__END__

=head1 NAME

POE::Component::WakeOnLAN - A POE Component to send packets to power on computers.

=head1 SYNOPSIS

  use strict;
  use warnings;
  use Data::Dumper;
  use POE;
  use POE::Component::WakeOnLAN;
  
  my $mac_address = '00:0a:e4:4b:b0:94';
  
  POE::Session->create(
     package_states => [
  	'main' => [qw(_start _response)],
     ],
  );
  
  
  $poe_kernel->run();
  exit 0;
  
  sub _start {
    POE::Component::WakeOnLAN->wake_up( 
  	macaddr => $mac_address,
  	event   => '_response',
    );
    return;
  }
  
  sub _response {
    print Dumper( $_[ARG0] );
    return;
  }

=head1 DESCRIPTION

POE::Component::WakeOnLAN is a L<POE> component that sends wake-on-lan (AKA magic) 
packets to turn on machines that are wake-on-lan capable.

It is based on the L<Net::Wake> module by Clinton Wong.

=head1 CONSTRUCTOR

=over

=item C<wake_up>

Sends a wake-on-lan packet via UDP. Takes a number of parameters:

  'macaddr', the MAC Address of the host to wake up, mandatory;
  'event', the event handler in your session where the result should be sent, mandatory;
  'address', the IP address of the host to wake up, defaults to 255.255.255.255;
  'port', the UDP port to communicate with, defaults to 9;
  'session', optional if the poco is spawned from within another session;
  'options', a hashref of POE Session options to pass to the component;

Generally speaking, you should use a broadcast address for C<address> ( the component defaults 
to using C<255.255.255.255> if one is not supplied ), Using the host's last known IP address 
is usually not sufficient since the IP address may no longer be in the ARP cache.

If you wish to send a magic packet to a remote subnet, you can use a variation of '192.168.0.255', 
given that you know the subnet mask to generate the proper broadcast address.

The C<session> parameter is only required if you wish the output event to go to a different
session than the calling session, or if you have spawned the poco outside of a session.

You may pass through any arbitary parameters you like, though they must be prefixed with an
underscore to prevent future parameter clashes. These will be returned to you in the resultant
event response.

The poco does it's work and will return the output event with the result.

=back

=head1 OUTPUT EVENT

This is generated by the poco. ARG0 will be a hash reference with the following keys:

  'macaddr', the MAC address that was specified, the poco strips ':';
  'address', the IP address that was used;
  'port', the UDP port that was used;

Plus an arbitary key/values that were passed.

=head1 AUTHOR

Chris C<BinGOs> Williams <chris@bingosnet.co.uk>

Clinton Wong

=head1 LICENSE

Copyright E<copy> Chris Williams and Clinton Wong.

This module may be used, modified, and distributed under the same terms as Perl itself. Please see the license that came with your Perl distribution for details.

=head1 SEE ALSO

L<POE>

L<Net::Wake>

L<http://gsd.di.uminho.pt/jpo/software/wakeonlan/mini-howto/>

=cut

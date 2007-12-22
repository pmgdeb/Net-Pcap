#!perl -T
use strict;
use Test::More;
use Net::Pcap;
use lib 't';
use Utils;


# first check than POE is available
plan skip_all => "POE is not available" unless eval "use POE; 1";

# then check than POE::Component::Pcap is available
plan skip_all => "POE::Component::Pcap is not available"
    unless eval "use POE::Component::Pcap; 1";
my $error = $@;

plan tests => 18;
is( $error, '', "use POE::Component::Pcap" );

# string-eval'd because POE is loaded at run-time and its variables 
# constants used in the code below will cause a compile error
eval <<'CODE'; die $@ if $@;

my $dev = find_network_device();

SKIP: {
    skip "must be run as root", 17 unless is_allowed_to_use_pcap();
    skip "no network device available", 17 unless $dev;

    #diag "[POE] create";
    POE::Session->create(
        inline_states => {
            _start      => \&start,
            _stop       => \&stop, 
            got_packet  => \&got_packet,
        },
    );

    #diag "[POE] run";
    $poe_kernel->run;
}


sub start {
    #diag "[POE:start] spawning new Pcap session ", $_[SESSION]->ID, " on device $dev";
    POE::Component::Pcap->spawn(
        Alias => 'pcap',  Device => $dev,
        Dispatch => 'got_packet',  Session => $_[SESSION],
    );

    $_[KERNEL]->post(pcap => open_live => $dev);
    $_[KERNEL]->post(pcap => 'run');
}

sub stop {
    #diag "[POE:stop]";
    $_[KERNEL]->post(pcap => 'shutdown');
}

sub got_packet {
    #diag "[POE:got_packet]";
    my $packets = $_[ARG0];

    # process the first packet only
    process_packet(@{ $packets->[0] });

    # send a message to stop the capture
    $_[KERNEL]->post(pcap => 'shutdown');
}

sub process_packet {
    #diag "[POE:process_packet]";
    my ($header, $packet) = @_;

    ok( defined $header,        " - header is defined" );
    isa_ok( $header, 'HASH',    " - header" );

    for my $field (qw(len caplen tv_sec tv_usec)) {
        ok( exists $header->{$field}, "    - field '$field' is present" );
        ok( defined $header->{$field}, "    - field '$field' is defined" );
        like( $header->{$field}, '/^\d+$/', "    - field '$field' is a number" );
    }

    ok( $header->{caplen} <= $header->{len}, 
        "    - coherency check: packet length (caplen <= len)" );

    ok( defined $packet,        " - packet is defined" );
    is( length $packet, $header->{caplen}, " - packet has the advertised size" );
}

CODE

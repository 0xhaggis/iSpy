#!/usr/bin/perl
use strict;

open my $fh, '<&STDIN';
open my $out, ">webroot.c";
binmode($fh);
binmode($out);

print $out "const char *webrootZIPData=";

my $bytes, my $total = 0;
my $bytes_read, my $bytesToRead = 32;
do {
	$bytes_read = read $fh, $bytes, $bytesToRead;
	$total += $bytes_read;
	if($bytes_read > 0) {
		my $hexVersion = unpack("H*", $bytes);
		$hexVersion =~ s/([0-9a-f]{2})/\\x$1/g;
		print $out "\"$hexVersion\"\\\n";
	}
} while $bytes_read == $bytesToRead;

print $out "\"\";\n";
print $out "unsigned int WEBROOT_SIZE=$total;\n";

close($out);
close($fh);





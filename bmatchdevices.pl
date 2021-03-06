#!/usr/bin/perl -w
#
# This program was written by Philippe CHAUVAT (philippe@chauvat.eu)
# You can use this program accordingly to the LICENCE file in this project.
use File::Basename ;
#
# The following value is a suffix to prevent file overwrite as the script does not verify anything in this matter.
$SECURITYFILEXT="pct" ;
#
# Required system tools
my @features = ("lsscsi","mtx","mt --version") ;
my @message = () ;
foreach my $f (@features) {
    open(CHECK,$f . "|") or push @message,$f ;
    close(CHECK) ;
}
if (defined($message[0])) {
    print "The following feature" . $#message > 1?'s are':' is' . " missing\n" ;
    foreach my $f (@message) {
	print "\t$f\n" ;
    }
    print "and required for the script to run.\n" ;
    exit(-1) ;
}
#
# Found devices
my %devices = () ;
my @tab ;
# Change debug value to something positive to enable more output.
# TODO: improve this to make it an arg on the command line.
my $debug = 0 ;
#
# Devices identification
print "Autoloader(s) identification process...\n" ;
open(DEVICES, "lsscsi -g|")    || die "can't fork lsscsi: $!";
while (<DEVICES>) {
    print "$_\n" if $debug ;
    my ($addr, $media, $brand, $name, $firmware, $device, $generic) ;
    s/^([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+(.*)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)/$addr=$1,$media=$2,$brand=$3,$name=$4,$firmware=$5,$device=$6,$generic=$7/eo ;
    print join("\t",$addr,$media,$brand,$name,$firmware,$device,$generic,"\n") if $debug ;
    my $prefix = "" ;
    my $thedevice = "" ;
    if ($media =~ /mediumx/) {
	$thedevice = $generic ;
    }
    if ($media =~ /tape/) {
    	# n form is for no-rewind devices.
	$prefix = "n" ;
	$thedevice = $device ;
    }
    if ($thedevice ne "") {
    	# Make $name variable without any space (leading or contained)
	$name =~ s/\s+$// ;
	$name =~ s/\s+/_/ ;
	# Change SCSI address like [a:b:c:d] as abcd
	$addr =~ s/\[//g ;
	$addr =~ s/\]//g ;
	$addr =~ s/://g ;
	# /dev/sg4 will become sg4
	# /dev/st1 will become nst1
	$thedevice = $prefix . basename($thedevice) ;
	# Building the hash
	$devices{$addr}{'type'} = $media ;
	$devices{$addr}{'brand'} = $brand ;
	$devices{$addr}{'name'} = $name ;
	$devices{$addr}{'addr'} = $thedevice ;
	print "Key: " . $addr . "\tName: " . $name . "\tAddress: " . $thedevice . "\tType: " . $media . "\n" if ($debug) ;
    }
}
close(DEVICES) || die "can't close lsscsi: $!";
#
# Looking for equivalent devices
# TODO: Make sure these are sufficient.
my @devdirs = ("/dev", "/dev/tape/by-id", "/dev/tape/by-path") ;
my %hash ;
foreach $d (@devdirs) {
    if ( -x $d ) {
	opendir(my $dh, $d) || die "Can't open $d: $!";
        while (my $ldir = readdir($dh)) {
            if (-l "$d/$ldir") {
		$linked = basename(readlink "$d/$ldir") ;
		$hash{$linked} = "$d/$ldir" if !defined($hash{$linked}) ;
		print $linked . " refers to\t" . $hash{$linked} . "\n" if ($debug) ;
	    }
        }
        closedir $dh;
    }
}
#
# Matching part
my @robots = () ;
my @keydrives = (); 
my $line ;
foreach my $key (keys(%devices)) {
    print "Key: $key\n" if $debug ;
    if (defined($hash{$devices{$key}{'addr'}})) {
	print "Addr: " . $devices{$key}{'addr'} . "\tHash: " . $hash{$devices{$key}{'addr'}} . "\n" if $debug ;
	if ($devices{$key}{'type'} =~ /mediumx/) {
	    push @robots,$key ;
	    open(MTX, "mtx -f " . $hash{$devices{$key}{'addr'}} . " status|")    || die "can't fork mtx: $!";
	    while (<MTX>) {
		@tab = split /:/, $_ ;
		@tab = split/\s+/, $tab[1] ;
		$devices{$key}{'drives'} = $tab[0] ;
		print $tab[0] . " drive" . ($tab[0] == 1 ? "":"s") . " belongs to " . $hash{$devices{$key}{'addr'}} . "\n" ;
		for (my $j = 0; $j < $tab[0]; $j++) {
		    $line = <MTX> ;
		    if ($line =~ /Full/) {
			my $slot ;
			# Data Transfer Element 0:Full (Storage Element 1 Loaded):VolumeTag = G03001TA
			$line =~ s/.*Storage\s+Element\s+([0-9]+).*/$slot=$1/eo ;
			my $command = join(' ',"mtx -f",$hash{$devices{$key}{'addr'}},"unload",$slot,$j) ;
			print $command . "\n" if ($debug) ;
			system($command) ;
		    }
		}
		print "Looking for a tape...\n" if ($debug) ;
		$line = <MTX> ;
		$slot = 0 ;
		do {
		    print "$line" if ($debug) ;
		    # Storage Element 1:Full :VolumeTag=E01100L4
		    if ($line =~ /.*Full.*/) {
			$line =~ s/^\s+Storage\s+Element\s+([0-9]+).*/$slot=$1/eo ;
			print $slot . " found\n" if ($debug) ;
		    }
		    $line = <MTX> ;
		} until ($slot!= 0) ;
		$devices{$key}{'fullslot'} = $slot ;
		last ;
	    }
	    close(MTX) ;

	}
	elsif ($devices{$key}{'type'} =~ /tape/) {
	    push @keydrives,$key ;
	    print "$key is a tape drive\n" if ($debug) ;
	}
	else {
	    print "$key inknonwn for " . $devices{$key}{'type'} . "\n" if ($debug) ;
	}
    }
}
# At this point:
# - autoloaders are identified and matched with their usuful name
# - devices are identified but matching is not done
# - there are no tape in any drive
foreach my $r (@robots) {
    print "Autoloader $r has " . $devices{$r}{'drives'} . " drives\n" if ($debug) ;
    for (my $i=0; $i< $devices{$r}{'drives'}; $i++) {
	print "Drive $i\n" if ($debug) ;
	my $command = join(' ',"mtx -f",$hash{$devices{$r}{'addr'}},"load",$devices{$r}{'fullslot'},$i) ;
	print "load command: $command\n" if ($debug) ;
	system($command) ;
	foreach my $thekey (@keydrives) {
	    $command = join(' ',"mt -f",$hash{$devices{$thekey}{'addr'}},"status|") ;
	    print "mt status command: $command\n" if ($debug) ;
	    open(DRIVE,$command)    || die "can't fork mt: $!";
	    while (<DRIVE>) {
	        # mt status worked and is able to read something
		if (/ONLINE/) {
		    $devices{$r}{$i} = $thekey ;
		    print "Drive $thekey found as drive $i for autoloader " . $hash{$devices{$r}{'addr'}} . "\n" if ($debug) ;
		    last ;
		}
	    }
	    close(DRIVE) ;
	    last if (defined($devices{$r}{$i})) ;
	}
	$command = join(' ',"mtx -f",$hash{$devices{$r}{'addr'}},"unload",$devices{$r}{'fullslot'},$i) ;
	print "mtx unload command: $command\n" if ($debug) ;
	system($command) ;
    }
    #
    # Building Bacula configuration files
    my $robotconf = join('_',$devices{$r}{'name'},$SECURITYFILEXT . ".conf") ;
    open(ROBOT,">" . $robotconf) or die "$robotconf: Unable to create Bacula autoloader configuration file: $!\n" ;
    print "Creating $robotconf file\n" ;
    print ROBOT "Autochanger {\n" ;
    print ROBOT "\tName = " . $devices{$r}{'name'} . "\n" ;
    for (my $i=0; $i<$devices{$r}{'drives'};$i++) {
	my $deviceaddress = $devices{$r}{$i} ;
	my $devicename = join('_',$devices{$deviceaddress}{'name'},$i) ;
	print ROBOT "\tDevice = " . $devicename . "\n" ;
	my $driveconf = join('_',$devicename,$SECURITYFILEXT . ".conf") ;
	open(DRIVE,"> " . $driveconf) or die "$driveconf: Unable to create Bacula device configuration file: $!\n" ;
	print "Creation $driveconf file\n" ;
	print DRIVE "Device {\n" ;
	print DRIVE "       Name = $devicename\n" ;
	print DRIVE "       Drive Index = $i\n" ;
	print DRIVE "       Media Type = " . $devices{$r}{'name'} ."\n" ;
	print DRIVE "       Archive Device = " . $hash{$devices{$deviceaddress}{'addr'}} ."\n" ;
	print DRIVE "       AutomaticMount = yes\n" ;
	print DRIVE "       AlwaysOpen = yes\n" ;
	print DRIVE "       Offline On Unmount = no\n" ;
	print DRIVE "       Alert Command = \"sh -c 'smartctl -H -l error %c'\"\n";
	print DRIVE "}\n" ;
	close(DRIVE) ;
    }
    print ROBOT "       Changer Command = \"/opt/bacula/scripts/mtx-changer %c %o %S %a %d\"\n" ;
    print ROBOT "       Changer Device = " . $hash{$devices{$r}{'addr'}} . "\n" ;
    print ROBOT "}\n" ;
    close(ROBOT) ;
}
1 ;

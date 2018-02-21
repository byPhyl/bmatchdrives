#!/usr/bin/perl -w
#
# This program was written by Philippe CHAUVAT (philippe@chauvat.eu)
# You can use this program
use File::Basename ;
#
# Fonctions necessaires
my @features = ("lsscsi","mtx","mt --version") ;
my @message = () ;
foreach my $f (@features) {
    open(CHECK,$f . "|") or push @message,$f ;
    close(CHECK) ;
}
if (defined($message[0])) {
    print "La(es) fonction(s) suivante(s) manque(nt):\n" ;
    foreach my $f (@message) {
	print "\t$f\n" ;
    }
    print "Elles sont nécessaires au bon fonctionnement de ce programme.\n" ;
    exit(-1) ;
}
#
# devices
my %devices = () ;
my @tab ;
my $debug = 0 ;
#my @addresses ;
#
# Identification des devices
print "Identification des robots....\n" ;
open(DEVICES, "lsscsi -g|")    || die "can't fork lsscsi: $!";
while (<DEVICES>) {
    my $l = $_ ;
    print "$l\n" if $debug ;
    my ($addr, $media, $brand, $name, $firmware, $device, $generic) ;
    $l =~ s/^([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+(.*)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)/$addr=$1,$media=$2,$brand=$3,$name=$4,$firmware=$5,$device=$6,$generic=$7/eo ;
    print join("\t",$addr,$media,$brand,$name,$firmware,$device,$generic,"\n") if $debug ;
    my $prefix = "" ;
    my $thedevice = "" ;
    if ($media =~ /mediumx/) {
	$thedevice = $generic ;
    }
    if ($media =~ /tape/) {
	$prefix = "n" ;
	$thedevice = $device ;
    }
    if ($thedevice ne "") {
	$name =~ s/\s+$// ;
	$name =~ s/\s+/_/ ;
	$addr =~ s/\[//g ;
	$addr =~ s/\]//g ;
	$addr =~ s/://g ;
	$thedevice = $prefix . basename($thedevice) ;
	$devices{$addr}{'type'} = $media ;
	$devices{$addr}{'brand'} = $brand ;
	$devices{$addr}{'name'} = $name ;
	$devices{$addr}{'addr'} = $thedevice ;
	print "Key: " . $addr . "\tName: " . $name . "\tAdresse: " . $thedevice . "\tType: " . $media . "\n" if ($debug) ;
    }
}
close(DEVICES) || die "can't close lsscsi: $!";
#
# Recherche des devices équivalents
my @devdirs = ("/dev", "/dev/tape/by-id") ;
my %hash ;
foreach $d (@devdirs) {
    if ( -x $d ) {
	opendir(my $dh, $d) || die "Can't open $d: $!";
        while (my $ldir = readdir($dh)) {
            if (-l "$d/$ldir") {
		$linked = basename(readlink "$d/$ldir") ;
		$hash{$linked} = "$d/$ldir" ;
		print $linked . " pointe sur\t" . $hash{$linked} . "\n" if ($debug) ;
	    }
        }
        closedir $dh;
    }
}
@devdirs = ("/dev", "/dev/tape/by-path") ;
foreach $d (@devdirs) {
    if ( -x $d ) {
	opendir(my $dh, $d) || die "Can't open $d: $!";
        while (my $ldir = readdir($dh)) {
            if (-l "$d/$ldir") {
		$linked = basename(readlink "$d/$ldir") ;
		$hash{$linked} = "$d/$ldir" ;
		print $linked . " pointe sur\t" . $hash{$linked} . "\n" if ($debug) ;
	    }
        }
        closedir $dh;
    }
}
#
# Rapprochement
my @robots = () ;
my @drives = (); 
my $line ;
foreach my $key (keys(%devices)) {
    print "Key: $key\n" if $debug ;
    if (defined($hash{$devices{$key}{'addr'}})) {
	print $devices{$key}{'addr'} . "\t" . $hash{$devices{$key}{'addr'}} . "\n" if $debug ;
	if ($devices{$key}{'type'} =~ /mediumx/) {
	    push @robots,$key ;
	    open(MTX, "mtx -f " . $hash{$devices{$key}{'addr'}} . " status|")    || die "can't fork mtx: $!";
	    while (<MTX>) {
		@tab = split /:/, $_ ;
		@tab = split/\s+/, $tab[1] ;
		$devices{$key}{'drives'} = $tab[0] ;
		print $tab[0] . " drive" . ($tab[0] == 1 ? "":"s") . " sur le robot" . $hash{$devices{$key}{'addr'}} . "\n" ;
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
		print "Recherche d'une bande présente dans le robot...\n" if ($debug) ;
		$line = <MTX> ;
		$slot = 0 ;
		do {
		    print "$line" if ($debug) ;
		    # Storage Element 1:Full :VolumeTag=E01100L4
		    if ($line =~ /.*Full.*/) {
			$line =~ s/^\s+Storage\s+Element\s+([0-9]+).*/$slot=$1/eo ;
			print $slot . " trouvé\n" if ($debug) ;
		    }
		    $line = <MTX> ;
		} until ($slot!= 0) ;
		$devices{$key}{'fullslot'} = $slot ;
		last ;
	    }
	    close(MTX) ;

	}
	elsif ($devices{$key}{'type'} =~ /tape/) {
	    push @drives,$key ;
	    print "$key est un lecteur\n" if ($debug) ;
	}
	else {
	    print "$key inconnu pour " . $devices{$key}{'type'} . "\n" if ($debug) ;
	}
    }
}
# Ici:
# Les robots sont identifiés et appariés
# Les drives sont identifiés non appariés
# Les drives sont libres de toute bande
foreach my $r (@robots) {
    print "Robot $r\n" if ($debug) ;
    for (my $i=0; $i< $devices{$r}{'drives'}; $i++) {
	print "Drive $i\n" if ($debug) ;
	my $command = join(' ',"mtx -f",$hash{$devices{$r}{'addr'}},"load",$devices{$r}{'fullslot'},$i) ;
	print "load command: $command\n" if ($debug) ;
	system($command) ;
	foreach my $d (@drives) {
	    $command = join(' ',"mt -f",$hash{$devices{$d}{'addr'}},"status|") ;
	    print "mt status command: $command\n" if ($debug) ;
	    open(DRIVE,$command)    || die "can't fork mt: $!";
	    while (<DRIVE>) {
		if (/ONLINE/) {
		    $devices{$r}{$i} = $d ;
		    print "Drive $d trouvé comme drive $i du robot " . $hash{$devices{$r}{'addr'}} . "\n" if ($debug) ;
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
    # Construction des fichiers de configuration Bacula
    my $robotconf = $devices{$r}{'name'} . "_tic.conf" ;
    open(ROBOT,">" . $robotconf) or die "Impossible de créer le fichier $robotconf: $!\n" ;
    print ROBOT "Autochanger {\n" ;
    print ROBOT "\tName = " . $devices{$r}{'name'} . "\n" ;
    for (my $i=0; $i<$devices{$r}{'drives'};$i++) {
	my $deviceaddress = $devices{$r}{$i} ;
	my $devicename = $devices{$deviceaddress}{'name'}  . "_" . $i ;
	print ROBOT "\tDevice = " . $devicename . "\n" ;
	my $driveconf = join('_',$devicename,"tic.conf") ;
	open(DRIVE,"> " . $driveconf) or die "Impossible de créer le fichier $driveconf; $!\n" ;
	print DRIVE "Device {\n" ;
	print DRIVE "\tName = $devicename\n" ;
	print DRIVE "\tDrive Index = $i\n" ;
	print DRIVE "\tMedia Type = " . $devices{$r}{'name'} ."\n" ;
	print DRIVE "\tArchive Device = " . $hash{$devices{$deviceaddress}{'addr'}} ."\n" ;
	print DRIVE "\tAutomaticMount = yes\n" ;
	print DRIVE "\tAlwaysOpen = yes\n" ;
	print DRIVE "\tOffline On Unmount = no\n" ;
	print DRIVE "\tAlert Command = \"sh -c 'smartctl -H -l error %c'\"\n";
	print DRIVE "}\n" ;
	close(DRIVE) ;
    }
    print ROBOT "\tChanger Command = \"/opt/bacula/scripts/mtx-changer %c %o %S %a %d\"\n" ;
    print ROBOT "\tChanger Device = " . $hash{$devices{$r}{'addr'}} . "\n" ;
    print ROBOT "}\n" ;
    close(ROBOT) ;
}
1 ;

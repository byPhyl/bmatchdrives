# bmatchdrives
How to match your drives in your autoloaders for Bacula 

Purpose
When setting up a new autoloader (aka tape librairy with Bacula) you must define both the autoloader and the drives accordingly to the way they are set up in the real life
The usualy way is to request your autoloader and drives and create everything by yourself

This script is just that: the same but automatized.

What does it take?
You must have an autoloader, directly connected to your server, at least one tape drive. At this time, the only situations that have been tested are one Tape Library/SAS attachment and mhVTL environment. Therefore, there is NO GUARANTEE it will work with SCSI or FC even there is no reason it would not.

Required tools
lsscsi, mt (mt-st actually), mtx are required.

How it works
The script:
1) requests lsscsi, identify mediumx and tape devices.
2) determines the soft links to the drives and library, number of drives, and so on
3) find the match between drives and libray (which drive in which library at what place)
4) build Bacula default configuration files for all drives and libraries. File naming is based on device names.

$!===========================================================================
$!
$! Title:       OPENFILES_XFSERVER.COM
$!
$! Description: Lists the data files (ISAM and RELATIVE) opened by all
$!              xfServer processes (SYNLAU_<pid>)
$!
$! Usage:       $ @OPENFILES_XFSERVER
$!
$! Author:      Steve Ives (steve.ives@synergex.com)
$!
$!===========================================================================
$!
$!      Make sure we have the required privileges
$       requiredPrivs = "SYSPRV,BYPASS,GROUP,WORLD"
$       originalPrivs = f$setprv(requiredPrivs)
$!
$       if f$privilege(requiredPrivs).eqs."FALSE"
$       then
$               write sys$output "%OPENFILES-E-NOPRIV, Insufficient privilege"
$               write sys$output "-OPENFILES-I-REQPRIV, Required privilages are ''requiredPrivs'"
$               exit 1
$       endif
$!
$!      Should be good to go
$       dataFile = "SYS$SCRATCH:" + f$unique() + ".TMP"
$       openFiles = 0
$       open/write dataChn 'dataFile
$!
$!      Iterate through all disks
$nextDisk:
$       nextDisk = f$device(,"DISK")
$       if "''nextDisk'".eqs."" then goto noMoreDisks
$!
$!      Only process mounted disks
$       if f$getdvi(nextDisk,"MNT").eqs."TRUE"
$       then
$!              Write all "non-system" open files to a temp file
$               deviceFile = "SYS$SCRATCH:" + f$unique() + ".TMP"
$               show device/files/nosystem/out='deviceFile 'nextDisk
$!
$!              Process the temp file
$               open/read deviceChn 'deviceFile
$nextFile:      read/end=noMoreFiles deviceChn data
$!
$!              Only process records for SYNLAU_<pid> processes
$               processName = f$extract(0,7,data)
$               if "''processName'".nes."SYNLAU_" then goto nextFile
$!
$!              Add the current device name to make a full file spec
$               candidateFileSpec = "''nextDisk'" + f$extract(26,f$length(data),data)
$!
$!              Ignore all files except ISAM and RELATIVE
$               fileType = f$file_attributes(candidateFileSpec,"ORG")
$               if "''fileType'".nes."IDX" .and. "''fileType'".nes."REL" then goto nextFile
$!
$!              We have a winner!
$               write dataChn "''candidateFileSpec'"
$               openFiles = openFiles + 1
$               goto nextFile
$!
$!              All done with this disk
$noMoreFiles:   close deviceChn
$               delete/nolog/noconf 'deviceFile;*
$       endif
$!
$       goto nextDisk
$!
$noMoreDisks:
$!
$       close dataChn
$!
$       write sys$output ""
$       if openFiles .gt. 0
$       then
$               write sys$output "Open data files for all xfServer processes (SYNLAU_*)"
$               write sys$output ""
$               open/read resultsChn 'dataFile
$!
$nextResult:    read/end=noMoreResults resultsChn data
$               write sys$output "''data'"
$               goto nextResult
$!
$noMoreResults: close resultsChn
$               delete/nolog/noconf 'dataFile;*
$       else
$               write sys$output "No open data files found for xfServer processes (SYNLAU_*)"
$       endif
$       write sys$output ""
$!
$       exit
$!
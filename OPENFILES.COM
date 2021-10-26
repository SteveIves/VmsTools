$!===========================================================================
$!
$! Title:       OPENFILES.COM
$!
$! Description: Lists the data files (ISAM and RELATIVE) opened by a process
$!
$! Usage:       $ @OPENFILES <process-id>
$!
$!===========================================================================
$!
$!      Make sure we have a P1 parameter value
$       if "''P1'".eqs.""
$       then
$               write sys$output "%OPENFILES-E-NOPID, Specify a PID via P1"
$               exit 1
$       endif
$!
$!      And make sure it is a valid process ID
$       set message/nofac/nosev/noid/notext
$       processName = f$getjpi("''p1'","PRCNAM")
$       set message/fac/sev/id/text
$!
$       if "''processName'".eqs.""
$       then
$               write sys$output "%OPENFILES-E-NOPRC, Process not found"
$               exit 1
$       endif
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
$       targetPid = f$getjpi("''p1'","PID")
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
$!              Only process records for the PID we're looking for?
$               thisPid = f$extract(16,8,data)
$               if "''thisPid'".nes."''targetPid'" then goto nextFile
$!
$!              Add the current device name to make a full file spec
$               candidateFileSpec = "''nextDisk'" + f$extract(26,f$length(data),data)
$!
$!              Ignore all files except ISAM and RELATIVE file?
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
$               write sys$output "Open data files for process ''targetPid' (''processName')"
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
$               write sys$output "Process ''targetPid' (''processName') has no open data files"
$       endif
$       write sys$output ""
$!
$       exit
$!
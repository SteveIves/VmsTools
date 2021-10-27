$!===========================================================================
$!
$! Title:       SET_PROCESS_NAME.COM
$!
$! Description: Sets the name of the process to a base name and incremented #
$!
$! Usage:       $ @SET_PROCESS_NAME <base_name>
$!
$! Author:      Steve Ives (steve.ives@synergex.com)
$!
$!===========================================================================
$!
$       BASENAME="''P1'"
$       IF "''BASENAME'" .EQS. ""
$       THEN
$           WRITE SYS$OUTPUT "%PRCNAM-E-NONAME, Specify base name via P1"
$           EXIT 1
$       ENDIF
$       COUNT=0
$       SET MESSAGE/NOFACILITY/NOSEVERITY/NOID/NOTEXT
$RETRY: ON ERROR THEN GOTO RETRY
$       COUNT=COUNT+1
$       SET PROCESS/NAME="''BASENAME'''COUNT'"
$       ON SEVERE_ERROR THEN EXIT
$       SET MESSAGE/FACILITY/SEVERITY/ID/TEXT
$       EXIT
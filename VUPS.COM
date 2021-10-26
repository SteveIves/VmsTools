$! VUPS.COM
$! Provides an estimate of system CPU performance on OpenVMS systems.
$! Use at your own risk.
$! Modified: MAY-2010: Code updated by Volker Halle to address the
$! following issues:
$! - init_vups can become negative, if the first loop is executed
$!   within less than 1 clock tick time (10 ms),
$!   i.e. end_cputime .eq. start_cputime. This has been prevented.
$! - the same problem could happen when calculating new_vups
$! - the procedure will automatically terminate after
$!   times_through_loop = 5, evts vse the loop to terminate earlier.
$!   I had to move the calculation of times_through_loop up inside the code.
$! - the procedure will print average CPU as well as minimum and
$!   maximum values.
$!
$ set noon
$ cpu_multiplier = 10 ! VAX = 10 - Alpha/AXP = 40
$ cpu_round_add = 1 ! VAX = 1 - Alpha/AXP = 9
$ cpu_round_divide = cpu_round_add + 1
$ init_counter = cpu_multiplier * 525
$ speed_factor = 1                      ! to increase no. of loops on fast CPUs
$ 9$:
$ init_loop_maximum = 205 * speed_factor
$ start_cputime = f$getjpi(0,"CPUTIM")
$ loop_index = 0
$ 10$:
$ loop_index = loop_index + 1
$ if loop_index .ne. init_loop_maximum then goto 10$
$ end_cputime = f$getjpi(0,"CPUTIM")
$ IF end_cputime .LE. start_cputime + 1 ! not enough clock-ticks = CPU too fast
$ THEN
$   speed_factor = speed_factor + 1     ! increase no. of loops
$   WRITE SYS$OUTPUT "INFO: Preventing endless loop (10$) on fast CPUs"
$   GOTO 9$
$ ENDIF
$ init_vups = ((init_counter / (end_cputime - start_cputime) + -
                cpu_round_add) / cpu_round_divide) * cpu_round_divide
$ IF init_vups .LE. 0
$ THEN
$   WRITE SYS$OUTPUT "Calibration error -> exiting (Please report this problem)"
$   SHOW SYMB speed_factor
$   SHOW SYMB init_vups
$   SHOW SYMB init_counter
$   SHOW SYMB end_cputime
$   SHOW SYMB start_cputime
$   SHOW SYMB cpu_multiplier
$   SHOW SYMB cpu_rounding
$   SHOW CPU
$   EXIT
$ ENDIF
$ write sys$output " "
$ loop_maximum = (init_vups * init_loop_maximum) / ( 10 * speed_factor )
$ base_counter = (init_counter * init_vups) / 10
$ vups = 0
$ min_vups = %X7FFFFFFF
$ max_vups = 0
$ avg_vups = 0
$ times_through_loop = 0
$ 20$:
$ start_cputime = f$getjpi(0,"CPUTIM")
$ times_through_loop = times_through_loop + 1
$ loop_index = 0
$ 30$:
$ loop_index = loop_index + 1
$ if loop_index .ne. loop_maximum then goto 30$
$ end_cputime = f$getjpi(0,"CPUTIM")
$ IF end_cputime .LE. start_cputime
$ THEN
$   new_vups = 0        ! can not calculate VUPS (CPU too fast)
$   WRITE SYS$OUTPUT "INFO: Loop too fast (20$) - ignoring VUPS data"
$ ELSE
$   new_vups = ((base_counter / (end_cputime - start_cputime) + -
                cpu_round_add) / cpu_round_divide) * cpu_round_divide
$ ENDIF
$ IF new_vups .LT. min_vups THEN $ min_vups = new_vups
$ IF new_vups .GT. max_vups THEN $ max_vups = new_vups
$ avg_vups = avg_vups + new_vups
$ if new_vups .eq. vups then goto 40$
$ vups = new_vups
$ if times_through_loop .le. 5 then goto 20$
$!! WRITE SYS$OUTPUT "INFO: Preventing endless loop 20$"
$ 40$:
$ vups = avg_vups / times_through_loop
$ write sys$output "   Approximate System VUPs Rating :  ", -
                   vups / 10,".", vups - ((vups / 10) * 10), -
                   "  ( min: ", min_vups/10, "  max: ", max_vups/10, " )"
$ exit
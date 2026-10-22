#!/bin/bash
# Records the 7 RPM stages (on and off load) of each engine used by IronMetal, all engines in parallel.
R=/home/claude/ange-yaghi/engine-sim
rec() {  # id script rpms
  mkdir -p $R/bin_$1 /home/claude/esim/out/$1
  cd $R/bin_$1 && ES_GAIN=0.0015 /home/claude/esim/recorder ../assets/engines/$2.mr /home/claude/esim/out/$1 $3 3 > /home/claude/esim/out/$1.log 2>&1
}
rec lfa atg-video-2/10_lfa_v10 1400,2600,3800,5000,6300,7600,8800 &
rec f136 atg-video-2/08_ferrari_f136_v8 1400,2600,3800,5000,6300,7600,8800 &
rec c454 chevrolet/chev_truck_454 1000,1700,2400,3100,3800,4500,5300 &
rec merlin atg-video-2/11_merlin_v12 700,1000,1350,1700,2100,2500,2900 &
rec ls atg-video-2/07_gm_ls 1000,1800,2600,3500,4400,5300,6300 &
wait

#!/bin/bash
# Second pass: the engines that needed a longer start, and the 454 truck through its own main script.
R=/home/claude/ange-yaghi/engine-sim
rec() {
  rm -rf /home/claude/esim/out/$1; mkdir -p $R/bin_$1 /home/claude/esim/out/$1
  cd $R/bin_$1 && ES_GAIN=0.0015 /home/claude/esim/recorder2 ../assets/engines/$2.mr /home/claude/esim/out/$1 $3 3 > /home/claude/esim/out/$1.log 2>&1
}
rec f136 atg-video-2/08_ferrari_f136_v8 1400,2600,3800,5000,6300,7600,8800 &
rec c454 chevrolet/c454_main 1000,1700,2400,3100,3800,4500,5300 &
rec merlin atg-video-2/11_merlin_v12 700,1000,1350,1700,2100,2500,2900 &
wait

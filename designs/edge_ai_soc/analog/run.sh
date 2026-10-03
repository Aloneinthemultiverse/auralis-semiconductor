#!/bin/sh
# usage: run.sh corner dvin_mV freq_GHz  -> prints decision and delay
c=$1; dv=$2; f=$3
per=$(python3 -c "print(1/$f)")
half=$(python3 -c "print(0.5/$f)")
cat > /tmp/tb.sp <<SP
* testbench
.lib /pdk/sky130A/libs.tech/ngspice/sky130.lib.spice $c
.include /w/strongarm.sp
.option scale=1e-6
.param dv=${dv}m
vdd vdd 0 1.8
vss vss 0 0
vclk clk 0 pulse(0 1.8 ${half}n 20p 20p ${half}n ${per}n)
vip inp 0 dc {0.9+dv/2}
vin inn 0 dc {0.9-dv/2}
xc clk inp inn outp outn vdd vss strongarm
cl1 outp 0 10f
cl2 outn 0 10f
.tran 1p $(python3 -c "print(4/$f)")n
.control
run
meas tran tclk when v(clk)=0.9 rise=3
meas tran tdp trig v(clk) val=0.9 rise=3 targ v(outp) val=0.9 rise=1 td=$(python3 -c "print(2.5/$f)")n
meas tran tdn trig v(clk) val=0.9 rise=3 targ v(outn) val=0.9 rise=1 td=$(python3 -c "print(2.5/$f)")n
meas tran ivdd avg i(vdd) from=$(python3 -c "print(2/$f)")n to=$(python3 -c "print(4/$f)")n
let vfin = v(outp) - v(outn)
meas tran vdiff find vfin at=$(python3 -c "print(2.5/$f + 0.4/$f)")n
.endc
.end
SP
ngspice -b /tmp/tb.sp 2>/dev/null | grep -E "^(tdp|tdn|ivdd|vdiff)" | tr '\n' ' '
echo

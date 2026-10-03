* StrongARM latch comparator - receiver sampler for the LPDDR4 DQ / SerDes front end (SKY130, 1.8 V core)
.subckt strongarm clk inp inn outp outn vdd vss
* clocked tail and input pair
XM0  tail clk vss vss sky130_fd_pr__nfet_01v8 w=4 l=0.15
XM1  x1 inp tail vss sky130_fd_pr__nfet_01v8 w=4 l=0.15 m=2
XM2  x2 inn tail vss sky130_fd_pr__nfet_01v8 w=4 l=0.15 m=2
* cross-coupled latch
XM3  on op x1 vss sky130_fd_pr__nfet_01v8 w=2 l=0.15
XM4  op on x2 vss sky130_fd_pr__nfet_01v8 w=2 l=0.15
XM5  on op vdd vdd sky130_fd_pr__pfet_01v8 w=2 l=0.15
XM6  op on vdd vdd sky130_fd_pr__pfet_01v8 w=2 l=0.15
* reset (precharge) switches
XM7  on clk vdd vdd sky130_fd_pr__pfet_01v8 w=1 l=0.15
XM8  op clk vdd vdd sky130_fd_pr__pfet_01v8 w=1 l=0.15
XM9  x1 clk vdd vdd sky130_fd_pr__pfet_01v8 w=1 l=0.15
XM10 x2 clk vdd vdd sky130_fd_pr__pfet_01v8 w=1 l=0.15
* output buffers (outp high when inp > inn)
XI1p outp on vdd vdd sky130_fd_pr__pfet_01v8 w=2 l=0.15
XI1n outp on vss vss sky130_fd_pr__nfet_01v8 w=1 l=0.15
XI2p outn op vdd vdd sky130_fd_pr__pfet_01v8 w=2 l=0.15
XI2n outn op vss vss sky130_fd_pr__nfet_01v8 w=1 l=0.15
.ends

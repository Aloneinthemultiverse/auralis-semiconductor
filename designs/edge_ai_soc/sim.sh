#!/bin/sh
# usage: ./sim.sh tb_top file...
top=$1; shift
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/w" -w /w auralis-eda sh -c "iverilog -g2012 -s $top -o /tmp/s $* 2>&1 | grep -v sorry; timeout 120 vvp -n /tmp/s | tail -8"

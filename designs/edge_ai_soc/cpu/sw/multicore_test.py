"""Bring-up test for the 4 x CVA6 cluster. Each hart h:
   mem[0x1000_1000 + 8h] = h + 0x11            (64-bit store, uncached SRAM)
   amoadd.d 1 -> 0x1000_2000                    (shared counter: atomics across 4 cores)
   sb (0xA0 + h) -> 0x1000_2100 + h             (4 harts byte-store into ONE word: RMW lock)
   amoadd.d 1 -> 0x1000_2008                    (done counter), then spin."""
import sys
from rvasm import *
prog = [
    csrr("t0", 0xF14),
    lui("t1", 0x10001), slli("t2", "t0", 3), add("t1", "t1", "t2"),
    addi("t3", "t0", 0x11), sd("t3", 0, "t1"),
    lui("t4", 0x10002), addi("t5", "zero", 1), amoadd_d("zero", "t5", "t4"),
    add("t6", "t4", "t0"), addi("t6", "t6", 0x100), addi("a0", "t0", 0xA0), sb("a0", 0, "t6"),
    fence(),
    addi("a1", "t4", 8), amoadd_d("zero", "t5", "a1"),
    jal("zero", 0),
]
with open(sys.argv[1], "w") as f:
    for k in range(0, len(prog) + (len(prog) & 1), 2):
        lo = prog[k]; hi = prog[k + 1] if k + 1 < len(prog) else 0x00000013
        f.write(f"{(hi << 32) | lo:016x}\n")
print(len(prog), "instructions")

"""Stage-1 boot image for the full SoC (executed by the 4 CVA6 harts from flash after secure boot).
hart 0: SRAM store; LPDDR4 store + load-back; programs the IOPMP and the DMA to copy LPDDR4 -> SRAM;
        polls DMA done; writes a done marker. harts 1-3: amoadd.d on a shared SRAM counter.
Writes flash.hex (header {version, nwords} + code) and the SHA-256 digest for the OTP fuses."""
import hashlib, sys
from rvasm import *
L = lambda lab, f: (lambda labels, pc: f(labels[lab] - pc))
code = assemble([
    csrr("t0", 0xF14),
    L("other", lambda o: bne("t0", "zero", o)),
    lui("t1", 0x10000),                                   # t1 = SRAM base 0x1000_0000
    addi("t2", "zero", 0x123), sd("t2", 0x100, "t1"),     # SRAM[0x100] = 0x123
    addi("t3", "zero", 1), slli("t3", "t3", 31),          # t3 = 0x8000_0000 (LPDDR4)
    lui("t4", 0xB), addi("t4", "t4", -0x433),             # 0xABCD
    sd("t4", 0x40, "t3"), ld("t5", 0x40, "t3"),           # LPDDR4 store + load
    sd("t5", 0x108, "t1"),                                # SRAM[0x108] = load-back
    lui("s1", 0x30002),                                   # IOPMP registers
    sw("t3", 0, "s1"), lui("a2", 0x10), add("a2", "t3", "a2"), sw("a2", 4, "s1"),
    addi("a3", "zero", 3), sw("a3", 8, "s1"),             # region 0: LPDDR4 64 KB read-only
    sw("t1", 16, "s1"), lui("a4", 0x2), add("a4", "t1", "a4"), sw("a4", 20, "s1"),
    addi("a3", "zero", 7), sw("a3", 24, "s1"),            # region 1: SRAM 8 KB read/write
    lui("s0", 0x30001),                                   # DMA registers
    addi("a5", "t3", 0x40), sw("a5", 4, "s0"),            # SRC = LPDDR4 + 0x40
    addi("a6", "t1", 0x200), sw("a6", 8, "s0"),           # DST = SRAM + 0x200
    addi("a7", "zero", 1), sw("a7", 12, "s0"), sw("a7", 16, "s0"),
    addi("a3", "zero", 8), sw("a3", 20, "s0"), sw("a3", 24, "s0"),
    addi("a3", "zero", 1), sw("a3", 0, "s0"),             # start
    "poll", lw("a3", 0, "s0"), andi("a3", "a3", 2),
    L("poll", lambda o: beq("a3", "zero", o)),
    lui("a4", 0x6), addi("a4", "a4", 0xD), sd("a4", 0x110, "t1"),   # done marker 0x600D
    "spin0", L("spin0", lambda o: jal("zero", o)),
    "other",
    lui("t1", 0x10000), addi("t2", "zero", 1), addi("t3", "t1", 0x120),
    amoadd_d("zero", "t2", "t3"),
    "spin1", L("spin1", lambda o: jal("zero", o)),
])
if len(code) % 2: code.append(0x00000013)
words = [(code[k + 1] << 32) | code[k] for k in range(0, len(code), 2)]
img = [(5 << 32) | len(words)] + words
dig = hashlib.sha256(b"".join(w.to_bytes(8, "big") for w in img)).hexdigest()
open(sys.argv[1], "w").write("".join(f"{w:016x}\n" for w in img))
open(sys.argv[2], "w").write(dig + "\n")
print(len(code), "instructions,", len(img), "flash words, digest", dig)

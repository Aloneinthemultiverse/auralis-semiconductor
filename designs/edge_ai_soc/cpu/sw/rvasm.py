"""Minimal RV64 assembler for bare-metal bring-up tests (no toolchain needed)."""
R = {f"x{i}": i for i in range(32)}
R.update(zero=0, ra=1, sp=2, gp=3, tp=4, t0=5, t1=6, t2=7, s0=8, s1=9, a0=10, a1=11, a2=12, a3=13,
         a4=14, a5=15, a6=16, a7=17, t3=28, t4=29, t5=30, t6=31)
def r(op, rd, f3, rs1, rs2, f7): return (f7 << 25) | (R[rs2] << 20) | (R[rs1] << 15) | (f3 << 12) | (R[rd] << 7) | op
def i(op, rd, f3, rs1, imm): return ((imm & 0xFFF) << 20) | (R[rs1] << 15) | (f3 << 12) | (R[rd] << 7) | op
def s(op, f3, rs1, rs2, imm): return (((imm >> 5) & 0x7F) << 25) | (R[rs2] << 20) | (R[rs1] << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op
def lui(rd, imm20): return ((imm20 & 0xFFFFF) << 12) | (R[rd] << 7) | 0x37
def addi(rd, rs1, imm): return i(0x13, rd, 0, rs1, imm)
def slli(rd, rs1, sh): return i(0x13, rd, 1, rs1, sh & 0x3F)
def add(rd, a, b): return r(0x33, rd, 0, a, b, 0)
def sd(rs2, imm, rs1): return s(0x23, 3, rs1, rs2, imm)
def sb(rs2, imm, rs1): return s(0x23, 0, rs1, rs2, imm)
def ld(rd, imm, rs1): return i(0x03, rd, 3, rs1, imm)
def csrr(rd, csr): return i(0x73, rd, 2, "x0", csr)
def amoadd_d(rd, rs2, rs1): return r(0x2F, rd, 3, rs1, rs2, 0)          # funct5=0, aq=rl=0
def fence(): return 0x0FF0000F
def jal(rd, off): return ((off >> 20 & 1) << 31) | ((off >> 1 & 0x3FF) << 21) | ((off >> 11 & 1) << 20) | ((off >> 12 & 0xFF) << 12) | (R[rd] << 7) | 0x6F

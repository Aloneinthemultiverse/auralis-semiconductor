"""Generate Verilog simulation models from a Liberty file (combinational functions, ff, latch).
usage: python lib2v.py cells.lib out.v"""
import re, sys

src = open(sys.argv[1]).read()
out = ["// generated from Liberty by lib2v.py (simulation models for gate-level power analysis)",
       "`timescale 1ns/1ps"]

def expr(f):
    f = f.strip().strip('"')
    f = f.replace("!", "~").replace("+", "|").replace("*", "&")
    f = re.sub(r"\b1'b?0\b|\b0\b", "1'b0", f)
    return f

def block(text, start):
    """return the {...} body starting at index of '{' >= start"""
    i = text.index("{", start); depth = 0
    for j in range(i, len(text)):
        if text[j] == "{": depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0: return text[i + 1:j], j
    raise ValueError

pos = 0
cells = 0
seen = set()
for m in re.finditer(r"\bcell\s*\(\s*\"?([\w]+)\"?\s*\)", src):
    name = m.group(1)
    if m.start() < pos or name in seen:
        continue
    body, endp = block(src, m.end())
    pos = endp
    seen.add(name)
    pins = []
    for pm in re.finditer(r"\bpin\s*\(\s*\"?([\w]+)\"?\s*\)", body):
        pb, _ = block(body, pm.end())
        d = re.search(r"direction\s*:\s*\"?(\w+)", pb)
        fn = re.search(r"\bfunction\s*:\s*\"([^\"]*)\"", pb)
        pins.append((pm.group(1), d.group(1) if d else "input", fn.group(1) if fn else None))
    ins = [p for p, d, _ in pins if d == "input"]
    outs = [(p, f) for p, d, f in pins if d == "output"]
    lines = [f"module {name} (" + ", ".join([p for p, _, _ in pins]) + ");"]
    for p, d, _ in pins:
        lines.append(f"  {'input' if d == 'input' else 'output'} {p};")
    ffm = re.search(r"\bff\s*\(\s*\"?(\w+)\"?\s*,\s*\"?(\w+)\"?\s*\)", body)
    lam = re.search(r"\blatch\s*\(\s*\"?(\w+)\"?\s*,\s*\"?(\w+)\"?\s*\)", body)
    if ffm:
        fb, _ = block(body, ffm.end())
        q, qn = ffm.group(1), ffm.group(2)
        ns = expr(re.search(r"next_state\s*:\s*\"([^\"]*)\"", fb).group(1))
        ck = expr(re.search(r"clocked_on\s*:\s*\"([^\"]*)\"", fb).group(1))
        clr = re.search(r"\bclear\s*:\s*\"([^\"]*)\"", fb)
        pre = re.search(r"\bpreset\s*:\s*\"([^\"]*)\"", fb)
        lines += [f"  reg {q} = 1'b0;", f"  wire {qn} = ~{q};", f"  wire ck_ = {ck};"]
        if clr or pre:
            c = expr(clr.group(1)) if clr else "1'b0"
            p = expr(pre.group(1)) if pre else "1'b0"
            lines += [f"  always @(posedge ck_ or posedge ({c}) or posedge ({p}))",
                      f"    if ({c}) {q} <= 1'b0; else if ({p}) {q} <= 1'b1; else {q} <= {ns};"]
        else:
            lines += [f"  always @(posedge ck_) {q} <= {ns};"]
    elif lam:
        lb, _ = block(body, lam.end())
        q, qn = lam.group(1), lam.group(2)
        dd = expr(re.search(r"data_in\s*:\s*\"([^\"]*)\"", lb).group(1))
        en = expr(re.search(r"\benable\s*:\s*\"([^\"]*)\"", lb).group(1))
        lines += [f"  reg {q} = 1'b0;", f"  wire {qn} = ~{q};", f"  always @* if ({en}) {q} = {dd};"]
    for p, f in outs:
        if f is not None:
            lines.append(f"  assign {p} = {expr(f)};")
    lines.append("endmodule")
    out += lines
    cells += 1
open(sys.argv[2], "w").write("\n".join(out) + "\n")
print(cells, "cells")

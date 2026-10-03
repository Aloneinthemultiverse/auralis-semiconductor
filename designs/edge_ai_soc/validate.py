"""Validate a block through the auralis-semiconductor MCP server (Verilator lint, Icarus sim, Yosys synth).
usage: python validate.py file1.sv file2.sv ... tb_x.sv"""
import json, os, sys, urllib.request
URL = "http://localhost:8090/mcp"
H = {"content-type": "application/json", "accept": "application/json,text/event-stream"}
def mcp(p, sid=None):
    h = dict(H)
    if sid: h["mcp-session-id"] = sid
    with urllib.request.urlopen(urllib.request.Request(URL, json.dumps(p).encode(), h, method="POST"), timeout=600) as r:
        return r.headers.get("mcp-session-id"), r.read().decode()
sid, _ = mcp({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "v", "version": "1"}}})
mcp({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
files = {os.path.basename(f): open(f, encoding="utf-8").read() for f in sys.argv[1:]}
_, raw = mcp({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "semiconductor_validate", "arguments": {"filesJson": json.dumps(files)}}}, sid)
text = json.loads(raw[raw.index("{"):])["result"]["content"][0]["text"]
out = sys.argv[1].rsplit("/", 1)[0] if "/" in sys.argv[1] else "."
name = [f for f in sys.argv[1:] if os.path.basename(f).startswith("tb_")]
rep = os.path.join("reports", (os.path.basename(name[0])[3:-3] if name else "block") + ".txt")
os.makedirs("reports", exist_ok=True); open(rep, "w").write(text)
for l in text.splitlines():
    if any(k in l for k in ("%Error", "%Warning", "FAIL", "error", "SUMMARY", "ALL TESTS", "Number of cells", "PASSED")): print(l[:300])

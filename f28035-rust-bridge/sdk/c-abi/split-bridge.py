"""Split f28035_bridge.c into per-peripheral files."""
import re
from pathlib import Path

SRC = Path(r"C:\Users\61987\Desktop\28035\f28035-rust-bridge\sdk\c-abi\f28035_bridge.c")
OUT_DIR = SRC.parent

text = SRC.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

# Find all function starts
func_starts = []
for i, line in enumerate(lines):
    if re.match(r'^void f28035_\w+\(', line):
        func_starts.append(i)

# Categorize by prefix
def categorize(name: str) -> str:
    n = name.replace("f28035_", "")
    if n.startswith("gpio"):
        return "gpio"
    if n.startswith("epwm"):
        return "epwm"
    if n.startswith("adc"):
        return "adc"
    if n.startswith("spi"):
        return "spi"
    if n.startswith("i2c"):
        return "i2c"
    if n.startswith("sci"):
        return "sci"
    if n.startswith("lin"):
        return "lin"
    if n.startswith("ecap"):
        return "ecap"
    if n.startswith("eqep"):
        return "eqep"
    if n.startswith("can"):
        return "can"
    if n.startswith("hrcap"):
        return "hrcap"
    if n.startswith("pie"):
        return "pie"
    if n.startswith("watchdog") or n.startswith("sys_wdg") or n.startswith("wdg_"):
        return "watchdog"
    if n.startswith("sys_"):
        return "sys"
    if n.startswith("timer"):
        return "timer"
    return "common"

# Extract each function block
groups = {}
prelude_end = func_starts[0] if func_starts else len(lines)
prelude = "".join(lines[:prelude_end])

for idx, start in enumerate(func_starts):
    end = func_starts[idx + 1] if idx + 1 < len(func_starts) else len(lines)
    block = "".join(lines[start:end])
    m = re.match(r'void (f28035_\w+)\(', lines[start])
    if m:
        mod = categorize(m.group(1))
        groups.setdefault(mod, []).append(block)

# Write files
for mod, blocks in groups.items():
    body = prelude + "\n" + "".join(blocks)
    (OUT_DIR / f"bridge_{mod}.c").write_text(body, encoding="utf-8")
    print(f"bridge_{mod}.c: {len(blocks)} functions")

print("done")

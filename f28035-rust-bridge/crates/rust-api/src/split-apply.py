"""Split application.rs into per-peripheral submodules.

Strategy:
- Read application.rs
- Common prelude (lines 1..first `#[unsafe(no_mangle)]`) goes to mod.rs
- Each `#[unsafe(no_mangle)] pub extern "C" fn foo(...) { ... }` block goes to a
  per-peripheral module based on the function name prefix.
"""
import re
from pathlib import Path

SRC = Path(r"C:\Users\61987\Desktop\28035\f28035-rust-bridge\crates\rust-api\src")
APP = SRC / "application.rs"
OUT_DIR = SRC / "application"

text = APP.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

# Find the first #[unsafe(no_mangle)] line
first_attr = None
for i, line in enumerate(lines):
    if "#[unsafe(no_mangle)]" in line:
        first_attr = i
        break

prelude = "".join(lines[:first_attr])
rest = lines[first_attr:]

# Now split rest into function blocks.
# A block starts at a line containing "#[unsafe(no_mangle)]" and ends just
# before the next "#[unsafe(no_mangle)]" line.
blocks = []
start = None
for i, line in enumerate(rest):
    if "#[unsafe(no_mangle)]" in line:
        if start is not None:
            blocks.append((start, i))
        start = i
if start is not None:
    blocks.append((start, len(rest)))

# Categorize each block by function name
def categorize(fn_name: str) -> str:
    n = fn_name
    if n.startswith("rust_gpio"):
        return "gpio"
    if n.startswith("rust_epwm"):
        return "epwm"
    if n.startswith("rust_adc"):
        return "adc"
    if n.startswith("rust_spi"):
        return "spi"
    if n.startswith("rust_i2c"):
        return "i2c"
    if n.startswith("rust_sci"):
        return "sci"
    if n.startswith("rust_lin"):
        return "lin"
    if n.startswith("rust_ecap"):
        return "ecap"
    if n.startswith("rust_eqep"):
        return "eqep"
    if n.startswith("rust_can"):
        return "can"
    if n.startswith("rust_hrcap"):
        return "hrcap"
    if n.startswith("rust_pie"):
        return "pie"
    if n.startswith("rust_watchdog") or n.startswith("rust_sys_wdg") or n.startswith("rust_wdg_"):
        return "watchdog"
    if n.startswith("rust_sys_") or n.startswith("rust_sys"):
        return "sys"
    if n.startswith("rust_timer"):
        return "timer"
    if n in ("rust_main", "rust_et_jtag_setup"):
        return "integration"
    return "integration"

MOD_TO_FUNCS = {}
MOD_BLOCKS = {}
for (s, e) in blocks:
    block_text = "".join(rest[s:e])
    m = re.search(r'pub\s+extern\s+"C"\s+fn\s+(\w+)', block_text)
    if not m:
        continue
    fn_name = m.group(1)
    mod = categorize(fn_name)
    MOD_BLOCKS.setdefault(mod, []).append(block_text)
    MOD_TO_FUNCS.setdefault(mod, []).append(fn_name)

# Create output dir
OUT_DIR.mkdir(exist_ok=True)

# Write mod.rs: prelude + `pub mod xxx;` + `pub use xxx::*;`
mod_lines = [prelude, "\n"]
for mod in sorted(MOD_BLOCKS.keys()):
    mod_lines.append(f"pub mod {mod};\n")
for mod in sorted(MOD_BLOCKS.keys()):
    mod_lines.append(f"pub use {mod}::*;\n")
(OUT_DIR / "mod.rs").write_text("".join(mod_lines), encoding="utf-8")

# Write each per-peripheral file
for mod, blocks_text in MOD_BLOCKS.items():
    body = (
        "//! Auto-generated peripheral module. Do not hand-edit; see split-apply.py.\n"
        "use crate::system_init;\n\n"
    )
    for b in blocks_text:
        body += b
        if not b.endswith("\n"):
            body += "\n"
    (OUT_DIR / f"{mod}.rs").write_text(body, encoding="utf-8")
    print(f"{mod}.rs: {len(blocks_text)} functions")

print("done")

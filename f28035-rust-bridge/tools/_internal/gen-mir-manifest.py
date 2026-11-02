#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从现有的 build-mir-*.ps1 / verify-mir-*.ps1 解析出每 case 的清单，
生成 tools/mir-cases.json，供通用 build-mir.ps1 / verify-mir.ps1 / self-check.ps1 使用。

设计原则：
- 只「读」现有脚本，不修改任何旧脚本。
- 每 case 的字段都按字面从脚本里提取，保证通用脚本与旧脚本行为一致。
- 任何解析异常或不标准的脚本都标 custom=true，通用脚本会回退到旧脚本，
  绝不静默改变行为。

STANDARD 判定（build）：
  Invoke-Native $Compiler 出现次数必须为 7（rust 汇编1 + harness/sysctrl/gpio/delay/codestart 5 个编译 + 1 个链接）。
  否则视为 custom（可能多了/少了编译或链接步骤）。
STANDARD 判定（verify）：
  必须包含 "RAM relink" 且能提取到 verify JS 与 passMarker；否则 custom。
"""
import os
import re
import json
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)  # script lives in tools/_internal, scripts are in tools/
ROOT = os.path.dirname(TOOLS)

BUILD_PREFIX = "build-mir-"
VERIFY_PREFIX = "verify-mir-"

# ---------- 提取辅助 ----------
def read(path):
    with open(path, encoding="utf-8-sig", errors="replace") as f:
        return f.read()

def grab(text, pat, group=1, default=None):
    m = re.search(pat, text)
    return m.group(group) if m else default

def count(text, pat):
    return len(re.findall(pat, text))

cases = {}
anomalies = []

build_files = sorted(glob.glob(os.path.join(TOOLS, BUILD_PREFIX + "*.ps1")))
verify_files = sorted(glob.glob(os.path.join(TOOLS, VERIFY_PREFIX + "*.ps1")))

verify_by_key = {}
for vf in verify_files:
    key = os.path.basename(vf)[len(VERIFY_PREFIX):-4]
    verify_by_key[key] = vf

for bf in build_files:
    fname = os.path.basename(bf)
    key = fname[len(BUILD_PREFIX):-4]
    t = read(bf)

    b = {
        "outputDir": grab(t, r"\$outputDirectory = Join-Path \$projectRoot '([^']+)'"),
        "mirFile": grab(t, r"\$mirOutput = Join-Path \$mirDirectory '([^']+\.mir\.txt)'"),
        "asmFile": grab(t, r"\$assembly = Join-Path \$mirDirectory '([^']+\.asm)'"),
        "rustObj": grab(t, r"\$rustObject = Join-Path \$outputDirectory '([^']+)'"),
        "harnessObj": grab(t, r"\$harnessObject = Join-Path \$outputDirectory '([^']+)'"),
        "firmwareOut": grab(t, r"\$firmwareOut = Join-Path \$outputDirectory '([^']+)'"),
        "harnessSrc": grab(t, r"\$harnessSource = Join-Path \$projectRoot '([^']+)'"),
        "onlyExport": grab(t, r"-OnlyExport',\s*'([^']+)'"),
    }
    b_compiles = count(t, r"Invoke-Native \$Compiler")
    b_custom = b_compiles != 7

    vf = verify_by_key.get(key)
    v = {}
    v_custom = True
    v_js_missing_disk = False
    if vf:
        vt = read(vf)
        # js：优先从真正的 & $Dss 调用行提取，避免抓到注释里的其它引用
        dss_line = next((ln for ln in vt.splitlines() if "& $Dss" in ln), None)
        js = None
        if dss_line:
            m = re.search(r"Join-Path[^\n]*'([^']+\.js)'", dss_line)
            if not m:
                m = re.search(r"'(verify-[^']+\.js)'", dss_line)
            if m:
                js = m.group(1)
            else:
                mv = re.search(r"& \$Dss\s+\$(\w+)", dss_line)
                if mv:
                    var = mv.group(1)
                    mv2 = re.search(r"\$" + re.escape(var) + r"\s*=\s*Join-Path[^\n]*'([^']+\.js)'", vt)
                    if not mv2:
                        mv2 = re.search(r"\$" + re.escape(var) + r"\s*=\s*'([^']+\.js)'", vt)
                    if mv2:
                        js = mv2.group(1)
        if not js:
            js = grab(vt, r"[\"'](verify-[^\"']+\.js)[\"']")
        # passMarker：从真正的 -notmatch 行提取
        pm_line = next((ln for ln in vt.splitlines() if "-notmatch" in ln and "PASS" in ln), None)
        passMarker = None
        if pm_line:
            m = re.search(r"[\"']([A-Za-z0-9_=]+PASS)[\"']", pm_line)
            if m:
                passMarker = m.group(1)
        if not passMarker:
            passMarker = grab(vt, r"-notmatch [\"']([A-Za-z0-9_=]+PASS)[\"']")
        ramOut = grab(vt, r"[\"']([^\"']+_ram\.out)[\"']")
        ramMap = grab(vt, r"[\"']([^\"']+_ram\.map)[\"']")
        v = {"js": js, "passMarker": passMarker, "ramOut": ramOut, "ramMap": ramMap}
        # js 文件必须真实存在于 tools/ 下，否则视为提取可疑 -> 回退 legacy
        if js and not os.path.exists(os.path.join(TOOLS, js)):
            v_js_missing_disk = True
        has_ram_relink = "RAM relink" in vt
        v_is_js = bool(js) and js.lower().endswith(".js")
        if has_ram_relink and v_is_js and not v_js_missing_disk and passMarker and ramOut and ramMap:
            v_custom = False

    # 关键字段缺失也标 custom
    b_missing = [k for k, val in b.items() if val is None and k != "onlyExport"]
    if b["harnessSrc"] and not os.path.exists(os.path.join(ROOT, b["harnessSrc"])):
        b_missing.append("harnessSrc(missing-on-disk)")
    if b_missing:
        b_custom = True
    v_missing = [k for k, val in v.items() if val is None]
    if v_missing:
        v_custom = True

    custom = b_custom or v_custom
    entry = {
        "key": key,
        "build": b,
        "verify": v,
        "custom": custom,
        "legacyBuild": fname,
        "legacyVerify": os.path.basename(vf) if vf else None,
        "buildCompilerCalls": b_compiles,
        "buildMissing": b_missing,
        "verifyMissing": v_missing,
    }
    cases[key] = entry

    if custom:
        reasons = []
        if b_custom:
            reasons.append("build: Invoke-Native $Compiler=%d (expect 7)%s" % (
                b_compiles, (" missing=" + ",".join(b_missing)) if b_missing else ""))
        if v_custom:
            reasons.append("verify missing=" + ",".join(v_missing) if v_missing else "verify: non-standard")
        anomalies.append((key, "; ".join(reasons)))

# ---------- 写出 JSON ----------
out = {
    "meta": {
        "generatedBy": "tools/_internal/gen-mir-manifest.py",
        "toolsDir": TOOLS,
        "buildScriptCount": len(build_files),
        "verifyScriptCount": len(verify_files),
        "caseCount": len(cases),
        "customCount": sum(1 for c in cases.values() if c["custom"]),
        "onlyExportCount": sum(1 for c in cases.values() if c["build"]["onlyExport"]),
    },
    "cases": cases,
}

out_path = os.path.join(TOOLS, "mir-cases.json")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)

# ---------- 控制台报告 ----------
print("=== mir-cases.json 生成报告 ===")
print("build 脚本数 :", len(build_files))
print("verify 脚本数:", len(verify_files))
print("case 数      :", len(cases))
build_custom = sum(1 for c in cases.values() if c.get("buildMissing") or c["buildCompilerCalls"] != 7)
verify_custom = sum(1 for c in cases.values() if c.get("verifyMissing"))
print("build standard :", len(cases) - build_custom, " custom:", build_custom)
print("verify standard:", len(cases) - verify_custom, " custom:", verify_custom)
print("overall standard:", sum(1 for c in cases.values() if not c["custom"]))
print("onlyExport   :", sum(1 for c in cases.values() if c["build"]["onlyExport"]))
print()
if anomalies:
    print("--- custom 用例 (%d) ---" % len(anomalies))
    for k, r in sorted(anomalies):
        print("  %-28s %s" % (k, r))
else:
    print("全部为 standard，无 custom 用例。")
print()
print("已写出:", out_path)

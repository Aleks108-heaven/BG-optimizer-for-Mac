#!/usr/bin/env python3
"""Checks the translations.

  - every tr("...") / trkey("...") key used in Sources/ exists in the Ukrainian file
  - every trPlural("base", ...) has .one/.few/.many (uk) and .one/.other (en)
  - placeholders (%d, %@, %.1f, %%) match between the English key and the Ukrainian text
  - no unused (stale) Ukrainian keys, and the .strings files parse

Run:  python3 tools/check_strings.py        (exit code 1 if anything is wrong)
"""
import json, re, subprocess, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = "\n".join(p.read_text() for p in sorted((root / "Sources").glob("*.swift")))

def lit(s):  # Swift string literal body -> value (only the escapes we use)
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")

LITERAL = r'"((?:[^"\\]|\\.)*)"'
keys = {lit(m) for m in re.findall(r'\btr\(\s*' + LITERAL, src)}
keys |= {lit(m) for m in re.findall(r'\btrkey\(\s*' + LITERAL, src)}
plurals = {lit(m) for m in re.findall(r'\btrPlural\(\s*' + LITERAL, src)}
keys.discard("")

def load(lang):
    path = root / "Resources" / f"{lang}.lproj" / "App.strings"
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, text=True)
    if out.returncode:
        print(f"ERROR: {path} does not parse:\n{out.stderr}"); sys.exit(1)
    return json.loads(out.stdout)

en, uk = load("en"), load("uk")
problems = []

def specs(s):
    return sorted(re.sub(r"\d+\$", "", m) for m in re.findall(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?[a-zA-Z@%]", s) if m != "%%")

used_uk = set()
for k in sorted(keys):
    if k in uk:
        used_uk.add(k)
        base_en = en.get(k, k)
        if specs(base_en) != specs(uk[k]):
            problems.append(f"placeholders differ for {k!r}: English {specs(base_en)} vs Ukrainian {specs(uk[k])}")
        if not uk[k].strip():
            problems.append(f"empty Ukrainian text for {k!r}")
    elif not (k.startswith("health.") and False):
        problems.append(f"missing Ukrainian: {k!r}")

for base in sorted(plurals):
    for cat in ("one", "few", "many"):
        if f"{base}.{cat}" not in uk: problems.append(f"missing Ukrainian plural form {base}.{cat}")
        else: used_uk.add(f"{base}.{cat}")
    for cat in ("one", "other"):
        if f"{base}.{cat}" not in en: problems.append(f"missing English plural form {base}.{cat}")
    forms = [en.get(f"{base}.{c}") for c in ("one", "other")] + [uk.get(f"{base}.{c}") for c in ("one", "few", "many")]
    sp = {tuple(specs(f)) for f in forms if f}
    if len(sp) > 1: problems.append(f"plural forms of {base!r} use different placeholders: {sp}")

for k in sorted(set(uk) - used_uk):
    if not any(k == f"{b}.{c}" for b in plurals for c in ("one", "few", "many", "other")):
        problems.append(f"stale Ukrainian key (not used in code): {k!r}")
for k in sorted(set(en) - set(keys)):
    if not any(k == f"{b}.{c}" for b in plurals for c in ("one", "other")):
        problems.append(f"stale English key (not used in code): {k!r}")

print(f"{len(keys)} keys + {len(plurals)} plural phrases found in code; Ukrainian file has {len(uk)} entries, English {len(en)}.")
if problems:
    print(f"\n{len(problems)} problem(s):")
    for p in problems: print(" -", p)
    sys.exit(1)
print("OK: every key is translated, placeholders match, nothing stale.")

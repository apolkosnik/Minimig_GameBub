#!/usr/bin/env python3
"""Signals connected to an instance (or assigned by `assign`) before the line
that declares them.

Verilog makes an implicit one-bit net of an undeclared name in those two
places. Quartus and Verilator take the later declaration for it. Vivado
2018.3 does so only at a module's top level (Synth 8-992, "already implicitly
declared earlier"); inside a generate block it keeps the implicit net next
to the declared signal (Synth 8-605, "same-named implicit nets") and ties
what it drives to 0, without an error. The AP68040's instruction cache was
filled at set 0 only and its ATCs written at way 0 only that way: every
simulation passed, and on the FPGA the CPU failed as soon as the instruction
cache was on.

  tools/decl_before_use.py --check FILE...   list them; exit 1 if there are any
  tools/decl_before_use.py --fix IN OUT      move each such declaration to
                                             before the statement of its
                                             first use

tools/import_ap68040.py applies the fix to what it imports and
tools/build_variant.sh checks the staged CPU before Vivado runs;
sim/gls/run_cpu_gls.sh compares the netlist with the RTL.
SPDX-License-Identifier: GPL-3.0-or-later
"""
import re
import sys

NOTE = ("// (declared before their use: Vivado 2018.3 makes a separate implicit net of a\n"
        "// signal an instance is connected to ahead of its declaration)")


def _strip(text):
    """The text without comments, its lines kept."""
    text = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def scan(text):
    """[(module, name, line of the first use, 'port' | 'assign', line of the
    declaration, the declaration's type)], lines counted from 1."""
    bare = _strip(text)
    lines = bare.split('\n')
    types = set(re.findall(r'\}\s*(\w+)\s*;', bare)) | set(re.findall(r'typedef\s+[^;{]*?\b(\w+)\s*;', bare))
    kw = r'(?:wire|logic|reg|bit|tri|integer|int' + ''.join('|' + t for t in sorted(types)) + r')'
    decl_re = re.compile(r'^\s*(?:\(\*[^)]*\*\)\s*)?(?:(?:input|output|inout)\s+)?(?:var\s+)?(' + kw +
                         r')\b(?:\s+(?:signed|unsigned))?\s*((?:\[[^\]]*\]\s*)*)(.*)$')
    found = []
    mod = None
    decl = {}
    uses = []

    def flush():
        seen = set()
        for ln, name, kind in uses:
            if name in decl and decl[name][0] > ln and name not in seen:
                seen.add(name)
                found.append((mod, name, ln, kind, decl[name][0], decl[name][1]))

    for i, l in enumerate(lines, 1):
        m = re.match(r'^\s*module\s+(\w+)', l)
        if m:
            mod, decl, uses = m.group(1), {}, []
            continue
        if re.match(r'^\s*endmodule', l):
            flush()
            mod = None
            continue
        if mod is None:
            continue
        m = decl_re.match(l)
        if m and not re.match(r'^\s*(?:for|if|else|assign|return)\b', l):
            rest = re.sub(r'=[^,;]*', '', m.group(3))
            for name in re.findall(r'\b([A-Za-z_]\w*)\b\s*(?:\[[^\]]*\]\s*)*(?=,|;|$)', rest):
                decl.setdefault(name, (i, (m.group(1) + ' ' + m.group(2).strip()).strip()))
        for pm in re.finditer(r'\.\w+\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)', l):
            for name in re.findall(r"(?<![.'\w])([A-Za-z_]\w*)\b(?!\s*\()", pm.group(1)):
                uses.append((i, name, 'port'))
        am = re.match(r'^\s*assign\s+([A-Za-z_]\w*)', l)
        if am:
            uses.append((i, am.group(1), 'assign'))
    return found


def fix(text):
    """(the text with those declarations moved ahead of the statement of their
    first use, the number of declarations moved). A statement at a module's
    top level starts in column 1 in these sources; a use inside a generate
    region gets the declaration before the region."""
    L = text.split('\n')
    moves = {}   # line of the declaration -> line to put it before
    for _mod, _name, use, _kind, d, _type in scan(text):
        code = re.sub(r'//.*', '', L[d - 1]).strip()
        if not code.endswith(';') or code.count(';') != 1:
            sys.exit(f"line {d}: a declaration of more than one line or statement: {L[d - 1]}")
        a = use
        while not re.match(r'^[A-Za-z_(`]', L[a - 1]):
            a -= 1
        depth = 0
        for i in range(a, 0, -1):
            if re.match(r'^endgenerate\b', L[i - 1]):
                depth += 1
            elif re.match(r'^generate\b', L[i - 1]):
                if depth == 0:
                    a = i
                    break
                depth -= 1
            elif re.match(r'^module\b', L[i - 1]):
                break
        while re.match(r'^\s*(//|\(\*)', L[a - 2]):   # its comment and attribute
            a -= 1
        moves[d] = min(a, moves.get(d, a))
    before = {}
    for d, a in sorted(moves.items()):
        before.setdefault(a, []).append(d)
    out = []
    for i in range(1, len(L) + 1):
        if i in before:
            out.append(NOTE)
            out.extend(L[d - 1] for d in before[i])
        if i not in moves:
            out.append(L[i - 1])
    fixed = '\n'.join(out)
    left = scan(fixed)
    if left:
        sys.exit("still used before their declaration: " + ', '.join(f"{m}.{n}" for m, n, *_ in left))
    return fixed, len(moves)


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == '--check':
        bad = 0
        for path in sys.argv[2:]:
            for mod, name, use, kind, d, typ in scan(open(path).read()):
                bad += 1
                print(f"{path}:{use}: {mod}.{name} used ({kind}) before its declaration at line {d} ({typ})")
        if bad:
            print(f"{bad} signals used before their declaration: Vivado 2018.3 may synthesize "
                  "separate nets for them (tools/decl_before_use.py)")
        sys.exit(1 if bad else 0)
    if len(sys.argv) == 4 and sys.argv[1] == '--fix':
        fixed, n = fix(open(sys.argv[2]).read())
        open(sys.argv[3], 'w').write(fixed)
        print(f"{n} declarations moved")
        return
    sys.exit(__doc__)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Where do the flops go? Attribute a design's registers to named signals.

Runs Yosys up to the end of coarse synthesis (registers are still word-level
cells, after the optimizations that remove unused and constant registers),
writes JSON, and maps every flop bit back to the named signal its Q drives.
Groups by name prefix (the process or object a generated register came from).

  scripts/synth_attrib.py <verilog...> --top <module> [--depth N]

Prints flop bits per signal, then per prefix group (the first N
'_'-separated components of the name).
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
YOSYS = os.path.join(HERE, "..", "packages", "yosys", "bin", "yosys")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--top", required=True)
    ap.add_argument("--depth", type=int, default=3)
    ap.add_argument("--signals", action="store_true", help="list every signal")
    ap.add_argument("--luts", action="store_true",
                    help="also attribute iCE40 LUTs to the registers they feed")
    a = ap.parse_args()
    if a.luts:
        return lut_attrib(a)
    with tempfile.TemporaryDirectory() as td:
        js = os.path.join(td, "d.json")
        reads = "; ".join(f"read_verilog -sv {f}" for f in a.files)
        cmd = (f"{reads}; synth -top {a.top} -flatten -run :fine; opt -full; opt_clean -purge; "
               f"write_json {js}")
        r = subprocess.run([YOSYS, "-q", "-p", cmd], capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stdout + r.stderr)
            return 1
        d = json.load(open(js))
    mod = d["modules"][a.top]
    bitname = {}
    for name, nn in mod["netnames"].items():
        hidden = name.startswith("$") or nn.get("hide_name")
        for i, b in enumerate(nn["bits"]):
            if not isinstance(b, int):
                continue
            prev = bitname.get(b)
            if prev is None or (prev[2] and not hidden):
                bitname[b] = (name, i, hidden)
    per_sig = collections.Counter()
    for cname, c in mod["cells"].items():
        if "dff" not in c["type"] and "dlatch" not in c["type"]:
            continue
        for b in c["connections"].get("Q", []):
            nm = bitname.get(b, ("?", 0, True))[0]
            per_sig[nm] += 1
    total = sum(per_sig.values())
    groups = collections.Counter()
    for nm, n in per_sig.items():
        groups["_".join(nm.lstrip("\\").split("_")[:a.depth])] += n
    print(f"flop bits: {total}")
    for g, n in groups.most_common():
        print(f"  {n:4d}  {g}")
    if a.signals:
        print()
        for nm, n in per_sig.most_common():
            print(f"  {n:4d}  {nm}")
    return 0


def lut_attrib(a) -> int:
    """synth_ice40, then charge every LUT/carry to the flops whose D/enable/
    reset cone it is in (split evenly when shared) or to the outputs."""
    with tempfile.TemporaryDirectory() as td:
        js = os.path.join(td, "d.json")
        reads = "; ".join(f"read_verilog -sv {f}" for f in a.files)
        cmd = f"{reads}; synth_ice40 -device u -top {a.top}; write_json {js}"
        r = subprocess.run([YOSYS, "-q", "-p", cmd], capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stdout + r.stderr)
            return 1
        d = json.load(open(js))
    mod = d["modules"][a.top]
    bitname = {}

    def rank(name, nn):
        # prefer a source name over generated ones (yosys $..., emitter _tN,
        # techmap *_SB_LUT4_*)
        n = name.lstrip("\\")
        return (bool(name.startswith("$") or nn.get("hide_name")), n.startswith("_t"),
                "_SB_" in n, len(n))
    for name, nn in mod["netnames"].items():
        r_ = rank(name, nn)
        for b in nn["bits"]:
            if isinstance(b, int):
                prev = bitname.get(b)
                if prev is None or r_ < prev[2]:
                    bitname[b] = (name, r_[0], r_)
    driver = {}           # bit -> comb cell name
    comb = {}
    ffs = []
    for cname, c in mod["cells"].items():
        t = c["type"]
        if t.startswith("SB_DFF"):
            ffs.append((cname, c))
        elif t in ("SB_LUT4", "SB_CARRY"):
            comb[cname] = c
            for port, dirn in c["port_directions"].items():
                if dirn == "output":
                    for b in c["connections"][port]:
                        driver[b] = cname

    def cone(bits):
        seen = set()
        stack = [b for b in bits if isinstance(b, int)]
        while stack:
            b = stack.pop()
            cn = driver.get(b)
            if cn is None or cn in seen:
                continue
            seen.add(cn)
            c = comb[cn]
            for port, dirn in c["port_directions"].items():
                if dirn == "input":
                    stack.extend(x for x in c["connections"][port] if isinstance(x, int))
        return seen

    users = collections.defaultdict(set)
    def group_of(name):
        return "_".join(name.lstrip("\\").split("_")[:a.depth])
    for cname, c in ffs:
        q = c["connections"]["Q"][0]
        g = group_of(bitname.get(q, ("?", True))[0])
        ins = []
        for port in ("D", "E", "R", "S"):
            ins += c["connections"].get(port, [])
        for cn in cone(ins):
            users[cn].add(g)
    for pname, pinfo in mod["ports"].items():
        if pinfo["direction"] == "output":
            for cn in cone(pinfo["bits"]):
                users[cn].add("<out>" + group_of(pname))
    charge = collections.Counter()
    for cn, c in comb.items():
        if c["type"] != "SB_LUT4":
            continue
        gs = users.get(cn) or {"<unused>"}
        for g in gs:
            charge[g] += 1.0 / len(gs)
    nlut = sum(1 for c in comb.values() if c["type"] == "SB_LUT4")
    print(f"SB_LUT4: {nlut}, flops: {len(ffs)}")
    for g, n in charge.most_common():
        print(f"  {n:7.1f}  {g}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

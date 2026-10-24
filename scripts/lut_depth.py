#!/usr/bin/env python3
"""LUT depth by endpoint in a synth_ice40 JSON netlist.

    scripts/lut_depth.py design.json [--top pnr_top] [--min N] [--paths K]

Each path starts at a flop output or a top input and ends at a flop's D, E,
R or S pin or a top output. Depth counts SB_LUT4s; an SB_CARRY counts 0.25
(a carry hop is short next to a LUT and its routing). nextpnr's Fmax tracks
the deepest paths at about 2.6-3.5 ns per LUT level on the UP5K, so the
population of deep endpoints is a placement-independent view of timing.

Prints a histogram of endpoint depth, the endpoints at depth >= --min
grouped by register name, and the --paths deepest paths with the flops
(or inputs) they start from.
"""
import argparse
import collections
import json
import re
import sys

FLOP_IN = {"D", "E", "R", "S"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("--top", default="pnr_top")
    ap.add_argument("--min", type=float, default=6)
    ap.add_argument("--paths", type=int, default=10)
    ap.add_argument("--trace", action="store_true",
                    help="print the nets along each of the deepest paths")
    ap.add_argument("--to", help="only endpoints whose name matches this regex")
    a = ap.parse_args()

    mod = json.load(open(a.json))["modules"][a.top]
    # A bit's name: prefer one from the source (no "_SB_" from techmap and
    # no "$" from yosys), then the shortest.
    def rank(n):
        return ("_SB_" in n or "$" in n, len(n))
    names = {}
    for n, v in mod["netnames"].items():
        for i, b in enumerate(v["bits"]):
            nb = n if len(v["bits"]) == 1 else f"{n}[{i}]"
            if isinstance(b, int) and (b not in names or rank(nb) < rank(names[b])):
                names[b] = nb
    driver = {}       # bit -> (cell, kind)
    cells = mod["cells"]
    for cn, c in cells.items():
        for p, bits in c["connections"].items():
            if c["port_directions"].get(p) == "output":
                for b in bits:
                    if isinstance(b, int):
                        driver[b] = cn

    memo = {}
    pred = {}    # bit -> the input bit on its deepest path

    def arr(bit):
        """(depth, start) of a bit: 0 at a flop output or a top input."""
        if not isinstance(bit, int):
            return (0.0, "const")
        if bit in memo:
            return memo[bit]
        cn = driver.get(bit)
        if cn is None:
            r = (0.0, "in:" + names.get(bit, str(bit)))
        else:
            c = cells[cn]
            t = c["type"]
            if t.startswith("SB_DFF") or t in ("SB_RAM40_4K",):
                r = (0.0, "ff:" + names.get(c["connections"]["Q"][0], cn)
                     if "Q" in c["connections"] else cn)
            elif t in ("SB_LUT4", "SB_CARRY"):
                w = 1.0 if t == "SB_LUT4" else 0.25
                memo[bit] = (0.0, "loop")
                best, via = (0.0, "const"), None
                for p, bits in c["connections"].items():
                    if c["port_directions"].get(p) == "input":
                        for b in bits:
                            d = arr(b)
                            if d[0] > best[0] or best[1] == "const":
                                best, via = d, b
                pred[bit] = via
                r = (best[0] + w, best[1])
            else:
                r = (0.0, t + ":" + cn)
        memo[bit] = r
        return r

    sys.setrecursionlimit(100000)
    ends = []   # (depth, endpoint, pin, start)
    for cn, c in cells.items():
        if c["type"].startswith("SB_DFF"):
            q = names.get(c["connections"]["Q"][0], cn)
            for p in FLOP_IN & set(c["connections"]):
                d, s = arr(c["connections"][p][0])
                ends.append((d, q, p, s, c["connections"][p][0]))
    for pn, p in mod["ports"].items():
        if p["direction"] == "output":
            for b in p["bits"]:
                d, s = arr(b)
                ends.append((d, "out:" + pn, "", s, b))

    hist = collections.Counter(int(e[0]) for e in ends)
    print("endpoint depth histogram (LUT levels, carry 0.25):")
    for k in sorted(hist):
        print(f"  {k:2d}: {hist[k]}")

    def base(n):
        n = re.sub(r"\[\d+\]$", "", n)
        n = re.sub(r"_SB_.*", "", n)
        return n

    grp = collections.defaultdict(list)
    for e in ends:
        if e[0] >= a.min:
            grp[base(e[1])].append(e)
    print(f"\nendpoints at depth >= {a.min:g}, by register:")
    for k, v in sorted(grp.items(), key=lambda kv: -max(e[0] for e in kv[1])):
        starts = collections.Counter(base(e[3]) for e in v)
        print(f"  {max(e[0] for e in v):5.2f} {len(v):4d}  {k}")
        for s, n in starts.most_common(4):
            print(f"           from {s} ({n})")

    sel = [e for e in ends if re.search(a.to, e[1])] if a.to else ends
    print(f"\nthe {a.paths} deepest" + (f" to /{a.to}/:" if a.to else ":"))
    for e in sorted(sel, key=lambda e: -e[0])[: a.paths]:
        print(f"  {e[0]:5.2f}  {e[3]} -> {e[1]}.{e[2]}")
        if a.trace:
            chain, b = [], e[4]
            while b in pred and pred[b] is not None:
                chain.append(b)
                b = pred[b]
            chain.append(b)
            for b in reversed(chain):
                print(f"           {memo.get(b, (0,))[0]:5.2f} {names.get(b, b)}")


if __name__ == "__main__":
    main()

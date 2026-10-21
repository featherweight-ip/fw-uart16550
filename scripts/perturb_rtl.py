#!/usr/bin/env python3
"""Reorder a Yosys-written netlist without changing it (for scripts/synth-baseline.sh).

The input is `write_verilog -noattr` output of the reference RTL after
`proc; flatten`. Within each module, the one-line ``assign`` statements are
shuffled with the given seed (seed 0 leaves the file as it is). ABC's result
depends on statement order, so an area is quoted as the median over seeds
(as fw-i2c scripts/perturb_netlist.py does for the lowered netlist).

  scripts/perturb_rtl.py <in.v> <out.v> <seed>
"""
import random
import re
import sys

ASSIGN = re.compile(r"^\s*assign\s.*;\s*$")


def main() -> int:
    src, dst, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    rng = random.Random(seed)
    out, assigns = [], []
    for ln in open(src).read().split("\n"):
        if seed and ASSIGN.match(ln):
            assigns.append(ln)
            continue
        if ln.startswith("endmodule"):
            rng.shuffle(assigns)
            out.extend(assigns)
            assigns = []
        out.append(ln)
    open(dst, "w").write("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

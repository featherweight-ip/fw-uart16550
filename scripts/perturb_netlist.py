#!/usr/bin/env python3
"""Reorder a generated netlist without changing it (for scripts/synth-lowered.sh).

Every one-line ``wire [..] name = expr;`` becomes a declaration plus an
``assign``, and the assigns are shuffled with the given seed. Top-level
``always`` blocks (structured emission: a ``// process`` comment, then the
block, ending at a 4-space ``end``) are shuffled among themselves too. Synthesis
results move by a few percent on such changes (ABC is order-sensitive), so
an area is quoted as the median over several seeds.

  scripts/perturb_netlist.py <in.v> <out.v> <seed>
"""
import random
import re
import sys

WIRE = re.compile(r"^(\s*)wire\s+(\[[^\]]+\]\s+)?(\w+)\s*=\s*(.*);\s*$")


def main() -> int:
    src, dst, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    lines = open(src).read().split("\n")
    decls, assigns, out = [], [], []
    endm = None
    for i, ln in enumerate(lines):
        m = WIRE.match(ln)
        if m and seed:
            ind, rng, name, expr = m.groups()
            decls.append(f"{ind}wire {rng or ''}{name};")
            assigns.append(f"{ind}assign {name} = {expr};")
            continue
        if ln.strip() == "endmodule" and endm is None and decls:
            endm = len(out)
        out.append(ln)
    if not seed or not decls:
        open(dst, "w").write("\n".join(lines))
        return 0
    rng_ = random.Random(seed)
    rng_.shuffle(assigns)
    out = _shuffle_blocks(out, rng_)
    # declarations where the first wire was; assigns before the endmodule
    first = next(i for i, ln in enumerate(lines) if WIRE.match(ln))
    head = [ln for ln in lines[:first]]
    rest = out[len(head):]
    endm = max(i for i, ln in enumerate(rest) if ln.strip() == "endmodule")
    res = head + decls + rest[:endm] + assigns + rest[endm:]
    open(dst, "w").write("\n".join(res))
    return 0


def _shuffle_blocks(lines, rng_):
    """Shuffle the multi-line top-level always blocks among their slots."""
    blocks, slots, out, i = [], [], [], 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("    // process ") or ln.startswith("    always @"):
            j = i
            if ln.startswith("    // process "):
                j += 1
            if not lines[j].rstrip().endswith("begin"):
                out.append(ln)
                i += 1
                continue
            k = j + 1
            while lines[k] != "    end":
                k += 1
            slots.append(len(out))
            out.append(None)
            blocks.append(lines[i:k + 1])
            i = k + 1
            continue
        out.append(ln)
        i += 1
    rng_.shuffle(blocks)
    for s_, b in zip(slots, blocks):
        out[s_] = "\n".join(b)
    return out


if __name__ == "__main__":
    sys.exit(main())

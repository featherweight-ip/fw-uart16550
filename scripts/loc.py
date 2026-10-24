#!/usr/bin/env python3
"""Lines of code, comment and blank in SystemVerilog, Verilog and RDL files.

    scripts/loc.py [--each] file... [-- label file...]...

Groups are separated by `--`; a group's first word is its label (the first
group is "files" unless it starts with a label ending in ':'). A line with
any code on it counts as code; a line with only a comment (// or /* */)
counts as comment.
"""
import sys


def count(path):
    code = comment = blank = 0
    in_block = False
    for line in open(path, errors="replace"):
        s = line.strip()
        has_code = has_comment = False
        i = 0
        while i < len(s):
            if in_block:
                j = s.find("*/", i)
                has_comment = True
                if j < 0:
                    i = len(s)
                else:
                    in_block = False
                    i = j + 2
            elif s.startswith("//", i):
                has_comment = True
                break
            elif s.startswith("/*", i):
                in_block = True
                i += 2
            elif s[i] == '"':
                j = s.find('"', i + 1)
                has_code = True
                i = len(s) if j < 0 else j + 1
            else:
                if not s[i].isspace():
                    has_code = True
                i += 1
        if has_code:
            code += 1
        elif has_comment:
            comment += 1
        else:
            blank += 1
    return code, comment, blank


def main(argv):
    each = "--each" in argv
    argv = [a for a in argv if a != "--each"]
    groups, cur = [], []
    for a in argv:
        if a == "--":
            groups.append(cur)
            cur = []
        else:
            cur.append(a)
    groups.append(cur)
    print(f"{'':34s} {'files':>5s} {'code':>6s} {'comment':>8s} {'blank':>6s} {'total':>6s}")
    for g in groups:
        if not g:
            continue
        label, files = (g[0][:-1], g[1:]) if g[0].endswith(":") else ("files", g)
        tot = [0, 0, 0]
        for f in files:
            c = count(f)
            tot = [a + b for a, b in zip(tot, c)]
            if each:
                print(f"  {f[-32:]:32s} {'':5s} {c[0]:6d} {c[1]:8d} {c[2]:6d} {sum(c):6d}")
        print(f"{label:34s} {len(files):5d} {tot[0]:6d} {tot[1]:8d} {tot[2]:6d} {sum(tot):6d}")


if __name__ == "__main__":
    main(sys.argv[1:])

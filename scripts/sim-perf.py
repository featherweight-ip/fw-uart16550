#!/usr/bin/env python3
"""Simulation speed of the views' sim images (docs/results.md, "Simulation
performance").

    scripts/sim-perf.py [--views wb,rtl,ref] [--reps 3] [--build]

Runs each view's simv (built by `dfm run uvm-universal` / `uvm-perf`) on
the universal cases and the stream test at several lengths, REPS times
each, in rundir/perf/. Reports the median wall time, the simulated clocks
(the TEST PASSED line's time over the 10 ns clock) and clocks per wall
second. The stream lengths give the marginal speed: the slope between the
longest and the shortest, with UVM start-up and init() taken out.

--build also re-runs each image's verilate and C++ compile from its
build.f into rundir/perf/build-<view>/ and times the two.
"""
import argparse
import os
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNDIR = os.path.join(ROOT, "rundir")
IMG = os.path.join(RUNDIR, "org.fwip.uart16550.uvm.sim-img.{}",
                   "project.dv.uvm.utils.tb-img.sim-img")
CLOCK_PS = 10_000

CASES = [
    ("smoke", "fw_uart16550_smoke_test", []),
    ("regs", "fw_uart16550_regs_test", []),
    ("line", "fw_uart16550_line_test", []),
    ("status", "fw_uart16550_status_test", []),
    ("irq", "fw_uart16550_irq_test", []),
    ("stream-0", "fw_uart16550_stream_test", ["+blocks=0"]),
    ("stream-16", "fw_uart16550_stream_test", ["+blocks=16"]),
    ("stream-64", "fw_uart16550_stream_test", ["+blocks=64"]),
]


def run_case(view, name, test, plus, rep):
    d = os.path.join(RUNDIR, "perf", f"{view}-{name}-{rep}")
    os.makedirs(d, exist_ok=True)
    simv = os.path.join(IMG.format(view), "obj_dir", "simv")
    log = os.path.join(d, "sim.log")
    t0 = time.perf_counter()
    with open(log, "w") as f:
        rc = subprocess.call([simv, f"+UVM_TESTNAME={test}", *plus],
                             cwd=d, stdout=f, stderr=subprocess.STDOUT)
    wall = time.perf_counter() - t0
    txt = open(log).read()
    m = re.search(r"@ (\d+): uvm_test_top \[RESULT\] \*\* TEST PASSED", txt)
    if rc != 0 or not m:
        sys.exit(f"{view} {name}: failed (rc {rc}); see {log}")
    return wall, int(m.group(1)) // CLOCK_PS


def build(view):
    """(verilate s, compile s) for one image, rebuilt from its build.f."""
    src = IMG.format(view)
    d = os.path.join(RUNDIR, "perf", f"build-{view}")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    lines = open(os.path.join(src, "build.f")).read().splitlines()
    cut = lines.index("# make phase:")
    vargs = [a for a in lines[:cut] if a]
    margs = [a for a in lines[cut + 1:] if a]
    # Paths in build.f are absolute, except the DPI source the dfm task
    # stages in its rundir; the make phase runs in obj_dir.
    t0 = time.perf_counter()
    with open(os.path.join(d, "verilate.log"), "w") as f:
        subprocess.check_call(["verilator", *vargs], cwd=d, stdout=f,
                              stderr=subprocess.STDOUT)
    t1 = time.perf_counter()
    with open(os.path.join(d, "make.log"), "w") as f:
        subprocess.check_call(margs, cwd=d, stdout=f, stderr=subprocess.STDOUT)
    t2 = time.perf_counter()
    return t1 - t0, t2 - t1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--views", default="wb,rtl,ref")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--build", action="store_true")
    a = ap.parse_args()
    views = a.views.split(",")

    res = {}
    for v in views:
        for name, test, plus in CASES:
            runs = [run_case(v, name, test, plus, r) for r in range(a.reps)]
            res[v, name] = (statistics.median(w for w, _ in runs), runs[0][1])

    print(f"{'case':10s}" + "".join(f" {v + ' s':>8s} {v + ' kclk/s':>11s}" for v in views)
          + f" {'clocks':>9s}")
    for name, _, _ in CASES:
        row = f"{name:10s}"
        for v in views:
            w, c = res[v, name]
            row += f" {w:8.2f} {c / w / 1e3:11.1f}"
        print(row + f" {res[views[0], name][1]:9d}")
    print("marginal (stream-64 minus stream-0):")
    for v in views:
        (w0, c0), (w1, c1) = res[v, "stream-0"], res[v, "stream-64"]
        print(f"  {v:4s} {(c1 - c0) / (w1 - w0) / 1e3:8.1f} kclk/s"
              f"  ({c1 - c0} clocks in {w1 - w0:.2f} s)")

    if a.build:
        print("build (verilate s, C++ compile s):")
        for v in views:
            vt, mt = build(v)
            print(f"  {v:4s} {vt:7.1f} {mt:7.1f}")


if __name__ == "__main__":
    main()

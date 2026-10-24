#!/usr/bin/env bash
# Time scripts/repro/wait_styles.sv on Verilator, xsim and xezim (those that
# are installed), style by style. Run under direnv (packages on PATH).
set -u
here=$(cd "$(dirname "$0")" && pwd)
src=$here/wait_styles.sv
out=${OUT:-$(mktemp -d)}
cd "$out"
styles="5 0 1 2 3 4"
t() { /usr/bin/time -f "%e" "$@" 2>&1 >/dev/null | tail -1; }
if command -v verilator >/dev/null; then
    verilator --binary --timing -O3 -Wno-fatal "$src" --top-module top -o simv >vlt.log 2>&1
    for s in $styles; do echo "verilator style $s: $(t obj_dir/simv +style=$s) s"; done
fi
if command -v xvlog >/dev/null; then
    { xvlog -sv "$src" && xelab top -s wbsnap -O3 --timescale 1ns/1ps; } >xsim.log 2>&1
    for s in $styles; do echo "xsim style $s: $(t xsim wbsnap -R -testplusarg style=$s) s"; done
fi
if command -v xezim >/dev/null; then
    for s in $styles; do echo "xezim style $s: $(t xezim "$src" -s top --max-time 1s +style=$s) s"; done
fi

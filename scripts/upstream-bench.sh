#!/bin/bash
# Run the upstream uart16550 interrupt test (bench/verilog/test_cases/uart_int.v)
# under Icarus on tags u2b0 and u2b0-fw1 of the oc-uart16550 fork (plan U11).
#
# Usage: scripts/upstream-bench.sh <oc-uart16550-repo> [8|32] [outdir]
#   8  (default) +define+DATA_BUS_WIDTH_8: reproduces the shipped
#      sim/rtl_sim/log/uart_interrupts_report.log exactly.
#   32 default config: the bench writes with sel=4'hF, which 2b0ad80's
#      uart_wb decodes as byte 0, so the LCR write lands in THR and the
#      bench fails at initialization. Kept to show that.
#
# Two bench-only Icarus workarounds (same-time races; rtl/ is untouched):
#  1. uart_testbench.v:277  `wb_clk = 1'b0;` -> `#0 wb_clk = 1'b0;`
#     (otherwise always @(negedge wb_clk) is not yet waiting; wb_clk never toggles)
#  2. uart_device.v:345     sampler `begin` -> `begin #0;`
#     (the sampler races the rx_sample_clock generator and never samples)
#
# Outputs: <outdir>/<u2b0|fw1>/log/uart_interrupts_{report,verbose}.log and sim.log.
# Needs iverilog/vvp on PATH (fw-i2c: packages/iverilog/bin). Slow (the test
# runs 5.7 s of simulated time); both versions run in parallel, each with a
# TIMEOUT (seconds, default 7200).
set -euo pipefail
repo=$(cd "$1" && pwd); mode=${2:-8}
out=${3:-rundir/upstream-bench/$mode}
def=""; [ "$mode" = 8 ] && def="-DDATA_BUS_WIDTH_8"
mkdir -p "$out"; out=$(cd "$out" && pwd)
for pair in u2b0:u2b0 fw1:u2b0-fw1; do
  d=$out/${pair%%:*}; tag=${pair##*:}
  rm -rf "$d"; mkdir -p "$d/log" "$d/run"
  git -C "$repo" archive "$tag" rtl bench | tar -x -C "$d"
  sed -i "277s/^  wb_clk = 1'b0;/  #0 wb_clk = 1'b0; \/\/ Icarus workaround/" "$d/bench/verilog/uart_testbench.v"
  sed -i "345s/^  begin$/  begin #0; \/\/ Icarus workaround/" "$d/bench/verilog/uart_device.v"
  for f in uart_testbench.v uart_device.v; do
    grep -q 'Icarus workaround' "$d/bench/verilog/$f" \
      || { echo "workaround did not apply to $f in $d" >&2; exit 1; }
  done
  V=$d/rtl/verilog; B=$d/bench/verilog
  iverilog -g2005 $def -o "$d/run/sim" -I"$V" -I"$B" -y"$V" -y"$B" \
    "$B/uart_testbench.v" "$B/test_cases/uart_int.v" "$B/uart_wb_utilities.v" \
    "$B/uart_testbench_utilities.v" "$B/uart_device_utilities.v" "$B/uart_log.v" \
    > "$d/build.log" 2>&1
  (cd "$d/run" && { timeout "${TIMEOUT:-7200}" vvp -n ./sim > ../sim.log 2>&1; echo "vvp rc=$?" >> ../sim.log; }) &
done
wait
for v in u2b0 fw1; do echo "== $v"; grep -E 'PASSED|FAILED|Failure message' "$out/$v/log/uart_interrupts_report.log" || true; done

#!/usr/bin/env bash
# Area of fw-uart16550 lowered to RTL: the netlist from `dfm run lowered`
# through the baseline's flow (docs/reference/synthesis.md). From fw-i2c's
# scripts/synth-lowered.sh.
#
#   scripts/synth-lowered.sh [outdir]
#   NET=path/to/fw_uart16550_top.v scripts/synth-lowered.sh outdir   (another netlist)
#
# The lowering absorbs the kit cores and the synchronizer, so the netlist is
# one flat module. The library cores are also synthesized alone from their
# sources, as the library share (the design's own logic is the rest).
#
# Reports (in outdir, default rundir/synth-lowered):
#   ice40.stat      synth_ice40 -device u, flattened (the comparison with U2B0)
#   generic.stat    synth -flatten; abc -g (technology-neutral cross-check)
#   classes.txt     iCE40 LUTs and flops by register (scripts/synth_attrib.py)
#   spread.txt      LUT4 and generic gates over $SEEDS (11) runs of the netlist
#                   with its statements reordered (scripts/perturb_netlist.py);
#                   compare medians, not single runs
#   lib.txt         the library cores alone: LUT4, FF, CARRY each
# Needs the ivpm tools on PATH (direnv) and a run of `dfm run lowered`.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$here/rundir/synth-lowered}
mkdir -p "$out"
P=$here/packages
top=fw_uart16550_top
net=${NET:-$here/rundir/org.fwip.uart16550.lowered/$top.v}
[ -f "$net" ] || { echo "no $net: run 'dfm run lowered' first" >&2; exit 1; }
GATES="AND,NAND,OR,NOR,XOR,XNOR,MUX"
gsum() { awk 'NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^\$_/ && $2 !~ /DFF/ {s += $1} END {print s+0}' "$1"; }
lut()  { grep -E 'SB_LUT4' "$1" | awk '{print $1}'; }
ff()   { grep -E 'SB_DFF' "$1" | awk '{s+=$1} END {print s+0}'; }
cy()   { grep -E 'SB_CARRY' "$1" | awk '{s+=$1} END {print s+0}'; }

yosys -q -p "read_verilog $net; synth_ice40 -device u -top $top; \
    tee -q -o $out/ice40.stat stat" > "$out/ice40.log" 2>&1
yosys -q -p "read_verilog $net; synth -flatten -top $top; \
    abc -g $GATES; opt_clean; tee -q -o $out/generic.stat stat" > "$out/generic.log" 2>&1
python3 "$here/scripts/synth_attrib.py" "$net" --top $top --luts --depth 3 \
    > "$out/classes.txt" 2>&1 || true

# spread: the same netlist, statements reordered $SEEDS ways
: > "$out/spread.txt"
for k in $(seq 0 $((${SEEDS:-11} - 1))); do
    python3 "$here/scripts/perturb_netlist.py" "$net" "$out/p$k.v" $((k + 1))
    yosys -q -p "read_verilog $out/p$k.v; synth_ice40 -device u -top $top; \
        tee -q -o $out/p$k.stat stat; design -reset; read_verilog $out/p$k.v; \
        synth -flatten -top $top; abc -g $GATES; opt_clean; \
        tee -q -o $out/p$k.gstat stat" > "$out/p$k.log" 2>&1
    echo "$(lut "$out/p$k.stat") $(gsum "$out/p$k.gstat")" >> "$out/spread.txt"
    rm -f "$out/p$k.v" "$out/p$k.log"
done
med() { cut -d' ' -f$1 "$out/spread.txt" | sort -n | awk '{a[NR]=$1} END {printf "median %d (min %d, max %d)", a[int((NR+1)/2)], a[1], a[NR]}'; }

# The library cores alone (their default parameters are the design's).
sv2v -I"$P/fw-proto-wb/src" -I"$P/fw-proto-uart/src" \
    "$P/fw-proto-wb/src/wb_target_xtor_core.sv" \
    "$P/fw-proto-uart/src/uart_baud_xtor_core.sv" \
    "$P/fw-proto-uart/src/uart_tx_xtor_core.sv" \
    "$P/fw-proto-uart/src/uart_rx_xtor_core.sv" \
    "$here/src/spl-rtl/fw_uart16550_sync.sv" > "$out/lib.v"
: > "$out/lib.txt"
for name in wb_target_xtor_core uart_baud_xtor_core uart_tx_xtor_core uart_rx_xtor_core \
            fw_uart16550_sync; do
    yosys -q -p "read_verilog $out/lib.v; synth_ice40 -device u -top $name; \
        tee -q -o $out/lib_$name.stat stat" > "$out/lib_$name.log" 2>&1
    printf "  %-22s LUT4 %4d  FF %4d  CARRY %3d\n" "$name" "$(lut "$out/lib_$name.stat")" \
        "$(ff "$out/lib_$name.stat")" "$(cy "$out/lib_$name.stat")" >> "$out/lib.txt"
done

echo "flattened iCE40: $(lut "$out/ice40.stat") LUT4, $(ff "$out/ice40.stat") FF, $(cy "$out/ice40.stat") CARRY"
echo "generic gates:   $(gsum "$out/generic.stat") (flops not counted)"
echo "spread, LUT4:    $(med 1)"
echo "spread, generic: $(med 2)"
echo "library cores alone:"
cat "$out/lib.txt"

#!/bin/bash
# Synthesize the freecores uart16550 core (the reference, U2B0) at a given
# commit and print its area: generic gates, iCE40 (synth_ice40 -device u) as
# the median over $SEEDS reordered runs, the per-module breakdown, and, for
# the 8-bit core, nextpnr place-and-route on the iCEBreaker (UP5K-SG48).
#
# Usage: scripts/synth-baseline.sh <oc-uart16550-repo> <rev> <config> [outdir]
#   config  8      +define+DATA_BUS_WIDTH_8, top uart_top (the core of ref-rtl)
#           32     no defines, top uart_top (32-bit bus with debug; ref-rtl-32)
#           shim   +define+DATA_BUS_WIDTH_8, top oc_uart16550_wb32
#                  (src/ref/oc_uart16550_wb32.sv: ref-rtl as fw-uart16550
#                  compares it). Also checks the shim adds no cells over the
#                  8-bit core.
#   e.g. scripts/synth-baseline.sh ../oc-uart16550 u2b0-fw1 shim
#
# The median: ABC's result depends on statement order (fw-i2c synthesis-plan
# §0.5). The RTL is read, `proc; flatten`ed and written back by Yosys; that
# netlist's assigns are shuffled by scripts/perturb_rtl.py (seed 0 = as
# written) and each version goes through synth_ice40. FF counts are
# deterministic. The single run from the RTL itself is also reported.
#
# Outputs in outdir (default rundir/synth-baseline/<rev>-<config>):
#   generic.stat   synth -flatten; abc -g to 2-input gates and MUX
#   ice40.stat     synth_ice40 -device u, flattened, from the RTL
#   ice40_nf.stat  the same with hierarchy kept (per-module breakdown)
#   spread.txt     LUT4 per seed
#   pnr.log        nextpnr-ice40 (config 8 only; the others need more pins
#                  than SG48 has)
# Needs yosys and nextpnr-ice40 on PATH (or YOSYS, NEXTPNR); Yosys 0.69 for
# numbers comparable with docs/reference/synthesis.md.
set -euo pipefail
repo=$1; rev=$2; config=$3
out=${4:-rundir/synth-baseline/$rev-$config}
here=$(cd "$(dirname "$0")/.." && pwd)
YOSYS=${YOSYS:-yosys}
NEXTPNR=${NEXTPNR:-nextpnr-ice40}
SEEDS=${SEEDS:-11}
case $config in
  8)    def=-DDATA_BUS_WIDTH_8; top=uart_top ;;
  32)   def=""; top=uart_top ;;
  shim) def=-DDATA_BUS_WIDTH_8; top=oc_uart16550_wb32 ;;
  *)    echo "config must be 8, 32 or shim" >&2; exit 2 ;;
esac
mkdir -p "$out/src"
out=$(cd "$out" && pwd)
rm -rf "$out/src/rtl"
git -C "$repo" archive "$rev" rtl/verilog | tar -x -C "$out/src"
d=$out/src/rtl/verilog
files="raminfr.v uart_debug_if.v uart_receiver.v uart_regs.v uart_rfifo.v
  uart_sync_flops.v uart_tfifo.v uart_top.v uart_transmitter.v uart_wb.v"
read="read_verilog $def -I$d $(for f in $files; do printf '%s ' "$d/$f"; done)"
if [ $config = shim ]; then
  read="$read; read_verilog -sv $def $here/src/ref/oc_uart16550_wb32.sv"
fi

$YOSYS -q -l "$out/generic.log" -p "$read; synth -top $top -flatten; \
  abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; tee -q -o $out/generic.stat stat"
$YOSYS -q -l "$out/ice40.log" -p "$read; synth_ice40 -device u -top $top \
  -json $out/ice40.json; tee -q -o $out/ice40.stat stat"
$YOSYS -q -l "$out/ice40_nf.log" -p "$read; synth_ice40 -device u -top $top \
  -noflatten; tee -q -o $out/ice40_nf.stat stat"
$YOSYS -q -l "$out/net.log" -p "$read; hierarchy -top $top; proc; flatten; \
  opt_clean; write_verilog -noattr $out/net.v"

lut() { awk '$2 == "SB_LUT4" {print $1}' "$1"; }
carry() { awk '$2 == "SB_CARRY" {print $1}' "$1"; }
ff() { awk '$2 ~ /^SB_DFF/ {s += $1} END {print s + 0}' "$1"; }
bram() { awk '$2 == "SB_RAM40_4K" {s += $1} END {print s + 0}' "$1"; }
gates() { awk 'NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^\$_/ && $2 !~ /DFF/ {s += $1}
  END {print s + 0}' "$1"; }
gff() { awk 'NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^\$_/ && $2 ~ /DFF/ {s += $1}
  END {print s + 0}' "$1"; }

: > "$out/spread.txt"
for k in $(seq 0 $((SEEDS - 1))); do
  python3 "$here/scripts/perturb_rtl.py" "$out/net.v" "$out/p$k.v" $k
  $YOSYS -q -p "read_verilog $out/p$k.v; synth_ice40 -device u -top $top; \
    tee -q -o $out/p$k.stat stat" > "$out/p$k.log" 2>&1
  echo "$(lut "$out/p$k.stat") $(ff "$out/p$k.stat") $(carry "$out/p$k.stat")" >> "$out/spread.txt"
  rm -f "$out/p$k.v" "$out/p$k.log" "$out/p$k.stat"
done
# FF and CARRY must not move with statement order.
[ "$(cut -d' ' -f2,3 "$out/spread.txt" | sort -u | wc -l)" = 1 ] \
  || { echo "FF/CARRY differ across seeds: see $out/spread.txt" >&2; exit 1; }
med=$(cut -d' ' -f1 "$out/spread.txt" | sort -n | awk '{a[NR] = $1}
  END {printf "%d [%d, %d]", a[int((NR + 1) / 2)], a[1], a[NR]}')

if [ $config = 8 ]; then
  $NEXTPNR --up5k --package sg48 --freq 12 --pcf-allow-unconstrained \
    --json "$out/ice40.json" --asc "$out/ice40.asc" > "$out/pnr.log" 2>&1
fi

s=$out/ice40.stat
echo "== $rev $config generic:  gates $(gates "$out/generic.stat")  flops $(gff "$out/generic.stat")"
echo "== $rev $config iCE40:    LUT4 median $med over $SEEDS seeds;" \
     "RTL run $(lut $s);  FF $(ff $s)  CARRY $(carry $s)  BRAM $(bram $s)"
if [ $config = 8 ]; then
  echo "== $rev $config up5k place-and-route:" \
       "$(grep -E 'ICESTORM_LC:' "$out/pnr.log" | tail -1 | sed 's/^Info: *//')"
  echo "   $(grep -E 'Max frequency' "$out/pnr.log" | tail -1 | sed 's/^Info: *//')"
fi
# Per module instance (hierarchy kept): each module's own cells, not its
# submodules', one line per instance in the design hierarchy.
echo "== $rev $config per module instance (hierarchy kept, own cells):"
awk '
  function base(n) { sub(/^\$paramod(\$[0-9a-f]+)?\\/, "", n); sub(/\\.*/, "", n); return n }
  /^=== design hierarchy/ { h = 1; m = ""; next }
  /^=== / { m = base($2); next }
  !h && m != "" && $2 == "SB_LUT4" { l[m] = $1 }
  !h && m != "" && $2 == "SB_CARRY" { c[m] = $1 }
  !h && m != "" && $2 ~ /^SB_DFF/ { f[m] += $1 }
  h && /^ +[0-9]+ +[ ]*[$a-z]/ && !/wires|bits|ports|cells|memor|process/ {
    ind = match($0, /[^ 0-9]/) - 9; n = base($2)
    { printf "   %*s%-*s LUT4 %4d  FF %4d  CARRY %3d\n",
      ind, "", 22 - ind, n, l[n], f[n], c[n] } }
  h && /wires/ { exit }
' "$out/ice40_nf.stat"

# The shim is wiring only: with hierarchy kept, oc_uart16550_wb32's own
# cells must be none. (Flattened, the shim and the bare core differ by a few
# LUT4 either way: ABC and opt order noise, inside the seed spread.)
if [ $config = shim ]; then
  own=$(awk '/^=== oc_uart16550_wb32 ===/ {m = 1; next} /^=== / {m = 0}
    m && NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^SB_/ {s += $1} END {print s + 0}' "$out/ice40_nf.stat")
  echo "== shim own cells (hierarchy kept): $own"
  [ "$own" = 0 ] || { echo "the shim adds cells" >&2; exit 1; }
fi

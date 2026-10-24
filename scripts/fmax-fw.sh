#!/usr/bin/env bash
# Fmax and LUT depth of one fw-uart16550 netlist, for comparing variants:
# the fw half of scripts/pnr-compare.sh plus scripts/lut_depth.py.
#
#   scripts/fmax-fw.sh outdir [netlist]     (default: the current `dfm run lowered`)
#   SEEDS=5 scripts/fmax-fw.sh ...
# Writes outdir/fw.json, fw_pnr<seed>.log, depth.txt; prints one summary line.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=$1
net=${2:-$here/rundir/org.fwip.uart16550.lowered/fw_uart16550_top.v}
mkdir -p "$out"
cp "$net" "$out/fw_uart16550_top.v"
[ -f "$here/rundir/pnr/wrap_fw_uart16550_top.v" ] || { echo "run scripts/pnr-compare.sh once first" >&2; exit 1; }
yosys -q -p "read_verilog $out/fw_uart16550_top.v $here/rundir/pnr/wrap_fw_uart16550_top.v; \
    synth_ice40 -device u -top pnr_top -json $out/fw.json; tee -q -o $out/fw.stat stat" > "$out/fw_syn.log" 2>&1
python3 "$here/scripts/lut_depth.py" "$out/fw.json" --min 6 --paths 20 --trace > "$out/depth.txt"
f=""
for s in $(seq 1 "${SEEDS:-3}"); do
    nextpnr-ice40 --up5k --package sg48 --freq "${FREQ:-12}" --pcf-allow-unconstrained --timing-allow-fail --seed "$s" \
        --json "$out/fw.json" > "$out/fw_pnr$s.log" 2>&1
    f="$f $(grep -h 'Max frequency for clock' "$out/fw_pnr$s.log" | tail -1 | awk '{print $(NF-5)}')"
done
lut=$(grep -E 'SB_LUT4' "$out/fw.stat" | awk '{print $1}')
ff=$(grep -E 'SB_DFF' "$out/fw.stat" | awk '{s+=$1} END {print s+0}')
hist=$(awk '/histogram/{p=1;next} /^$/{p=0} p{printf "%s%s", $1, $2" "}' "$out/depth.txt")
echo "$(basename "$out"): LUT4 $lut FF $ff; Fmax$f; depth $hist"

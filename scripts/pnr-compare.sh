#!/usr/bin/env bash
# Fmax of U2B0 (behind the 32-bit shim) and of fw-uart16550 (the lowered
# netlist) on the iCEBreaker's UP5K-SG48, each in the same pin wrapper: the
# shim's pins with an 8-bit data bus (bits 31:8 are 0 on both designs), so
# they fit the package. nextpnr-ice40 at 12 MHz, $SEEDS (3) seeds each.
#
#   scripts/pnr-compare.sh [outdir]     (default rundir/pnr)
# Needs the ivpm tools on PATH (direnv) and a run of `dfm run lowered`.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$here/rundir/pnr}
mkdir -p "$out"
R=$here/packages/oc-uart16550/rtl/verilog
for d in oc_uart16550_wb32 fw_uart16550_top; do
    cat > "$out/wrap_$d.v" <<EOV
module pnr_top (
    input clk, input rst, input [4:2] adr, input [7:0] dat_i, output [7:0] dat_o,
    input we, input stb, input cyc, output ack, output err, output int_o,
    input srx, output stx, output rts, input cts, output dtr, input dsr, input ri, input dcd);
    wire [31:0] dat_o_w;
    assign dat_o = dat_o_w[7:0];
    $d u_dut (.wb_clk_i(clk), .wb_rst_i(rst), .wb_adr_i({adr, 2'b00}), .wb_dat_i({24'h0, dat_i}),
        .wb_dat_o(dat_o_w), .wb_sel_i(4'hF), .wb_we_i(we), .wb_stb_i(stb), .wb_cyc_i(cyc),
        .wb_ack_o(ack), .wb_err_o(err), .int_o(int_o), .srx_pad_i(srx), .stx_pad_o(stx),
        .rts_pad_o(rts), .cts_pad_i(cts), .dtr_pad_o(dtr), .dsr_pad_i(dsr), .ri_pad_i(ri), .dcd_pad_i(dcd));
endmodule
EOV
done
yosys -q -p "read_verilog -DDATA_BUS_WIDTH_8 -I$R $R/raminfr.v $R/uart_receiver.v $R/uart_regs.v \
    $R/uart_rfifo.v $R/uart_sync_flops.v $R/uart_tfifo.v $R/uart_top.v $R/uart_transmitter.v $R/uart_wb.v; \
    read_verilog -sv -DDATA_BUS_WIDTH_8 $here/src/ref/oc_uart16550_wb32.sv; read_verilog $out/wrap_oc_uart16550_wb32.v; \
    synth_ice40 -device u -top pnr_top -json $out/ref.json" > "$out/ref_syn.log" 2>&1
yosys -q -p "read_verilog $here/rundir/org.fwip.uart16550.lowered/fw_uart16550_top.v $out/wrap_fw_uart16550_top.v; \
    synth_ice40 -device u -top pnr_top -json $out/fw.json" > "$out/fw_syn.log" 2>&1
for d in ref fw; do
    f=""
    for s in $(seq 1 "${SEEDS:-3}"); do
        nextpnr-ice40 --up5k --package sg48 --freq 12 --pcf-allow-unconstrained --seed "$s" \
            --json "$out/$d.json" --asc "$out/$d.asc" > "$out/${d}_pnr$s.log" 2>&1
        f="$f $(grep -h 'Max frequency for clock' "$out/${d}_pnr$s.log" | tail -1 | awk '{print $(NF-5)}')"
    done
    echo "$d: Fmax (MHz) by seed:$f; $(grep -h 'ICESTORM_LC:' "$out/${d}_pnr1.log" | tail -1 | awk '{print $3, $4}') LCs"
done

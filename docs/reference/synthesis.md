# Synthesis baseline

## Published results

The PDF (rev 0.6) gives no synthesis results, and the repository has none:
`syn/` holds only empty placeholder directories (`syn/bin`, `log`, `out`,
`run`, `src`, each with a `.keepme`).

The only figure upstream is in `doc/CHANGES.txt` (2002-07-22): making the
FIFOs inferable RAM (`raminfr`), so that they map to distributed RAM on
Xilinx, "saves about 1/3 of the Slice count". No absolute numbers are
given.

## Repository synthesis setup

None at U2B0. `fw-uart16550` measures the reference with
`scripts/synth-baseline.sh` (Yosys and nextpnr from ivpm), as fw-i2c does.

The memory mapping matters for the comparison. `raminfr` has a
synchronous write and an asynchronous read. iCE40 has no LUT RAM, and its
block RAM reads synchronously, so on iCE40 the two 16×8 arrays become 256
flops plus read muxes, and the 48 RX error flags are flops anyway (plan §2,
decision D4).

## Measurements

Measured 2026-10-21 with `scripts/synth-baseline.sh <oc-uart16550> <rev>
<config>`, using Yosys 0.69 and nextpnr 0.11.1 (fw-i2c's ivpm packages).
Area is out of context (all ports on pins).

- **Generic:** `synth -flatten`, then `abc -g` to 2-input gates and MUX.
- **iCE40:** `synth_ice40 -device u`, flattened. ABC's result depends on
  statement order, so LUT4 is the median [range] of 11 runs of the same
  design with its `assign`s reordered (`scripts/perturb_rtl.py`). Flop and
  carry counts do not move.
- **P&R:** `nextpnr-ice40 --up5k --package sg48 --freq 12`, one seed, 8-bit
  core only. The other two configurations need more pins than SG48 has.

| Config | Top | Generic gates | Flops | SB_LUT4 | SB_CARRY | BRAM |
|---|---|---|---|---|---|---|
| `DATA_BUS_WIDTH_8` | `uart_top` | 1750 | 564 | 820 [817, 824] | 80 | 0 |
| `DATA_BUS_WIDTH_8` + shim | `oc_uart16550_wb32` | 1749 | 564 | 821 [817, 827] | 80 | 0 |
| default (32-bit, debug) | `uart_top` | 1947 | 606 | 911 [904, 919] | 80 | 0 |

The 8-bit core places in 1231 of 5280 logic cells (23%) and reaches
41.3 MHz, against the 12 MHz board clock. On this target, as for fw-i2c,
the comparison that matters is area.

The tags `u2b0` and `u2b0-fw1` give identical numbers in every row: the fw
patch set changes no area. With hierarchy kept, the shim's own cells are
zero. Its flattened median differs from the bare core by 1 LUT4, which is
inside the spread. The breakdown by module is in {doc}`architecture`.

The shim row is the form `fw-uart16550` compares against (`ref-rtl`). The
budget derived from it is in the plan (§6.2).

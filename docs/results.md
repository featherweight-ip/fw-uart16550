# Results

## First area: fw-uart16550 against U2B0 (2026-10-24)

The first lowerable fw-uart16550 ({doc}`design/fw-impl`), lowered with the
fw-i2c path (`dfm run lowered`) and synthesized with
`scripts/synth-lowered.sh`. U2B0 was re-measured with
`scripts/synth-baseline.sh ../oc-uart16550 u2b0-fw1 shim` on the same Yosys
(0.70; {doc}`reference/synthesis` has 0.69). Both: iCE40UP5K
(`synth_ice40 -device u`), flattened, out of context, the 8-bit core behind
the 32-bit shim, FIFOs in flops on both sides (D4 (a)). LUT4 is the median
[range] of 11 reordered runs.

| | SB_LUT4 | Flops | SB_CARRY | Generic gates |
|---|---|---|---|---|
| U2B0 (`ref-rtl`) | 826 [826, 826] | 564 | 80 | 1719 |
| fw-uart16550 (`lowered`) | **774** [766, 790] | **526** | 92 | 2154 |
| Difference | −52 (−6%) | −38 (−7%) | +12 | +435 |
| Budget (plan §6.2) | ≤ 903 | ≤ 620 | | |

Within budget, and below the reference in LUT4 and flops. The generic gate
count (2-input gates and MUX, technology-neutral) is 25% higher. That
cross-check disagrees with the iCE40 numbers and is not explained yet.

Checked before measuring: the shared tests (`smoke`, `regs`, `line`,
`status`, `irq`) pass on the lowered netlist (`rtl` view), on the class model
behind pins (`wb`) and on U2B0 (`ref`). A model mutation (no THRE mask on
the IIR read) is caught by `irq` alone.

### Where it goes

The lowering absorbs the kit cores into one flat module, so there is no
per-module breakdown like U2B0's. Two views:

**The library cores alone** (synthesized from their sources; inside the
design they share logic and are trimmed, so this is an estimate of the
library share):

| Core | LUT4 | FF | CARRY |
|---|---|---|---|
| `wb_target_xtor_core` | 8 | 3 | 0 |
| `uart_baud_xtor_core` | 57 | 16 | 28 |
| `uart_tx_xtor_core` | 99 | 25 | 12 |
| `uart_rx_xtor_core` | 77 | 44 | 10 |
| `fw_uart16550_sync` | 0 | 2 | 0 |
| Sum | 241 | 90 | 50 |

**LUT4 by the register each feeds** (`rundir/synth-lowered/classes.txt`,
the largest): the WISHBONE read data 183 (the register read mux and the RX
FIFO head), the TX request data 109 (the TX FIFO head), `int_o` 52 (IIR as
a relation), the baud counter 46, RX and TX FIFO writes 39 and 36.

FIFO storage is 304 flops on both sides: 128 + 128 data plus U2B0's 48
error flags, against fw's 128 + 176 (11-bit RX entries).

### What it took

From the first lowered netlist to this one:

| Change | LUT4 (median) |
|---|---|
| First netlist (after the lowering fix below) | 1203 |
| `fw_fifo`: read and write through constant indices (an AND-OR read mux and per-entry write enables) instead of a run-time index into the packed storage, which lowers to a shifter over all of it | 970 |
| tx process: one clock after each character, so the lowering reads the TX FIFO head in one state, not two | 774 |

### Lowering defects found

- **Partial nonblocking writes** (fixed, fw-hdl `translate.py`). Several
  nonblocking writes to parts of one variable in a clock (struct members,
  bits, part selects) each rebuilt the vector from the old value, so only
  the last survived. In the absorbed kit rx core
  (`rsp_q.data <= …; rsp_q.parity_err <= …; …`) that dropped the received
  data and PE, FE and BI: `rtl-smoke` read every character as 0x00, and
  seqcorr then proved the RX FIFO constant. Each partial nonblocking write
  now merges into the pending value of the clock.
- **A one-shot flag the lowering treats as constant** (worked around in the
  model). A flag set on a process's first pass (`msr_started`) is already
  set where the process first blocks, which is its reset state. The
  optimizer then removes it as a constant but leaves a reader: "internal:
  root_dut_msr_started is read but no longer defined". The model no longer
  uses one.

### Not measured yet

- P&R and Fmax (the shim's pins do not fit the SG48 package; U2B0's 41 MHz
  is for the 8-bit core alone).
- The FIFOs in block RAM (D4 (b)).
- The attribution by function of design §7.2 (bus and registers, TX, RX,
  storage): it needs the netlist's hierarchy or a per-signal mapping.

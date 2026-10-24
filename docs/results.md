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

| | SB_LUT4 | Flops | SB_CARRY | Generic gates | Fmax (MHz) |
|---|---|---|---|---|---|
| U2B0 (`ref-rtl`) | 826 [826, 826] | 564 | 80 | 1719 | 40.8, 39.7, 43.5 |
| fw-uart16550, first pass | 774 [766, 790] | 526 | 92 | 2154 | 29.8, 33.0, 32.3 |
| **fw-uart16550, now** | **736** [729, 750] | **529** | **80** | 2132 | 35.9, 35.3, 35.1 |
| Now − U2B0 | −90 (−11%) | −35 (−6%) | 0 | +413 (+24%) | −13% |
| Budget (plan §6.2) | ≤ 903 | ≤ 620 | | | ≥ 37 |

The first pass is the commit d560ce7 state; "now" includes the second
round below. Fmax is from `scripts/pnr-compare.sh` (see Timing).

Within budget, and below the reference in LUT4 and flops. Fmax is still
short of the target. The generic gate count is 24% higher: that is the
form of the FIFO read mux, not extra logic (see "The generic gate count"
below).

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

### Second round (2026-10-24)

Each change measured on its own, against the one before (LUT4 median of 5,
Fmax over 3 seeds):

| Change | LUT4 | FF | CARRY | Fmax (MHz) | Kept |
|---|---|---|---|---|---|
| Start | 774 | 526 | 92 | 29.8–33.0 | |
| O1: the timeout reload value in a register, set on LCR and DL writes | 776 | 530 | 91 | 29.5–30.6 | no (see below) |
| O2: LSR and IIR registered by the status process; the host's reads (and their side effects) use the registers, as U2B0 does | 761 | 541 | 94 | 31.0–32.9 | yes |
| O3: kit baud core reloads with the divisor and ticks at 1, no subtractor (fw-proto-uart 95b4ff9; proven equivalent to the old core) | 768 | 541 | 80 | 32.6–34.0 | yes |
| O4: the timeout's reload trigger from bit 0 of each RX pointer instead of a copy of both | 761 | 533 | 81 | 32.7–33.9 | yes |
| O1 taken out again | 745 | 529 | 81 | 31.0–33.1 | |
| All, 11 seeds | 736 | 529 | 80 | 35.1–35.9 | |

O1 was first inlined at two call sites (+21 LUT4); with one call site it was
area-neutral, and with O2–O4 in, taking it out saved 16 LUT4 and 4 FF for
about 1 MHz, within the seed spread. Its one-call-site refactor of
`host_access()` is kept.

The critical path after the first pass was the timeout reload (FIFO count
→ `toc_value()` → the counter). O1 moved it to the host's IIR read
(RX head error → `head_ack` → `thre_masked`), which O2 removed. Since
then the worst path differs by seed: the kit tx core's counter, the
status process, or the host's TX FIFO write straight from `wb_cyc_i`.
Routing is about two thirds of the delay. U2B0 registers the bus in
`uart_wb` (27 FF) before decoding; the fw WISHBONE target core does not,
so a request is decoded and acted on in the clock it arrives.

### The generic gate count

The generic flow counts 2-input gates and MUX. By type, against U2B0 (one
run each):

| | AND | MUX | NAND | NOR | OR | NOT | XOR+XNOR | Total |
|---|---|---|---|---|---|---|---|---|
| U2B0 | 514 | 286 | 286 | 153 | 285 | 135 | 60 | 1719 |
| fw-uart16550 | 858 | 84 | 313 | 333 | 209 | 134 | 113 | 2044 |

fw has 202 fewer MUX and 344 more AND. The difference is `fw_fifo`'s read: an AND-OR over
decoded indices costs about three gates per entry and bit, where U2B0's
memory read is a tree of MUX, one gate each. On iCE40 both are LUT4s at
about the same count. With `fw_fifo`'s read rewritten as a mux tree on the
index bits:

| `fw_fifo` read | LUT4 (median of 5) | Fmax (MHz) | Generic gates (median) |
|---|---|---|---|
| AND-OR (kept) | 736 | 35.1–35.9 | 2132 (+24%) |
| Mux tree | 749 | 33.9–34.5 | 1780 (+3.6%) |

So the 24% is the read mux's form: with a mux tree fw is within 4% of U2B0
on the generic count (its as-written run, 1670, is below it). The AND-OR
form is kept because the target is iCE40, where it is 13 LUT4 smaller and
about 1.5 MHz faster. A library with MUX2 cells (an ASIC) would favour the
mux tree; `fw_fifo` could offer both.

The lowering's output order varies between runs of the same source (the
as-written iCE40 run was 740, then 737 LUT4), so single runs differ by a
few LUT4 even before the reordered seeds.

### Timing

`scripts/pnr-compare.sh`: both designs in one pin wrapper (the shim's pins
with an 8-bit data bus; bits 31:8 are 0 on both), nextpnr-ice40 on the
UP5K-SG48 at 12 MHz, 3 seeds.

| | Fmax (MHz), seeds 1–3 | Logic cells |
|---|---|---|
| U2B0 | 40.8, 39.7, 43.5 | 1240 / 5280 |
| fw-uart16550, first pass | 29.8, 33.0, 32.3 | 1220 / 5280 |
| fw-uart16550, now | 35.9, 35.3, 35.1 | 1181 / 5280 |

Both pass the 12 MHz board clock; fw-uart16550 is still short of the
plan's target (≥ 0.9 × 41 MHz). For the first pass the critical path was
the timeout reload; for the second round, see above.

`obsmerge=1` (register merging modulo observability) gains nothing:
784 LUT4 on one run, against 776 without it.

### Not measured yet

- The FIFOs in block RAM (D4 (b)).
- The attribution by function of design §7.2 (bus and registers, TX, RX,
  storage): it needs the netlist's hierarchy or a per-signal mapping.

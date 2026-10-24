# Results

## Code size (2026-10-24)

`scripts/loc.py` counts a line with any code on it as code and a line with
only a comment as comment. U2B0's comment count includes the LGPL header
on every file (about 60 lines each).

| | Files | Code | Comment | Total |
|---|---|---|---|---|
| U2B0 core: the files synthesized (`rtl/verilog`, no debug interface) | 11 | 1611 | 1574 | 3464 |
| U2B0's 32-bit shim (`src/ref`, for the comparison only) | 1 | 50 | 29 | 86 |
| **fw-uart16550**: register map (RDL) | 1 | 26 | 11 | 43 |
| **fw-uart16550**: class model (`src/spl`) | 6 | 274 | 116 | 423 |
| **fw-uart16550**: pin top (`src/spl-rtl`) | 4 | 258 | 47 | 334 |
| **fw-uart16550 total** | 11 | **558** | 174 | 800 |
| Library: fw-proto-uart, the parts used (baud, tx and rx cores; APIs) | 7 | 348 | 151 | 551 |
| Library: fw-proto-wb, the parts used (target core, interface, bridge) | 5 | 181 | 83 | 301 |
| Library: `fw_fifo` | 1 | 34 | 34 | 77 |
| Library: fw-hdl kernel and std, whole | 44 | 1401 | 1073 | 2781 |
| Generated: register packages (peakrdl-fw-hdl) | 2 | 214 | 31 | 281 |
| Generated: lowered netlist | 1 | 3604 | 30 | 3634 |

The design's own code is a third of U2B0's (558 lines against 1611). With
the library parts it uses, the UART and WISHBONE kits and `fw_fifo`, it is
1121, 30% less, and those parts are meant to be shared with other designs.
The fw-hdl kernel plays the part of a language runtime and is not counted against either. The behaviour itself
(registers and their side effects, both FIFOs, LSR, IIR, MSR, the timeout)
is `fw_uart16550.svh`, 222 lines; in U2B0 the same is `uart_regs.v`,
`uart_rfifo.v`, `uart_tfifo.v`, `raminfr.v` and `uart_wb.v`, 896 lines.
The pin top is mostly wiring: the kit cores, the transactor interface and
the bridges between it and the model.

Not like for like: U2B0's code carries the 8/32-bit bus option and the
debug interface (`UART_HAS_DEBUG`), not all of which is compiled here. fw
lacks the baud restart on a DL write (U24) and gets the serial framing
from the kit cores.

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
| fw-uart16550, second round | 736 [729, 750] | 529 | 80 | 2132 | 35.9, 35.3, 35.1 |
| **fw-uart16550, now** | **760** [756, 772] | **553** | **67** | 2145 | 41.5, 40.5, 41.7, 39.5, 40.5, 40.5 |
| Now − U2B0 | −66 (−8%) | −11 (−2%) | −13 | +426 (+25%) | about −2% (medians 40.5, 41.0) |
| Budget (plan §6.2) | ≤ 903 | ≤ 620 | | | ≥ 37 |

The first pass is the commit d560ce7 state; "now" includes the second and
third rounds below. Fmax is from `scripts/pnr-compare.sh` (see Timing); the
third round uses 6 seeds (U2B0 on 6: 40.8, 39.7, 43.5, 42.1, 39.5, 41.4).

Within budget, below the reference in LUT4 and flops, and at the Fmax
target on every seed. The generic gate count is 24% higher: that is the
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

### Third round: timing (2026-10-24)

**Method.** `scripts/lut_depth.py` counts LUT4 levels to each flop input
in the mapped netlist; `scripts/fmax-fw.sh` places one netlist on 6 seeds.
Seed-to-seed spread is 2–3 MHz, so a change is judged on its 6 seeds and
its depth histogram, not one run. At the start (re-measured, 755 LUT4,
32.4–33.9 MHz) fw had 373 endpoints at 7 or more LUT levels and 3 at 9;
U2B0 has 4 at 7 and none deeper. The kit cores alone are 4–6 levels deep:
the depth came from where the model and the cores meet.

| Change | LUT4 | FF | Fmax, 6 seeds (MHz) | Depth ≥ 7 |
|---|---|---|---|---|
| Start | 755 | 529 | 32.4–33.9 | 373 |
| T1 `fw_fifo.full()` by pointer compare, not `count() == DEPTH` (every push checked it through a subtractor) | 743 | 529 | 34.8–37.2 | 67 |
| T2 kit baud core: `tick` registered (its consumers started from the counter's and the divisor's zero tests) | 733 | 530 | 34.2–37.1 | 26 |
| T3 LSR[7] by a toggle pair per RX entry, not counts of bad pushes and pops (a pop read the head's error bits through the 16:1 read mux) | 773 | 552 | 37.2–39.1 | 19 |
| T4 IIR from last clock's state, computed first in the status loop (see below) | 768 | 553 | 36.7–41.7 | 0 |
| T5 `fw_fifo.empty()` as an XOR reduction, and RX trigger level 1 as `!empty()` (see below) | 765 | 553 | 38.6–41.7 | 0 |

LUT4 here is the 8-bit pin wrapper's single run; the table at the top has
the 11-run median.

**IIR a clock behind.** The head's error bits (a read mux), the RX count
(a subtractor) and the timeout (its reload) were each followed by IIR's
priority in the same clock. IIR is now computed from registers: RLS from
`lsr_q`, RDA from a registered trigger level, TI from `to_cnt` and
`lsr_q`'s DR, MS from the deltas. Each term's inputs lag together, so
none glitches. THRE keeps `txf.empty()`: it pairs with `thre_masked`,
which a THR write clears in the clock it pushes, and a lagged THRE would
pulse `int_o`. The lag is invisible to the host: the kit's WISHBONE target
accepts a request at most every third clock (WATCH, RESP, DRAIN), so the
next access after a change reads IIR registered two clocks after it. U2B0
also builds IIR from its registered LSR. A second clock of lag would not
be invisible.

**What abc9 did with `empty()`.** After T4 every seed's critical path was
the host's pop: the RX pointers, a 5-bit carry chain, a carry compare, the
pop enables. `synth_ice40` maps with `abc9`, which sees through the carry
cells and merges nodes with the same function. `count() >= 1` (the FCR = 0
trigger) is the same function as `!empty()`, so abc9 built every RX
`empty()` from the subtractor and its compare. This is legal and abc9 does
it on purpose: its delay model has a carry hop at about 0.1–0.3 ns and a
flat 250 ps per wire (`-W 250`), while on the placed UP5K the routing into
and out of a carry chain costs 1.7–3.5 ns. So it is a model mismatch, not
a bug. Writing level 1 as `!empty()` removes the equivalent node; the XOR
form of `empty()` also keeps Yosys's `alumacc` from merging it with the
subtraction.

**The placer.** nextpnr places timing-driven by default, and that is worth
2–3 MHz here (fw seeds 1–3: 41.5, 40.5, 41.7; with `--no-tmdriv` 38.0,
39.3, 37.3). The target frequency makes no difference: placed for 40 MHz
instead of 12, both designs give the same Fmax on every seed. The placer
weights paths by slack relative to the worst path, so a loose constraint
does not make it lazy.

**Verified.** The shared tests on `wb`, `rtl` and `ref`, and U2B0's
ref-only tests, pass (23 cases). A mutation where a pop does not clear its
entry's LSR[7] flag fails `status`. The kit's smoke, lint-rtl, fv-quick and
full fv pass with the registered tick.

**Cost.** +24 LUT4 and +24 FF on the 11-run medians against the second
round, nearly all T3: 32 flags against two 5-bit counts, with a LUT per
flag on each side. CARRY is down 13 (T1). fw is still 8% below U2B0 in
LUT4 and 2% in flops.

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
| fw-uart16550, second round | 35.9, 35.3, 35.1 | 1181 / 5280 |
| fw-uart16550, now | 41.5, 40.5, 41.7, 39.5, 40.5, 40.5 | 1204 / 5280 |

U2B0 on seeds 4–6: 42.1, 39.5, 41.4. Both pass the 12 MHz board clock, and
fw-uart16550 now meets the plan's target (≥ 0.9 × 41 MHz) on every seed.
For the first pass the critical path was the timeout reload; for the
later rounds, see above.

`obsmerge=1` (register merging modulo observability) gains nothing:
784 LUT4 on one run, against 776 without it.

### Not measured yet

- The FIFOs in block RAM (D4 (b)).
- The attribution by function of design §7.2 (bus and registers, TX, RX,
  storage): it needs the netlist's hierarchy or a per-signal mapping.

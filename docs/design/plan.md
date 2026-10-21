# fw-uart16550: plan

A fresh session should be able to pick up from this file alone. Update the
status column in §9 as each step finishes.

fw-uart16550 re-implements the freecores `uart16550` core with fw-hdl, verifies
it against the original, lowers it to RTL with the fw-i2c synthesis path,
and compares area. It is the second design on that path. fw-i2c was chosen
to get the path working. fw-uart16550 is chosen to **exercise the parts of
synthesis that fw-i2c did not** (fw-i2c synthesis-plan §8.3, §0.8).

Written 2026-10-20. Nothing below is decided until it is marked
**Decision**.

## 1. What this design adds to the synthesis study

fw-i2c had one controlling process with a single-transactor core running in
lock step with it. It had no storage beyond registers, and almost no data
path. Most of its area gap came from copies at transactor boundaries
(synthesis-plan §0.8). The 16550 differs in six ways. Each one is a
question for the synthesis path:

| # | What the 16550 has | Question for synthesis | fw-i2c had |
|---|---|---|---|
| Q1 | **Independent concurrent processes**: TX and RX run at the same time, unsynchronized, and meet only at the register file and the interrupt logic | Do copy merging and functional dependency (the tight view, §0.8–0.9) still pay off when the processes are not in lock step? What does the product state space cost? | one sequencer in lock step with one core |
| Q2 | **Storage**: two 16-deep FIFOs (TX 8 bits, RX 8 + 3 error bits), with count, flush and trigger level | How does an array lower: as flops with a read mux, as an inferred memory, or as a kept library leaf? FF vs block RAM? | none |
| Q3 | **Counters and a small data path**: a 16-bit baud divider, bit and sample counters, the 10-bit timeout counter, THRE hold-off, parity | Carry chains, counter sharing (TX and RX tick from one baud enable), width inference, lifetime sharing (§0.8 4.3) | an 8-bit shift and a prescaler |
| Q4 | **Interrupt priority**: five sources, a pending latch per source, IIR encoding, clear-on-read side effects | The "status is a relation, not a copy" style (model-style-plan B) at a larger scale; side-effect reads in the register block | a single IRQ flag |
| Q5 | **Undefined behaviour in the spec**: LCR or divisor written mid-character, FIFO reset during a transfer, reading RBR when empty | The *assumed* view (synthesis-plan §0.8 (b)): proved equivalent under environment assumptions, so it can go below the reference | not tried |
| Q6 | **Elaboration-time configuration**: 8-bit vs 32-bit bus, endianness, optional debug registers | One model, several lowered netlists; constant propagation from configuration (synthesis-plan E3) | one configuration |

Smaller items:

- Asynchronous inputs: a 2-flop synchronizer on `srx`, kept as leaf RTL
  (synthesis-plan §0 stage 3).
- Modem status lines: edge detection on pins (delta bits).
- The reference's Wishbone port registers its inputs and acks two cycles
  later. The fw-proto-wb target does not, so the comparison includes a
  different bus timing (§5, allowed differences).

**Goal.** As for fw-i2c (story.md): the model stays abstract, simulates
faster than the RTL, and lowers to RTL within about 10% of the reference on
lowered logic. Library cost is reported separately (fw-i2c synthesis-plan
§6, decision D1 (c)).

## 2. Reference

**Source.** `github.com/freecores/uart16550`. It has 97 commits, from
2001-05-12 to 2004-11-22, by Jacob Gorban and Igor Mohor (also Tadej
Markovic for the bench). The mirror came through OpenCores SVN
(`refs/remotes/svn/trunk`), but the git history carries no SVN revision
numbers, so the pin is named by commit. Upstream tags: `initial`, `rel_1`
… `rel_4`, `asyst_2`, `asyst_3`, `NewFormat`.

**Decision (D1): pin `2b0ad80`** (master HEAD, 2004-11-22, Igor Mohor). It
is the last RTL change: tag `rel_4` plus one fix (the timeout interrupt
needs a non-empty RX FIFO). It is what people use as "uart16550". This
document calls it **U2B0**.

The old `featherweight-ip/fwuart-16550` (2022) holds a vendored copy of the
same RTL with a mkdv/cocotb flow that no longer passes. Do not build on it.
The spec PDF (rev 0.6) is in the fork's `doc/`.

**RTL.** About 3.6k lines in 10 files:

- `uart_top`
  - `uart_wb`
  - `uart_regs`
    - `uart_transmitter` → `uart_tfifo` → `raminfr`
    - `uart_sync_flops`
    - `uart_receiver` → `uart_rfifo` → `raminfr`
  - `uart_debug_if` (32-bit mode only)

Reset is asynchronous and active high, with one clock (`wb_clk_i`).

**Defines.**

- `DATA_BUS_WIDTH_8`: off by default, giving a 32-bit bus with a 5-bit
  address, byte lanes selected by `wb_sel`, and the debug interface.
- `LITLE_ENDIAN` (sic): byte lane order.
- `UART_HAS_BAUDRATE_OUTPUT`.
- The FIFO is 16 deep.

**Register map** (byte address):

| Addr | Read | Write | DLAB = 1 |
|---|---|---|---|
| 0 | RBR (pops RX FIFO) | THR | DLL |
| 1 | IER | IER | DLM |
| 2 | IIR (`{4'b1100, iir[3:0]}`) | FCR | (unaffected) |
| 3 | LCR | LCR | |
| 4 | reads 0 | MCR | |
| 5 | LSR (read clears error bits) | | |
| 6 | MSR (read clears deltas) | | |
| 7 | SCR | SCR | |
| 8, 12 | debug words (32-bit only) | | |

**Quirks to confirm by simulation** (as fw-i2c D1–D10 were; list goes in
`docs/reference/deviations.md`):

| ID | Quirk |
|---|---|
| U1 | MCR is write-only and reads 0. |
| U2 | SCR exists, though spec rev 0.6 says it was removed. |
| U3 | FIFOs are always on. FCR[0] and DMA mode are ignored, and there is no 16450 mode. |
| U4 | RX samples once, mid-bit (count 7 of 16), with no majority vote. |
| U5 | On overrun the incoming character is dropped. |
| U6 | THRE is held off about one character time after a THR write while THRE was set (`block_cnt`). |
| U7 | The RDA interrupt uses the level, not a latch. Other sources latch on a rising edge. |
| U8 | Loopback still drives RTS/DTR to the pads. There are no OUT1/OUT2 pins. |
| U9 | Modem inputs are not synchronized. |
| U10 | In 32-bit mode, a non-one-hot `wb_sel` reads 0; `4'b1111` reads the debug word. A write with `4'b1111` goes to byte 0, so the upstream bench (which writes with `sel = 4'hF`) puts its LCR write into THR at `2b0ad80`. |
| U11 | The shipped `sim/rtl_sim/log` records "Bit 5 of LSR register not '1'" (THRE). **Re-run 2026-10-21** (`scripts/upstream-bench.sh`, Icarus, two bench-only `#0` race workarounds): with `DATA_BUS_WIDTH_8` it reproduces the shipped report exactly, on `u2b0` and `u2b0-fw1` alike. Likely a bench bug, not RTL: the bench device's `rx_clk_cnt_en` starts as x, so its bit counter runs from t≈0 instead of from the start bit (1.23 ms), and it expects THRE 1.23 ms before the RTL raises it (`block_cnt` = 143 at LCR = 0x03). Confirm on the `ref` view (step 4). In the default 32-bit config the bench fails at initialization instead; see U10. |
| U12 | Break: a zero character with BI is pushed after one character time low. |
| U13–U26 | Found by reading the RTL in step 0; listed with evidence in `docs/reference/deviations.md`. The ones that shape later steps: **U13** an access whose `stb` rises in the clock right after the previous ack is acked but not performed (`uart_wb.v` `wbstate`/`wre`), so the bench's WISHBONE master must leave an idle clock between accesses (fwvip-wb, step 4); **U14** on overrun the RAM write still happens and overwrites the oldest entry (U5 holds for count and flags only); U15 the same in the TX FIFO; U16–U21 FIFO/LSR/RDA corner cases; U24 a DLM write does not restart the divider. |

**Baseline area** (Yosys 0.69, `synth_ice40 -device u`, flattened;
`scripts/synth-baseline.sh`, LUT4 as the median [range] of 11 reordered
runs; measured 2026-10-21; `u2b0` and `u2b0-fw1` give identical numbers in
every configuration):

| Config | LUT4 | FF | CARRY | BRAM |
|---|---|---|---|---|
| default (32-bit, debug), top `uart_top` | 911 [904, 919] | 606 | 80 | 0 |
| `DATA_BUS_WIDTH_8`, top `uart_top` | 820 [817, 824] | 564 | 80 | 0 |
| `DATA_BUS_WIDTH_8` + shim (`ref-rtl`) | 821 [817, 827] | 564 | 80 | 0 |

The shim's own cells are zero (hierarchy kept); the 1 LUT4 between the last
two rows is ABC noise. The 8-bit core places on the UP5K-SG48 in 1231 of
5280 logic cells (23%) and reaches 41.3 MHz (one seed; the board clock is
12 MHz). Per module, hierarchy kept (own cells; `raminfr` twice):

| Module | LUT4 | FF | CARRY |
|---|---|---|---|
| `uart_wb` (8-bit) | 5 | 27 | 0 |
| `uart_regs` (registers, divider, IIR, timeout, modem) | 218 | 118 | 39 |
| `uart_sync_flops` | 2 | 2 | 0 |
| `uart_transmitter` | 52 | 22 | 4 |
| `uart_tfifo` (control) | 29 | 14 | 10 |
| `uart_receiver` | 129 | 54 | 17 |
| `uart_rfifo` (control + 16×3 error bits) | 139 | 62 | 10 |
| `raminfr` ×2 (16×8 storage + async read mux) | 2 × 140 | 2 × 128 | 0 |

In the 32-bit configuration `uart_wb` is 69 LUT4 / 79 FF, `uart_regs` 223
LUT4, and `uart_debug_if` adds 59 LUT4.

About 300 of the FFs are FIFO storage:

- 256 `SB_DFFE` hold the two 16×8 `raminfr` arrays.
- 48 hold the RX error bits.

`raminfr` reads asynchronously, so it cannot map to iCE40 block RAM, and
iCE40 has no LUT RAM. **This shapes the comparison** (D4 in §8).

### 2.1 Integration of the reference (decided 2026-10-20)

As `oc-i2c` is integrated into fw-i2c, with two differences: the 16550 has
read side effects, and its configuration is by `` `define ``.

**Fork** `featherweight-ip/oc-uart16550` (local Forgejo,
`ssh://git@a9550.perch-char.ts.net:222/featherweight-ip/oc-uart16550.git`;
clone at `../oc-uart16550`).

- Tag `u2b0` = upstream `2b0ad80`, untouched.
- Branch `fw-u2b0`, tag `u2b0-fw1`: the `fw` patch set. No behaviour or
  area change:
  - remove the 348 `#1` and 5 `#Tp` delays (all on non-blocking
    assignments) and the unused `Tp` parameter of `uart_sync_flops`;
  - remove the `` `include "timescale.v" `` lines (9 files; `timescale.v`
    is kept, the bench uses it);
  - add an include guard to `uart_defines.v` (every file includes it).
- Everything else that lint finds is waived in `lint-waivers.yaml`, not
  patched: a logically identical rewrite can still move the Yosys area
  (fw-i2c WIDTHTRUNC waiver).
- Acceptance for every patch: Yosys `equiv_induct` against `u2b0` proves
  all points in both configurations, and the iCE40 cell counts are
  identical.

**Configuration** by `+define+`, never by editing `uart_defines.v`:
`DATA_BUS_WIDTH_8`, `LITLE_ENDIAN` and `UART_HAS_BAUDRATE_OUTPUT` are all
commented out there and only tested with `` `ifdef ``. A `` `define ``
applies to a whole compile, so each configuration is its own image and
fileset:

- `ref-rtl` (headline, D2): `DATA_BUS_WIDTH_8` plus the shim.
- `ref-rtl-32` (step 11): no defines; native 32-bit bus with debug; no
  shim.

**ivpm** (`dev` set): `oc-uart16550`, `tag: u2b0-fw1`, `deps: skip`.

**Shim** `src/ref/oc_uart16550_wb32.sv`: the 8-bit core on the fw-XXX bus
convention (32-bit data, one register per 32-bit word, as
`oc_i2c_wb32`):

- register *n* at byte address 4*n*; the core sees `wb_adr_i[4:2]`;
  reads return `{24'b0, dat8}`, writes take `wb_dat_i[7:0]`. This is Linux
  `8250_of` with `reg-shift = 2`, `reg-io-width = 4`.
- `wb_sel` is **ignored**, unlike `oc_i2c_wb32`. That shim turns a write
  without lane 0 into a read, which is safe only because i2c reads have no
  side effects. Here RBR, LSR, MSR and IIR reads change state, and gating
  the access would need an ack flop in the reference. A reg-io-width-4
  driver always sets all lanes. Recorded as a shim deviation; the fw model
  does the same.
- `wb_rst_i` (the core's asynchronous active-high reset), the core's own
  WISHBONE timing (registered inputs, ack two cycles later), `int_o`,
  `stx`/`srx` and the modem pins pass straight through.
- No logic. `synth-baseline.sh` checks it: the shim top costs 0 LUT4 over
  `uart_top`.

**Lint** top `oc_uart16550_wb32` with `DATA_BUS_WIDTH_8`, plus `uart_top`
in the 32-bit configuration.

**Upstream bench** (U11): run once in step 0 under Icarus, result recorded
in `docs/reference/deviations.md`. Not wired into dfm; the UVM `ref` view
replaces it.

## 3. Packages to develop

fw-uart16550 needs a UART protocol kit and a UART VIP, as fw-i2c needed
`fw-proto-i2c` and `fwvip-i2c`. Both follow the fw-i2c pair's conventions,
not the older templates.

### 3.1 `fw-proto-uart` (protocol kit): extend the existing repo

`featherweight-ip/fw-proto-uart` (last commit 2026-06-29) already has:

- **Roles.** `tx`, `rx` and `monitor`, each with the six kit elements:
  the API `interface class`, `_xtor_if`, `_xtor_core`, `_xtor`, and the
  bridge.
- **Configuration.** `uart_config_if.configure(divisor, word_bits,
  parity_en/even/stick, stop_bits)`, which maps onto LCR.
- **Status.** An LSR-aligned `{OE, BI, FE, PE}` status.
- **Cores.** Parameterized by `MAX_DATA_BITS`, `DIV_WIDTH` and
  `OVERSAMPLE`.
- **Checks.** An SVA checker, a back-to-back testbench, and a BMC/cover
  formal run.

It was generated from fw-proto-core's older `fw-proto-create` templates,
so the work is a restructure plus API work.

**Restructure** (to match `fw-proto-i2c`):

- ivpm dep-sets: `use` (fw-hdl only), `default-dev`, and
  `dev = uses default-dev`. Drop the fw-proto-core dependency.
- `flow.yaml` with `uses: project.dv`, the package map, and imports
  `hdlsim`, `hdllint`, `formal.sby`. Package `fw.proto.uart`.
- `src/flow.yaml` exports `files`, `class` and `xtor-core`. Rename
  `uart_<role>_xtor_bridge.svh` to `uart_<role>_bridge.svh`.
- `lint-rtl` passes with zero findings, using `lint-waivers.yaml` and a
  lint top.
- Roots `tests`, `smoke`, `fv-quick`, `fv` and `fv-cover`.
- `ci/run.sh` plus `.github` and `.forgejo` workflows. Push runs `smoke
  lint-rtl fv-quick`; nightly runs `tests lint-rtl fv fv-cover`.
- README, `tests/formal/PROPERTIES.md`, and a consumer skill
  `skills/fw-proto-uart` (as fw-proto-wb ships).

**API and core work** (driven by what the 16550 model and the VIP need).
The rule for ZU items (§6.1) applies here too: build each item when its
user reaches it. Step 2 does the restructure plus K4, K6 and the K9 tests
for them, which the `ref` view's confirmation tests (U5, U12, error bits)
need. K1, K2, K3, K5, K7 and K8 wait for the class model (step 7).

| ID | Item | Why |
|---|---|---|
| K1 | A runtime `configure()` on all roles, taking effect at the next character boundary | LCR/DLL/DLM are software-written. This mirrors fw-proto-i2c `set_prescale()`. |
| K2 | The baud enable as a separate small core, `uart_baud_xtor_core` (divisor → 16× tick), shared by tx and rx | The 16550 has one divider for both directions (Q3). The kit cores take the tick as an input instead of each owning a divider. |
| K3 | A pull-style RX API, `recv(output data, output status)`, plus a non-blocking `recv_nb` | The model's RX process pulls characters into its FIFO. The existing API pushes into a sink. |
| K4 | Break: `tx.send_break(n_chars)`, and rx/monitor report BI | 16550 LCR[6] and LSR[4] |
| K5 | A sampling option in the rx core: mid-bit single sample (16550, U4) or 3-sample majority | Matching the reference without hard-wiring its choice |
| K6 | Error injection on the tx side, as a VIP-only path: bad parity, bad stop bit, glitch, baud offset | The VIP needs it. Keep it out of the synthesizable core (an `ifdef` or a separate driver core). **D5** |
| K7 | A TLM link, `uart_tlm_link` (tx API on one end, rx API on the other, no transactors), with character-time delays | The `tlm` view, as `i2c_tlm_bus` was for fw-i2c |
| K8 | Optional loopback in the core pair (tx → rx inside, line held at mark) | MCR[4] |
| K9 | Back-to-back tests across word lengths, parity modes, stop bits, divisors (including divisor 1), break, and errors. Formal: protocol properties plus a tx→rx round trip at small divisors | Kit acceptance, as for fw-proto-i2c |

Modem lines (RTS/CTS/DTR/DSR/RI/DCD) are not UART framing. Model them as
plain pins in fw-uart16550. Drive them from the VIP through
`fw-proto-gpio`/`fwvip-gpio` if those fit, or a small modem agent in
fwvip-uart (**D6**).

### 3.2 `fwvip-uart` (UVM VIP): start fresh in the existing empty repo

`featherweight-vip/fwvip-uart` holds only LICENSE and .gitignore. Build it
in the `fwvip-i2c` layout:

- **ivpm.** `use`: fw-hdl, `fw-proto-uart` (dep-set `use`), and fwvip-core.
  `dev` adds the dv-flow libs and Sphinx.
- **flow.yaml.** Package `org.fwvip.uart`, `uses: project.dv.uvm`, with
  `src/vip.yaml` exporting `xtor-pkg` and `vip-uvm-hvlsrc`.
- **Agents.** `fwvip_uart_{tx,rx,mon}_agent`. Each config extends
  `uvm_object` and implements the kit role API, with a `_config_p #(vif_t)`
  that binds the vif. Register macros
  `` `fwvip_uart_{tx,rx,mon}_register(vif, inst) ``.
- **Items.**
  - `fwvip_uart_char`: data, status, and timestamp in bit times.
  - `fwvip_uart_cfg_item`: the line configuration.
- **Sequences.**
  - Random characters, bursts and idle gaps, used to hit the 4-character
    RX timeout.
  - Error injection (K6), break, and baud offset (tolerance ±2–3%).
  - Line reconfiguration.
- **Monitor.** Reconstructs characters with status and publishes them
  through an analysis port.
- **Tests.**
  - A back-to-back UVM env with a scoreboard.
  - A monitor-teeth test (the monitor must flag injected errors).
  - A `+SEQ=` matrix.
- **Docs and skill.** Sphinx docs (design, integration, sequences,
  verification) and a skill `skills/fwvip-uart-usage`, as fwvip-i2c has.

`featherweight-vip/fwvip-example-uart16550` is also empty. fw-uart16550's `ref`
view is a complete UVM bench around the 16550. **D7**: either leave the
example repo unused, or later extract the `ref` view into it as a public
example.

## 4. fw-uart16550 model (sketch, for review in step 1)

Layers, as in fw-i2c design §3.1:

- **Host port.** A Wishbone target through the fw-proto-wb bridge. 8-bit
  and 32-bit are a configuration parameter (Q6).
- **Register block.** From SystemRDL (`src/rdl/fw_uart16550_regs.rdl`) through
  peakrdl-fw-hdl into `fw_reg_block`. The 16550 needs features that
  fw-i2c did not:
  - R1: different registers at one address for read and write (RBR/THR,
    IIR/FCR). fw-i2c design §4.1 R1 split-register support covers this.
  - R2: banking by a field value (DLAB selects DLL/DLM at 0/1).
  - R3: read side effects (an RBR read pops the FIFO; LSR and MSR reads
    clear bits; an IIR read clears the THRE pending bit).
  - R4: byte-lane addressing from `wb_sel` in 32-bit mode.
- **Processes.**
  - `tx`: wait for THR data in the TX FIFO, then `send()` through the
    kit tx API. It holds THRE/TEMT as relations over FIFO state and the tx
    core's busy bit.
  - `rx`: `recv()` from the kit rx API, push to the RX FIFO, and set
    overrun when the FIFO is full (U5).
  - `timeout`: the character-time counter, reloaded on push, pop and empty.
  - Interrupt identification as a relation over the pending bits and the
    IER (model-style-plan option B). Only the edge-captured pending bits
    are state.
  - Modem status: deltas on pin changes.
- **FIFOs.** fw-hdl `fw_channel #(T, DEPTH)` (`src/std/fw_channel.svh`)
  is the obvious library element. Its RTL form is `fw_rv_fifo`. The 16550
  needs more than put/get:
  - `count` (trigger level, debug word)
  - `flush` (FCR[1], FCR[2])
  - an OR over all RX entries' error bits (LSR[7])

  Either extend `fw_channel` (`fw_fifo`) or keep the error bits as a
  separate counter of bad entries in the model, so the FIFO stays plain.
  **D3**.

Carry over from fw-i2c (model-style-plan §7): read registers where they are
used, and do not latch them at command start, unless the reference does.
Make status bits relations. Do not copy values across transactor
boundaries without a reason.

## 5. Verification

The same structure as fw-i2c (bench-plan §3), so the scripts and the
dfm shape carry over.

- **Views.** The universal tests run on the same eight views as fw-i2c:
  - `ref`: U2B0 alone.
  - `ref-eq`: U2B0 against U2B0, the equivalence self-test.
  - `tlm`, `tlm-eq`: the class model at TLM, alone and against U2B0.
  - `wb`, `wb-eq`: the model behind pins.
  - `rtl`, `rtl-eq`: the lowered RTL.
- **Op-model.** A PSS operation model (`src/pss/`), derived with the
  `pss-operation-model-create` skill. Operations (to be confirmed in step
  4):
  - Configuration: `configure_line`, `set_fifo_trigger`, `set_ier`,
    `set_modem`.
  - End-to-end: `send_bytes`, `recv_bytes`, `wait_irq` with its IIR
    reason, `line_status`, `send_break`.
  - Registers come from the same RDL through peakrdl-pss.
- **Equivalence.** Compare at the operation level, as in fw-i2c bench-plan
  §3.1.
  - The serial side has two lines per direction (one per arm):
    - The VIP tx agent drives the same character stream into both arms'
      RX inputs.
    - One rx agent per arm receives each arm's TX output, and the
      scoreboard compares the streams.
  - Allowed differences (bench-plan §3.5 style):
    - The bus timing.
    - Start-bit alignment to the baud tick.
    - THRE timing within the U6 window.
    - The order of interrupts that become pending in the same cycle.
  - The character-timeout time: the reference counts cycles from an
    LCR-derived `toc_value`, so the timeout interrupt's time differs as
    THRE's does under U6.
  - Reset: the reference resets asynchronously on `wb_rst_i`; the model
    resets synchronously. Not visible at the operation level.
- **Reference confirmation.** U1–U12 by directed tests on `ref`.
- **Formal.**
  - Kit properties in fw-proto-uart.
  - In fw-uart16550, the debug⊗tight certificate miter (synthesis-plan §0.9).
  - The assumed-view certificate with its stated assumptions (Q5).

## 6. Synthesis

Reuse the fw-i2c path unchanged where possible: elaborate, translate,
structure, lower (synthesis-plan §0). The work here is mostly the §8.3
items fw-i2c did not need.

### 6.1 Expected Zuspec and fw-hdl requirements

| ID | Requirement | Driven by |
|---|---|---|
| ZU1 | Arrays as state: an unpacked array indexed by a pointer, with reads and writes per cycle; lowered to flops plus a read mux | Q2 |
| ZU2 | Memory inference as an option: emit a synchronous-read array in the form Yosys maps to `SB_RAM40_4K`, when the read can be moved one cycle earlier | Q2, D4 |
| ZU3 | A library FIFO kept as a leaf (`fw_rv_fifo` or `fw_fifo`) as an alternative to lowering its class form; measure both | Q2, and the synthesis-plan §0 principle "lower from its own SV source" |
| ZU4 | Several independent forever-processes with shared state: per-bit write resolution across processes with priority (existing), and seqcorr/copy merging over the product machine | Q1 |
| ZU5 | Counter recognition: up and down counters, and compare-to-constant, emitted so Yosys uses carry chains | Q3 |
| ZU6 | Elaboration-time configuration (bus width, endianness, debug) folded before lowering | Q6 |
| ZU7 | Side-effect reads in the register block lowered as a read strobe | R3 |
| ZU8 | The assumed view: environment assumptions as SVA `assume`s, used in the induction and stated in the certificate | Q5 |

None of these is built speculatively. Each is built when the lowering of
fw-uart16550 reaches it, with a generic test in its own clone (fw-i2c
synthesis-plan §8.4 rule).

### 6.2 Measurement

- **Flow.** The same flow as fw-i2c: `synth_ice40 -device u` plus nextpnr
  on the iCE40UP5K, with LUT4 as the median of 11 reordered runs, and the
  strong ABC flow as a cross-check.
- **Attribution by function.** Bus and registers, TX path, RX path, FIFO
  storage, interrupts, and library cores.
- **Two comparisons** (D4):
  - (a) Like for like: FIFOs in flops, against U2B0 as it is.
  - (b) Memory: FIFOs in block RAM on both sides. The reference needs a
    sync-read `raminfr` patch, kept on the fork as a measurement-only
    branch.
- **Budget** (set in step 0 from the baseline in §2, as fw-i2c
  synthesis-plan §2 did). Headline, `ref-rtl` (8-bit core + shim),
  flattened: 821 LUT4, 564 FF, 80 CARRY. 10%: **≤ 903 LUT4, ≤ 620 FF**.
  FIFO storage (2 × `raminfr`: 280 LUT4, 256 FF, plus 48 RX error-bit FFs)
  is reported apart from control, since it is a third of the LUT4 and half
  of the FFs (§10). Timing: ≥ 0.9 × 41 MHz on the 8-bit core, which is not
  expected to bind.

## 7. Repo layout (as fw-i2c)

```
fw-uart16550/
  ivpm.yaml          use: fw-hdl, fw-proto-uart, fw-proto-wb
                     dev: + oc-uart16550, fwvip-uart, fwvip-wb, peakrdl-*,
                       pssc/pssparser, dv-flow libs, verilator, yosys,
                       nextpnr, sphinx
  flow.yaml          org.fwip.uart16550, uses project.dv.uvm; views as fw-i2c
  src/rdl/           u2b0 register map (as-built) and fw_uart16550_regs.rdl
  src/pss/           op-model
  src/ref/           oc_uart16550_wb32.sv (§2.1) and its flow.yaml
  src/spl/           class model
  src/spl-rtl/       pin top (fw_root based), the synthesis top
  tests/uvm/         env, tb, tests (views of §5)
  scripts/           from fw-i2c: ivpm-env.sh, synth-baseline.sh,
                       synth-lowered.sh, synth_attrib.py, lower-variant.sh,
                       test-rtl.sh, speed_report.py, style-measure.sh
  docs/              Sphinx/MyST: reference/, design/ (this plan), results.md
  .envrc             loads packages/packages.envrc
  lint-waivers.yaml  every waiver with its reason
```

Set up as fw-i2c: `ivpm update`, then once
`uv pip install --python packages/python/bin/python -e packages/fw-hdl/python`
(fw-hdl's dfm plugin, which ivpm does not install), and `direnv allow`. Use `DFM_JOBS=2 DFM_CORES=8` on every dfm run.

## 8. Decisions needed

| ID | Question | Recommendation |
|---|---|---|
| D1 | Reference pin: `2b0ad80` (HEAD, includes the timeout fix) or `rel_4` | `2b0ad80` |
| D2 | Bus width for the headline comparison | **Decided 2026-10-20**: the 8-bit core (`DATA_BUS_WIDTH_8`, no debug block) behind the fw-XXX 32-bit shim (§2.1). The native 32-bit mode packs the 8 byte registers into two words by `wb_sel` (`uart_wb.v`), which is not the fw-XXX convention; it is the second configuration (step 11), so R4 is a step-11 item. |
| D3 | FIFO: extend `fw_channel` into `fw_fifo` (count, flush, OR over error bits), or keep the FIFO plain and track errors in the model | Plain FIFO plus count/flush in the library; error tracking in the model. An OR over the contents is design-specific. |
| D4 | Comparison basis for FIFO storage | Report both (a) flops, like for like, as the headline and (b) block RAM, as a measurement |
| D5 | Where tx error injection lives (K6) | A separate VIP-only driver core in fw-proto-uart, outside `xtor-core`, so synthesizable cores carry no test logic |
| D6 | Modem lines in the VIP | Reuse fwvip-gpio if its API fits in step 2; otherwise a small modem agent in fwvip-uart |
| D7 | `fwvip-example-uart16550` | Leave it unused for now |
| D8 | Repo name | **Decided 2026-10-20**: `fw-uart16550` (fw-<oc-ip-name>), package `org.fwip.uart16550`, SV prefix `fw_uart16550_`. Create the remote when step 0 is done. The empty sibling `../fw-uart` is not used. |

## 9. Steps and status

| # | Step | Output | Status |
|---|---|---|---|
| 0 | Fork `oc-uart16550`, pin U2B0, `fw` patch set. Reference spec (as-built) and register map in SystemRDL. Baseline synthesis script and per-block area. Re-run the shipped bench (U11). | `docs/reference/`, `src/rdl/u2b0_regs.rdl`, `scripts/synth-baseline.sh` | **done 2026-10-21**. Fork `../oc-uart16550` (tags `u2b0`, `u2b0-fw1` = ef67d27, branch `fw-u2b0`, pushed; equivalent and area-identical to `u2b0`). Upstream bench (U11) reproduces the shipped log. Shim `src/ref/oc_uart16550_wb32.sv` + `src/ref/flow.yaml` (`ref-rtl`, `ref-rtl-32`; wired into a root flow.yaml in step 4), Verilator-clean. `scripts/synth-baseline.sh` (configs 8/32/shim, 11-seed median via `scripts/perturb_rtl.py`, shim own cells = 0): baseline §2, budget §6.2. Reference spec `docs/reference/` (12 pages; RTL-read claims marked *(to confirm)*, for step 4) and RDL `src/rdl/u2b0_regs.rdl` + `u2b0_uart16550.rdl` (two addrmaps, DLAB = 0 and DLAB = 1; peakrdl-clean) + `src/rdl/flow.yaml` (rdl-src only). New quirks U13–U26. Open: create the fw-uart16550 remote (D8). |
| 1 | Review this plan, answer D1–D8, write the design doc (fw-i2c `docs/design/index.md` shape) | `docs/design/index.md` | not started |
| 2 | `fw-proto-uart`: restructure to kit conventions; K4, K6 with their K9 tests; lint, CI, formal, skill (K1–K3, K5, K7, K8 in step 7) | fw-proto-uart main | not started |
| 3 | `fwvip-uart`: tx/rx/mon agents on the step-2 kit API, sequences, b2b and teeth tests, docs, skill | fwvip-uart main | not started |
| 4 | dfm flow and `ref` view on Verilator with fwvip-wb + fwvip-uart; confirmation tests U1–U12; `lint-rtl` clean | `tests/uvm/`, `docs/reference/deviations.md` | not started |
| 5 | PSS op-model, equivalence harness, `ref-eq` self-test | `src/pss/`, `tests/uvm/env/` | not started |
| 6 | Register tooling R1–R4 in peakrdl-fw-hdl / `fw_reg_block`; `fw_uart16550_regs.rdl` | PRs, `src/rdl/` | not started |
| 7 | fw-proto-uart K1–K3, K5, K7, K8 as the model needs them; class model; `tlm` and `tlm-eq` pass | `src/spl/` | not started |
| 8 | Pin top; `wb` and `wb-eq` pass | `src/spl-rtl/` | not started |
| 9 | Lowering: ZU1–ZU7 as reached; `rtl` and `rtl-eq` pass; first area | `docs/design/synthesis-plan.md`, `docs/results.md` | not started |
| 10 | Optimization: tight view and certificate on independent processes (Q1); FIFO options (Q2); counters (Q3); assumed view (Q5); model-style options | `docs/design/synthesis-plan.md` | not started |
| 11 | Second configuration (32-bit, debug) from the same model (Q6) | `docs/results.md` | not started |

Order: steps 0–1 first. Steps 2–3 (packages) run alongside 4–5, because the
`ref` view needs fwvip-uart. Step 6 can start any time after step 1.

## 10. Risks

- **The kit rx core vs U4.** If the kit rx core cannot reproduce
  mid-bit sampling at the reference's tick alignment, character-level
  equivalence still holds, but error-injection tests (glitches, baud
  offset) can differ. Those tests are compared under allowed differences
  only.
- **THRE and interrupt timing (U6, U7)** are cycle-level details that
  software sees. If the op-model cannot absorb them, the model must copy
  them, at some cost in abstraction. Decide per case in step 7.
- **FIFO storage dominates area** (about half of the reference's FFs). A
  better or worse FIFO choice can hide the control-logic comparison.
  Always report storage and control separately (§6.2).
- **The product state space of TX × RX × timeout** may defeat
  simulation-guided candidate generation for the tight view (Q1). Measure
  it before relying on it.

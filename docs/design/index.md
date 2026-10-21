# fw-uart16550 design

```{admonition} Status
:class: note
Written 2026-10-21 (plan step 1); open issues answered the same day
({ref}`open-issues`). None of this is implemented yet.
Plan, status and step order: {doc}`plan`.
```

```{admonition} Decisions so far
:class: tip
- **Reference:** U2B0 = freecores `uart16550` `2b0ad80`, used from
  `featherweight-ip/oc-uart16550` at tag `u2b0-fw1`. The patch set changes
  no behaviour or area. (plan D1, §2.1)
- **Headline configuration:** the 8-bit core (`DATA_BUS_WIDTH_8`) behind
  the 32-bit shim `oc_uart16550_wb32`: one register per 32-bit word, low
  byte valid, `wb_sel` ignored. The 32-bit native mode is step 11. (plan D2)
- **Target:** iCE40UP5K (iCEBreaker, 12 MHz). Baseline: 821 LUT4, 564 FF,
  80 CARRY. 10% budget: ≤ 903 LUT4, ≤ 620 FF. ({doc}`../reference/synthesis`,
  plan §6.2)
- **Repository and names:** `fw-uart16550`, package `org.fwip.uart16550`,
  SV prefix `fw_uart16550_`. (plan D8)
- **FIFO:** a new library class `fw_fifo` in fw-hdl (packed storage, one
  writer per side, count, peek, flush), not an in-repo class and not an
  extension of `fw_channel`, which does not lower. (OI-1, §3.4)
- **Quirks:** copy U2B0's visible register and pin behaviour; do the 16550
  thing for its defects, each with a named bench rule (§5). (OI-2)
- **FIFO flush:** the one allowed two-writer case: the host writes the
  reader's pointer, and the host's priority wins over the reading process
  in the same clock. (OI-4, §3.2)
- **Reset:** synchronous `wb_rst_i` in the model. (OI-5)
- **Kit, VIP, example:** tx error injection in a VIP-only driver core; a
  modem agent in fwvip-uart unless fwvip-gpio fits; one shared baud tick
  core (K2) in step 2; the tx core holds characters during break;
  `fwvip-example-uart16550` unused. (OI-6 to OI-10)
```

## 1. Goal

Build a 16550-compatible UART with fw-hdl that:

1. is aligned with U2B0, whose actual behaviour is documented in
   {doc}`../reference/index`;
2. is verified against U2B0 on the fw-i2c bench structure (views `ref` …
   `rtl-eq`, equivalence at the operation level);
3. is lowered to RTL by the fw-i2c synthesis path;
4. is synthesized with the same flow as U2B0 and compared for area, with
   FIFO storage reported apart from control.

fw-i2c had one controlling process and almost no storage. The point of
this design is the six things it lacked (plan §1, Q1–Q6): concurrent
processes, FIFO storage, counters, an interrupt priority encoder, behaviour
the spec leaves undefined, and elaboration-time configuration.

### Inputs reviewed

| Input | What it gives this design |
|---|---|
| {doc}`../reference/index` | U2B0 as built, with quirks U1–U26 ({doc}`../reference/deviations`) |
| `src/rdl/u2b0_*.rdl` | The register map. The fw map will reuse `u2b0_regs.rdl` on a 4-byte stride |
| `fw-proto-uart` (066ed5a, 2026-06-29) | tx/rx/monitor cores and API. Its sim and formal pass. Each core has its own divider; RX samples once, mid-bit; config is read live; push-style RX API; break detect only |
| `fw-hdl` (`fw_reg_block`, `fw_channel`) and the fw-i2c lowering (`fe/elab`, zuspec-synth `lower.py`) | What the model can use and what lowers (§3.4, §4) |
| `fw-proto-wb` target, `fwvip-wb` initiator | Host port. The initiator always leaves an idle clock between accesses, so it never hits U13 |
| fw-i2c design, bench-plan, model-style-plan, synthesis-plan | The bench shape and the lessons in §5.1 |

## 2. Scope

| | This design | Later |
|---|---|---|
| Registers | The U2B0 map: RBR/THR, IER, IIR/FCR, LCR, MCR, LSR, MSR, SCR, DLL/DLM | — |
| Bus | WISHBONE Classic, 32-bit, one register per word (as the shim) | Native 32-bit mode with byte lanes and debug words (step 11, R4) |
| FIFOs | 16 deep, always on (U3), trigger 1/4/8/14 | Depth as a parameter |
| Line | 5–8 bits, parity none/odd/even/stick, 1/1.5/2 stop, break, loopback | — |
| Modem | RTS/DTR out, CTS/DSR/RI/DCD in, deltas | OUT1/OUT2 pins |
| Timing | One baud divider, 16× oversampling | — |
| Not in scope | DMA mode, 16450 mode (FCR[0] ignored, as U2B0) | — |

## 3. Architecture

```{mermaid}
flowchart LR
  WB["wb_* pins"] --> WBT["fw-proto-wb<br/>target xtor"]
  WBT --> HA["host access<br/>(decode, DLAB, side effects)"]
  HA <--> RB["register block<br/>(from RDL)"]
  HA --> TXF["TX FIFO"]
  RXF["RX FIFO"] --> HA
  RB --> BAUD["baud tick<br/>(DL)"]
  TXF --> TXP["tx process"] --> TXC["kit tx core"] --> STX["stx_pad_o"]
  SRX["srx_pad_i"] --> SY["2-flop sync<br/>(leaf)"] --> RXC["kit rx core"] --> RXP["rx process"] --> RXF
  BAUD --> TXC
  BAUD --> RXC
  RXF --> TO["timeout"]
  RB --> IRQ["IIR / int_o<br/>(relation)"]
  TXF --> IRQ
  RXF --> IRQ
  TO --> IRQ
  MOD["modem pads"] --> RB
```

### 3.1 Layers

| Block | Implementation | Benchmark category |
|---|---|---|
| WISHBONE target | `fw-proto-wb` target transactor (library) | Glue. Reported |
| Host access | The model's `access()`: address decode, DLAB banking, read side effects (§4) | CSR front end. Headline |
| Register block | SystemRDL → peakrdl-fw-hdl → `fw_reg_block` | CSR front end. Headline |
| TX and RX FIFOs | Packed storage with pointers (§3.4) | **Storage**. Reported apart from control |
| tx, rx processes | fw-hdl processes over the kit API | **Headline:** control |
| Timeout, interrupts, modem | Relations and small processes (§3.5) | **Headline** |
| Baud tick | Shared divider, `uart_baud_xtor_core` (K2) | Bit level. Reported |
| tx and rx cores | `fw-proto-uart` cores (library) | Bit level. Reported |
| Synchronizer | 2-flop leaf RTL on `srx_pad_i` | Glue |
| Top | The same pins as `oc_uart16550_wb32` | Glue |

### 3.2 Processes and who writes what

U2B0 has five pieces of state updated from different places in the same
clock: the RX FIFO (pushed by the receiver, popped by RBR reads), the TX
FIFO (pushed by THR writes, popped by the transmitter), the timeout
counter, the THRE pending flag, and the MSR deltas. The lowering resolves
a bit written by two processes by priority (`lower.py:699-753`), and two
model processes have the same priority. So a push and a pop in the same
clock would lose one of them. U16 and U17 are the reference's own version
of this bug.

The rule for this design: **every state bit has exactly one writer.**
Counts and flags that two sides change are computed from two
single-writer values:

| State | Writer | Readers | Derived |
|---|---|---|---|
| RX `wr_ptr`, entries | rx process | host access | `rx_count = wr_ptr − rd_ptr` (5-bit pointers) |
| RX `rd_ptr` | host access (RBR read) | rx process | `rx_full`, LSR.DR = `rx_count ≠ 0` |
| TX `wr_ptr`, entries | host access (THR write) | tx process | `tx_count`, LSR.THRE = `tx_count = 0` |
| TX `rd_ptr` | tx process | host access | LSR.TEMT = THRE and tx core idle |
| RX bad-entry pushes `rx_bad_wr` | rx process | host access | LSR[7] = `rx_bad_wr ≠ rx_bad_rd` |
| RX bad-entry pops `rx_bad_rd` | host access | — | |
| LSR.OE/PE/FE/BI sticky bits | rx process sets a toggle; host access acks it | | bit = `set_tgl ≠ ack_tgl` |
| THRE pending | toggle pair (tx side sets on THRE rise; IIR read / THR write ack) | | |
| MSR deltas | modem process sets, MSR read acks (toggle pair) | | |
| Timeout counter | timeout process; reload on push/pop seen through the pointers | | TI = `count = 0` and `rx_count ≠ 0` |

**The one exception is a FIFO flush** (FCR[1], FCR[2]; OI-4). A flush
empties the FIFO by setting `rd_ptr = wr_ptr`:

- **RX flush:** the host owns RX `rd_ptr`, so this is a single-writer
  write. A character pushed in the same clock survives the flush, as if it
  had arrived just after it. The host also sets `rx_bad_rd = rx_bad_wr` and
  acks the sticky LSR bits.
- **TX flush:** TX `rd_ptr` belongs to the tx process. The host writes it
  too, and **the host wins** in the same clock. A pop in that clock is
  overridden; the character it took is already in the tx core and is sent,
  as in U2B0. The priority is the lowering's own (bridge/host context 2 over
  model process 0, `translate.py:244-252`), so it needs no extra logic, only
  the warning the lowering prints for a two-writer bit, which this design
  expects for TX `rd_ptr` and nowhere else.

(Setting the host-owned `wr_ptr = rd_ptr` instead would avoid the second
writer, but a same-clock pop would then leave `rd_ptr` one ahead of
`wr_ptr`: a count of −1.)

Toggle pairs cost one flop per side instead of one flop, but they make the
same-clock set and clear cases exact by construction, and the relation
(`≠`) is the status bit, which is the model-style-plan B style.

### 3.3 tx and rx

- **tx process:** `forever`: wait until `tx_count ≠ 0` and the tx core is
  ready; read the head entry; `tx.send(data)`; advance `rd_ptr`. LCR and DL
  go to the core as configuration (K1), applied at the next character.
  Break (LCR.BC) is a level into the core (K4): the core holds the line at
  0, and characters behind it wait instead of being lost (U2B0 sends them
  invisibly; OI-2).
- **rx process:** `forever`: `rx.recv(data, status)` (pull, K3); if the
  FIFO is full, set OE and drop the character (16550 behaviour; U2B0
  overwrites the head, U14; OI-2); else write the entry, count it in
  `rx_bad_wr` if it has an error, and advance `wr_ptr`. Set the sticky LSR
  bits from `status`.
- **Kit cores:** fw-proto-uart's rx core samples once at mid-bit (U4), so
  it matches the reference without change. K5 (majority option) is not
  needed for equivalence and stays a kit option.

**The kit as built in step 2** (fw-proto-uart, `src/`), where it bears on
the model:

- **Baud tick (K2).** `uart_baud_xtor_core`: `tick` every `cfg_divisor`
  clocks; divisor 0 stops the line. A divisor change takes effect at the
  next tick. The `dlm_restart` rule (U24) has the model restart the
  divider on any DL write, so step 7 needs a restart input on the baud
  core, or that rule has to change.
- **tx core.** Every bit edge is on a tick, and a character is accepted on
  the tick that ends the previous stop bit, so back-to-back frames have no
  gap. U2B0 also shows 16/24/32 ticks of stop between back-to-back
  characters (timing.md). `busy` gives TEMT (`!busy` and the FIFO empty).
  Framing is sampled when a character is accepted (K1 at the core level;
  the class-side `configure()` is unchanged).
- **Break (K4).** `brk` is a level: space at once, no new character while
  it is 1, and one bit of mark after it falls before the next start bit.
  U2B0 has no such mark. That and the held characters are both part of
  rule `break_queue`.
- **rx core.** It looks at the line only on ticks. A start is the first
  tick that sees space, and each bit is sampled `OVERSAMPLE/2` ticks after
  that (8 to 9 ticks after the edge at 16×). After a BI character it waits
  for mark on a tick. The step 4 tests show whether U2B0's sample point is
  the same tick; U4 equivalence under glitch tests depends on it.
- **Error injection (K6)** is in `uart_tx_xtor_if` (not synthesizable),
  muxed over the core's `txd` in the `uart_tx_xtor` wrapper. Each injected
  frame ends with one bit of mark.

### 3.4 FIFOs

`fw_channel` cannot be used. The fw-i2c lowering path does not special-case
it, and its `m_q[$]` queue operations are rejected inside a process
(`translate.py:1396`). Unpacked arrays are rejected too (`translate.py:1142`,
ZU1). Packed vectors with run-time indexes do lower (`translate.py:1167-1181,
1462-1474`).

So the FIFO is a **new fw-hdl library class, `fw_fifo #(type T, int
DEPTH)`** (decided, OI-1), next to `fw_channel` in `src/std/`. Any fw-hdl
design with a FIFO it must count, peek or flush needs it, and it has to
lower, which `fw_channel` does not.

- **Storage:** `bit [DEPTH-1:0][$bits(T)-1:0] mem` (packed, so it lowers
  today), two pointers one bit wider than the index.
- **Writer side:** `push(T)`, `full()`, `wr_ptr`. **Reader side:**
  `head()` (peek), `pop()`, `empty()`, `rd_ptr`. `count()` is a relation
  over the two pointers. Each side writes only its own pointer, so the
  single-writer rule of §3.2 holds by construction.
- **`flush()`** sets `rd_ptr = wr_ptr`. Called from the reader side it is a
  single-writer write. Called from the writer side it is a second writer of
  `rd_ptr`, and the caller must have the higher lowering priority (as the
  host does here); the class documents this rather than hiding it.
- **Overflow:** `push` when full is a caller error. The class asserts it in
  simulation and ignores the push in RTL (it does not overwrite, unlike
  `raminfr`, U14/U15).
- **Simulation form:** the same packed storage (not a queue), so `tlm` and
  the lowered RTL hold the same state.
- **Tests:** a fw-hdl unit test (both sides in separate processes,
  same-clock push and pop, flush from either side, full and empty) and a
  lowering test (the lowered form against the class), in fw-hdl's own
  clone, per the fw-i2c rule (synthesis-plan §8.4). Built in step 7 when
  the model needs it (plan §6.1, ZU9).

It lowers to flops plus a read mux, like `raminfr` on iCE40, which keeps
the storage comparison like for like (OI-3 (a)). ZU1 (unpacked arrays) and
ZU2/ZU3 (memory inference, kept leaf) stay step 10 options.

The RX error flags are not stored per entry for LSR[7]. Each entry keeps
its 3 flags for LSR.PE/FE/BI of the head character (U2B0 does the same), and
LSR[7] comes from the bad-entry counters (§3.2), not an OR over 48 flops.
That is an expected area win over the reference (its 48-input OR and
per-entry clear logic, in `uart_rfifo`'s 139 LUT4).

### 3.5 Interrupts, timeout, modem

- **IIR and `int_o` are relations** over the sources and IER, evaluated
  in the host read and as a combinational output, in U2B0's priority order:
  RLS > RDA > TI > THRE > MS.
  - RLS = OE | PE | FE | BI (the sticky bits).
  - RDA = `rx_count ≥ trigger` (a level, as U2B0's IIR, U7).
  - TI = timeout counter at 0 and `rx_count ≠ 0`.
  - THRE = the THRE pending toggle pair (the only latched source).
  - MS = any MSR delta.
  So none of the pending flags of U2B0 except THRE is state, and U20/U21
  cannot occur.
- **Timeout:** a process that reloads a 10-bit down-counter on push, pop
  and empty, and counts on baud ticks. `toc_value` is a relation over LCR
  (character length × 4).
- **Modem:** MSR[7:4] are the pads (or MCR in loopback); MSR[3:0] deltas are
  set by a process that keeps the previous pad values. Whether to
  synchronize the pads (U9) is OI-2.

### 3.6 Reset

U2B0 resets asynchronously on `wb_rst_i`. fw-hdl models and the lowering
use a synchronous reset (fw-i2c OI-10). Recommendation: `wb_rst_i` is a
synchronous reset in fw-uart16550, and the bench holds it for at least two
clocks with the clock running, so the difference cannot be seen at the
operation level. On iCE40 both map to `SB_DFFR`/`SB_DFFSR`-class flops at
no LUT cost. (OI-5)

## 4. Registers

The fw map, `src/rdl/fw_uart16550_regs.rdl`, includes `u2b0_regs.rdl` with
stride 4 and 32-bit registers (bits [7:0] implemented), as fw-i2c does. It
also compiles the DLAB = 1 bank (`u2b0_uart16550_dlab`) as a second map.

What the tools give today, and where the rest goes:

| Need | Today | This design |
|---|---|---|
| R1: split read/write at one offset (RBR/THR, IIR/FCR, MCR) | Done (`FW_REG_RO`/`FW_REG_WO`, built for fw-i2c) | Use as is |
| R2: DLAB banking (DLL/DLM over 0/1) | None in `fw_reg_block` or peakrdl | Decode in the model's `access()`: `if (LCR.DLAB && adr < 2)` go to the DLAB block (fw-i2c decodes `sel` the same way). No tool change |
| R3: read side effects | `rclr` works (`fw_reg_base.svh:156-167`); there is no read strobe; `on_read` is a value provider also used for peeks | Side effects in `access()` (we = 0): RBR pops, LSR acks OE/PE/FE/BI and LSR[7], MSR acks the deltas, IIR acks THRE pending when it returns 0xC2. These are writes from the host side, which keeps §3.2's single-writer rule |
| R4: byte lanes from `wb_sel` | None (`fw_reg_block_if` has no byte enables) | Not needed for the headline (shim ignores `sel`). Step 11 |
| Status as relations (LSR, IIR, MSR[7:4]) | `fw_reg_rd_if.on_read` value providers | Use as is |
| Write reactions (THR, FCR, DLL/DLM, LCR) | `fw_reg_wr_if.on_write` observers; events cannot be lowered | Observers that set flags; processes `wait(flag)` (fw-i2c style) |

So plan step 6 shrinks: no peakrdl-fw-hdl or `fw_reg_block` work is needed
for the headline. Step 6 becomes writing `fw_uart16550_regs.rdl` and
checking that the unsupported-property warnings (FWH-SIDEEFFECT for
`swacc`/`swmod`, FWH-RSET) are only ones the model handles in `access()`.

## 5. Behavioural alignment

The model is register- and protocol-compatible with U2B0. For each quirk
the question is whether the model copies it (and pays for it in area and
abstraction) or does the 16550 thing and the bench allows the difference
by a named rule (fw-i2c bench-plan §3.5). Proposed (OI-2):

| ID | Quirk | Proposed | Why |
|---|---|---|---|
| U1, U2, U3 | MCR reads 0; SCR exists; FIFOs always on | Copy | Visible register behaviour; cheap |
| U4 | Single mid-bit sample | Copy (the kit already does it) | Equivalence under glitch tests |
| U5, U14 | Overrun: U2B0 overwrites the head byte | 16550: drop the new character | U14 corrupts data software has not read. Rule `overrun_head` |
| U6 | THRE hold-off (`block_cnt`) | Do not copy | One character of extra latency with no function. Rule `thre_holdoff` (THRE and its interrupt may come earlier) |
| U7 | RDA in IIR is a level | Copy (it is the relation) | |
| U8 | Loopback still drives RTS/DTR | Copy | Pins compared in loopback tests |
| U9 | Modem pads not synchronized | Copy, measure a synchronized option in step 10 | Area like for like |
| U11 | Upstream bench THRE report | n/a (bench bug) | |
| U12 | Break gives one zero character with BI | Copy | 16550 behaviour |
| U13 | Access right after ack is dropped | Do not copy | The fw target never drops an access. The VIP never triggers it; confirmed on `ref` with a pin-level test only |
| U15 | 17th THR write replaces the next byte | 16550: ignore the write | Rule `tx_overflow` |
| U16, U17 | Same-clock push/pop loses a character / keeps flags | Do not copy (§3.2 makes it impossible) | Rule `rx_pushpop` |
| U18, U19 | LSR errors only on edges; LSR[7] cleared while errors remain | 16550: set per character; LSR[7] from the bad-entry counters | Rules `lsr_edge`, `lsr7_clear` |
| U20, U21 | RDA lost / stuck | Do not copy (no RDA latch) | Rules `rda_lost`, `rda_stuck` |
| U22, U23 | Loopback deltas follow pads; active-high modem pins | Copy | Pin compatibility |
| U24 | DLM write does not restart the divider | Do not copy (any DL write restarts it) | Rule `dlm_restart` |
| U25 | With DLAB = 1, IIR/LSR/MSR reads clear nothing | Copy | Falls out of the DLAB decode |
| U26 | TX FIFO reset as the transmitter starts sends a stale byte | Do not copy | Rule `tx_reset_race` |

Each "do not copy" item gets a directed test on `ref` that shows the
U2B0 behaviour (step 4) and a rule the eq views must apply in that test
and nowhere else.

Not copying costs nothing in fairness of area only if the fix is not
larger than the bug. U6 (`block_cnt`, an 8-bit counter) and the U20/U21
latches are removed, which saves area; the toggle pairs of §3.2 add
some. Both are reported in the attribution (plan §6.2).

### 5.1 Lessons carried from fw-i2c

- Every transactor boundary costs a request word, a handshake and a
  response word (synthesis-plan §0.8). The tx and rx cores are the only
  transactor boundaries here besides the host port. Keep FIFO, LSR and IIR
  logic in relations, not behind a transactor.
- Read registers where they are used; do not latch them at command start.
  LCR and DL go straight to the cores (K1 latches them at the character
  boundary *inside* the core, which is what U2B0 does not do and the
  16550 spec leaves open; OI-2 row "LCR mid-character").
- Status is a relation through a read provider (LSR.DR, THRE, TEMT, IIR).
- Configuration through write observers (the PRER lesson: −29 LUT4).
- No `HOST_TICKS`-style delays in the model (fw-i2c A8).
- Library cores will be a large share. Measure the kit cores alone in
  step 2, before the model exists.

## 6. Verification

### 6.1 Benches

As fw-i2c (bench-plan §3.4): views `ref`, `ref-eq`, `tlm`, `tlm-eq`, `wb`,
`wb-eq`, `rtl`, `rtl-eq`. The same tests run on every view.

- **Host side:** `fwvip-wb` initiator. It leaves one idle clock between
  accesses (period 4 against U2B0), so U13 is never hit. No change needed.
- **Serial side:** per arm, one VIP tx agent drives the arm's `srx` and one
  rx agent receives its `stx`. In eq views the same tx stream goes to both
  arms. The modem pads are driven from a small agent (D6).
- **`tlm`:** the class model on `uart_tlm_link` (K7) instead of the kit
  cores. As `i2c_tlm_bus`, it implements the tx API, calls the peer's rx API
  and fans out to monitors, with optional character timing.

### 6.2 Equivalence

At the operation level, as fw-i2c (`fw_i2c_op_eq`): each op-model call is
forked into both arms. Each runs its own waits, and the outputs are
compared at the join. Ops (to confirm in step 5): `configure_line`,
`set_fifo`, `set_ier`, `set_modem`, `send_bytes`, `recv_bytes`, `wait_irq`
(returns the IIR reason), `line_status`, `send_break`, `loopback`.

Serial streams are compared by order (`stx` of each arm through its rx
agent). Allowed differences are the named rules of §5 plus the timing ones
of plan §5: bus timing, start-bit alignment to the tick, THRE within the U6
window, the order of interrupts pending in the same clock, the timeout
time. Every rule application is counted and reported; a test that expects
a rule says so (`EQ_EXPECT`).

The register-level tee of fw-i2c (`i2c_eq_model`, compare every read) does
not fit as is: reads of RBR, IIR, LSR and MSR have side effects and depend
on timing. Reads are compared only through ops that wait for the state to
settle on both arms.

### 6.3 Reference confirmation

U1–U26 by directed tests on `ref` (step 4). U13 needs a pin-level
initiator with a zero-idle mode, used only in that test.

### 6.4 Formal

- Kit: protocol properties and tx→rx round trip in fw-proto-uart (step 2).
- Here: the FIFO class (pointer invariants, no lost push under same-clock
  pop) by BMC on its lowered form; the debug⊗tight certificate miter
  (synthesis-plan §0.9); the assumed view with stated assumptions (Q5).

## 7. Lowering and synthesis

### 7.1 Flow

The fw-i2c path, unchanged where possible: elaborate, translate, structure,
lower (synthesis-plan §0). Expected new needs, built only when reached
(plan §6.1): several processes over shared state (ZU4: supported, with the
§3.2 rule making priority moot), packed-vector FIFOs (supported; ZU1 only
as a step 10 option), counters (ZU5), configuration folding (ZU6, step 11),
the read strobe (ZU7: it is the host `access()` call, so nothing new).

### 7.2 Measurement

As plan §6.2. The comparison is reported in four parts, each against the
matching U2B0 modules (hierarchy kept):

| Part | U2B0 modules | U2B0 LUT4 / FF |
|---|---|---|
| Bus and registers, IIR, modem | `uart_wb`, `uart_regs` (less divider), `uart_sync_flops` | ≈ 225 / 147 |
| TX path | `uart_transmitter`, `uart_tfifo` | 81 / 36 |
| RX path | `uart_receiver`, `uart_rfifo` | 268 / 116 |
| FIFO storage | `raminfr` ×2 | 280 / 256 |

The divider is in `uart_regs` in U2B0 and in a kit core here; step 9
splits it out of the U2B0 number with `scripts/synth_attrib.py`-style
attribution.

(open-issues)=
## 8. Open issues

| ID | Issue | Proposed answer |
|---|---|---|
| OI-1 (D3) | FIFO: extend `fw_channel` into `fw_fifo`, or keep the FIFO plain? | `fw_channel` does not lower (§3.4). Proposed: a packed-storage FIFO class in this repo with single-writer sides; LSR[7] from bad-entry counters. **Decided** 2026-10-21: a new fw-hdl library class `fw_fifo` (§3.4). `fw_channel` does not lower; an in-repo class was proposed and rejected in favour of the library |
| OI-2 | Which quirks to copy (§5 table) | As the §5 table: copy visible register and pin behaviour (U1–U4, U7, U8, U9, U12, U22, U23, U25), do the 16550 thing for defects with a named rule each. LCR or DL changed mid-character: the kit applies it at the next character (K1); U2B0 applies it at once; rule `lcr_midchar`, tested only under Q5. **Decided** 2026-10-21: as proposed (§5 table) |
| OI-3 (D4) | FIFO storage comparison basis | (a) flops, like for like, as the headline; (b) block RAM both sides as a measurement (needs a sync-read `raminfr` branch on the fork). **Decided** 2026-10-21: as proposed |
| OI-4 | FIFO flush when the other side owns the pointer | Proposed: a request/ack pair (single-writer kept), or a two-writer write with stated priority. **Decided** 2026-10-21: two writers with a stated priority; host wins (§3.2) |
| OI-5 | Reset | Synchronous `wb_rst_i` in the model (§3.6). **Decided** 2026-10-21: synchronous `wb_rst_i` (§3.6) |
| OI-6 (D5) | Where tx error injection lives (K6) | A VIP-only driver core in fw-proto-uart outside `xtor-core` (a txd override mux in the tx xtor wrapper, driven from `xtor_if` tasks). **Decided** 2026-10-21: as proposed |
| OI-7 (D6) | Modem lines in the VIP | A small modem agent in fwvip-uart (four inputs, two outputs, with an edge monitor). Check fwvip-gpio in step 3 first, and use it if its API fits. **Decided** 2026-10-21: as proposed |
| OI-8 (D7) | `fwvip-example-uart16550` | Leave unused for now. **Decided** 2026-10-21: as proposed |
| OI-9 | K2 shared baud tick: a kit change across all three cores (medium) | Do it in step 2: one divider for both directions is U2B0's structure, and two private dividers would cost about 2 × 16 FF and their counters in the comparison. **Decided** 2026-10-21: as proposed |
| OI-10 | Break while characters are queued (U2B0 sends them invisibly) | The kit tx core holds characters during break (K4); rule `break_queue`. **Decided** 2026-10-21: as proposed |

## 9. Opportunities

- The single-writer FIFO pattern (§3.2) is the shape of `fw_fifo`, and a candidate rule for the lowering itself
  (detect a count written by two processes and split it).
- LSR[7] by counters instead of an OR over the FIFO: a relation that is
  cheaper than the reference's state.
- U2B0's interrupt latches (U20, U21) are both state and bugs. A
  relation-only IIR should be smaller and correct.
- The kit fixes (K1, K2, K4) make fw-proto-uart usable for any 16550-style
  UART, not only this one.

## 10. Answers (2026-10-21)

All open issues are decided (§8). The FIFO answer changed the design: the
FIFO goes into fw-hdl as `fw_fifo` (§3.4), built when the class model
needs it (step 7). The quirk split of §5 is taken as proposed, as a working
assumption: a row can still move if a test on `ref` shows the U2B0
behaviour differs from what the reference pages say.

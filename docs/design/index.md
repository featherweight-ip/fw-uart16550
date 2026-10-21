# fw-uart16550 design (draft for review)

```{admonition} Draft
:class: warning
Written 2026-10-21 for review (plan step 1). The decisions that still
need an answer are in {ref}`open-issues`. None of this is implemented.
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

A FIFO flush (FCR[1], FCR[2]) is a host write. It must not write the other
side's pointer, so it is a request flag the owning process acknowledges
(set `rd_ptr = wr_ptr` from the side that owns `rd_ptr`, which is the host
for RX and the tx process for TX). This costs a request/ack pair per FIFO.
OI-4 asks whether that is acceptable or whether a flush should be the one
allowed two-writer case, with a stated priority.

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

### 3.4 FIFOs

`fw_channel` cannot be used. The fw-i2c lowering path does not special-case
it, and its `m_q[$]` queue operations are rejected inside a process
(`translate.py:1396`). Unpacked arrays are rejected too (`translate.py:1142`,
ZU1). Packed vectors with run-time indexes do lower (`translate.py:1167-1181,
1462-1474`).

So each FIFO is a small class in this repo, `fw_uart16550_fifo #(W, DEPTH)`:
`bit [DEPTH-1:0][W-1:0] mem`, two pointers one bit wider than the index, and
methods that touch only one side (`push`/`wr_ptr` for the writer,
`head`/`pop`/`rd_ptr` for the reader), so the single-writer rule of §3.2
holds by construction. It lowers to flops plus a read mux, like `raminfr`
on iCE40, which keeps the storage comparison like for like (D4 (a)).

This answers D3 differently from the plan's recommendation (extend
`fw_channel` into `fw_fifo`). `fw_channel` is a Kahn channel by design (no
peek, no count, no flush), and the 16550 needs all three. A library
`fw_fifo` can be promoted from this class once a second design needs it.
ZU1 (unpacked arrays) and ZU2/ZU3 (memory inference, kept leaf) stay step
10 options.

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
latches are removed, which saves area; the flush handshakes of §3.2 and
OI-4 add some. Both are reported in the attribution (plan §6.2).

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
| OI-1 (D3) | FIFO: extend `fw_channel` into `fw_fifo`, or keep the FIFO plain? | **Neither as planned:** `fw_channel` does not lower (§3.4). A packed-storage FIFO class in this repo with single-writer sides; LSR[7] from bad-entry counters; promote to fw-hdl later |
| OI-2 | Which quirks to copy (§5 table) | As the §5 table: copy visible register and pin behaviour (U1–U4, U7, U8, U9, U12, U22, U23, U25), do the 16550 thing for defects with a named rule each. LCR or DL changed mid-character: the kit applies it at the next character (K1); U2B0 applies it at once; rule `lcr_midchar`, tested only under Q5 |
| OI-3 (D4) | FIFO storage comparison basis | (a) flops, like for like, as the headline; (b) block RAM both sides as a measurement (needs a sync-read `raminfr` branch on the fork) |
| OI-4 | FIFO flush when the other side owns the pointer | A request/ack pair (single-writer kept). Alternative: let flush be a two-writer write with stated priority, which the lowering supports with a warning |
| OI-5 | Reset | Synchronous `wb_rst_i` in the model (§3.6) |
| OI-6 (D5) | Where tx error injection lives (K6) | A VIP-only driver core in fw-proto-uart outside `xtor-core` (a txd override mux in the tx xtor wrapper, driven from `xtor_if` tasks) |
| OI-7 (D6) | Modem lines in the VIP | A small modem agent in fwvip-uart (four inputs, two outputs, with an edge monitor). Check fwvip-gpio in step 3 first, and use it if its API fits |
| OI-8 (D7) | `fwvip-example-uart16550` | Leave unused for now |
| OI-9 | K2 shared baud tick: a kit change across all three cores (medium) | Do it in step 2: one divider for both directions is U2B0's structure, and two private dividers would cost about 2 × 16 FF and their counters in the comparison |
| OI-10 | Break while characters are queued (U2B0 sends them invisibly) | The kit tx core holds characters during break (K4); rule `break_queue` |

## 9. Opportunities

- The single-writer FIFO pattern (§3.2) is general. If it lowers well it is
  the shape of `fw_fifo` and a candidate rule for the lowering itself
  (detect a count written by two processes and split it).
- LSR[7] by counters instead of an OR over the FIFO: a relation that is
  cheaper than the reference's state.
- U2B0's interrupt latches (U20, U21) are both state and bugs. A
  relation-only IIR should be smaller and correct.
- The kit fixes (K1, K2, K4) make fw-proto-uart usable for any 16550-style
  UART, not only this one.

## 10. What I need from you

1. OI-1: accept the in-repo packed FIFO class instead of extending
   `fw_channel`.
2. OI-2: confirm the copy / do-not-copy split in §5, in particular U6
   (drop the THRE hold-off) and U14 (drop on overrun).
3. OI-4: request/ack flush, or a two-writer flush.
4. OI-5: synchronous reset.
5. OI-6 to OI-10 (D5–D7, K2, break): accept the proposed answers, or say
   which to change.

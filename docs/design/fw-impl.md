# First fw implementation (steps 6, 7, 8, 9)

Plan and status for getting a working, lowerable fw-uart16550 in place, so
it can be synthesized against the baseline. A fresh session can pick up
from this file. Design: {doc}`index`. Plan: {doc}`plan` (§9).

## Order

The plan has the op-model and equivalence harness (step 5) before the model.
This pass builds the model first and checks it with directed tests on a
`wb` view, as `ref` checks U2B0. Step 5 follows. The `tlm` view needs
fw-proto-uart's TLM link (K7) and comes later too.

## Shape

- `src/rdl/fw_uart16550_regs.rdl`: the U2B0 registers on a 4-byte stride,
  in two maps (DLAB = 0 view, DLAB = 1 bank). Two generated packages:
  `fw_uart16550_reg_pkg`, `fw_uart16550_dlab_reg_pkg`.
- `fw_fifo #(T, DEPTH)` in fw-hdl `src/std/` (design §3.4).
- `src/spl/`: the class model `fw_uart16550`. Host port (`wb_proto_if`),
  `access()` with the DLAB decode and the read side effects, the TX and RX
  FIFOs, a tx process, an rx sink, timeout and modem processes, and IIR and
  LSR as relations. It reaches the pins through one design-local interface,
  `fw_uart16550_xtor_if`: the kit cores' req/rsp channels, the configuration
  levels, loopback, modem pads and the irq level.
- `src/spl-rtl/fw_uart16550_top.sv`: the pin top (the pins of
  `oc_uart16550_wb32`), as `fw_i2c_top`: the fw-proto-wb target xtor, the
  kit's baud, tx and rx cores (one shared baud tick), the srx synchronizer,
  the xtor interface, and `fw_root`. It simulates (`wb` view) and lowers
  (`lowered`, module `fw_uart16550_spl`; `rtl` view).
- `tests/uvm/tb/`: the arm parts (pads interface, b2b driver) split out of
  `oc_uart16550_ref_arm.sv`, plus `fw_uart16550_wb_arm.sv` and the `wb` tops.

### Single-writer state (design §3.2), as built

| State | Writer |
|---|---|
| TX FIFO `wr_ptr`, entries | host (THR write) |
| TX FIFO `rd_ptr` | tx process; host on TX flush (host wins) |
| RX FIFO `wr_ptr`, entries, `rx_bad_wr`, `oe_set` | rx sink |
| RX FIFO `rd_ptr`, `rx_bad_rd`, `oe_ack`, `head_ack` | host |
| `thre_masked` (IIR read of THRE until the next THR write or TX flush) | host |
| MSR delta `set` toggles, previous pads | modem process |
| MSR delta `ack` toggles | host (MSR read) |
| timeout counter | timeout process |

## Sub-steps

| # | What | Status |
|---|---|---|
| 6 | RDL map, `reg-model`; FWH-SIDEEFFECT warnings only for RBR, THR, IIR.IID, DLL (the model handles them) | done 2026-10-24 |
| 7a | Lowering available locally: fw-i2c's unpushed fw-hdl and zuspec-synth commits merged into `packages/` (branch `uart16550-dev` in fw-hdl) | done 2026-10-24 |
| 7b | `fw_fifo` in fw-hdl, with a unit test | done 2026-10-24 (fw-hdl `uart16550-dev` 3fee8db, `tests/fifo`; local, not pushed) |
| 7c | Class model `src/spl/` | done 2026-10-24 |
| 8a | Pin top, xtor interface, `wb` arm and tops; `wb-smoke` passes | done 2026-10-24. The arm is now `uart16550_arm` with `dut_*` ports; the HDL top instances the DUT |
| 8b | Universal directed tests on `ref` and `wb` | done 2026-10-24: `regs`, `line` (framings at div 1–3, loopback), `status` (PE, FE, BI, overrun), `irq` (THRE, RDA, TI, RLS, MS) pass on both; the `ref` confirmation tests still pass |
| 9a | `lowered` and `rtl` view; `rtl-smoke` and the directed tests pass | done 2026-10-24: the five shared tests pass on `rtl`. Needed a lowering fix (partial nonblocking writes, fw-hdl `translate.py`) and `python-sat` in the venv |
| 9b | Synthesis of the lowered netlist (fw-i2c `synth-lowered.sh`), against the baseline; `docs/results.md` | done 2026-10-24: 774 LUT4 / 526 FF / 92 CARRY against U2B0's 826 / 564 / 80 (Yosys 0.70). {doc}`../results` |

## Status notes

- **Lowering and fw-hdl changes pushed 2026-10-24**: fw-hdl main 176f939
  (the lowering from fw-i2c, `fw_fifo`, the partial-NBA fix) and
  zuspec-synth main bc0a7cb. fw-i2c re-lowered with the fix: the same 500
  register bits, and outputs equal to its old netlist by a 25-clock bounded
  proof from reset. fw-hdl's Python unit tests: 34 failures before and
  after, the same set. `python-sat` is still installed by hand into
  `packages/python` (seqcorr needs it; fw-i2c's venv has 1.9.dev17).
- **Re-running the lowering after a change to the lowering's Python**:
  dfm does not see it as an input. Use `dfm run lowered -f`.
- **Area lessons** (results): index `fw_fifo` storage only through constant
  indices; give each FIFO head one read site per process (a `wait` that is
  already true costs no clock, so the lowering inlines the code after it
  into every state that reaches it).
- **MSR deltas from the first clock.** A one-shot flag was removed as a
  lowering workaround ({doc}`../results`), so a modem pad that is 1 out of
  reset sets its delta. U2B0 clears them on the first clock.
- **Baud restart (U24, rule `dlm_restart`).** The kit baud core has no
  restart input, so a DL write takes effect at the next tick, as the core
  says. The design wanted any DL write to restart the divider. Not done in
  this pass.

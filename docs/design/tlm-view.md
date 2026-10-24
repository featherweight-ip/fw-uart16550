# The `tlm` view (plan and status)

The UVM bench runs against the class model's method ports, with no pins and
no signal-level transactors. A fresh session can pick up from this file.
Design: {doc}`index` (§3); plan: {doc}`plan` (§5, K7).

## Shape

- **Register port.** The view's root component has a port,
  `fw_port #(wb_proto_if #(32, 32)) rf`, connected to the model's `host`
  export. `uart_tlm_model::rf_if()` gives the bench an adapter that calls
  `rf.t.access()`, so a test's `reg_write()`/`reg_read()` calls
  `fw_uart16550_host::access()`, and from it `fw_uart16550::host_access()`,
  directly. No WISHBONE cycle and no target transactor. An access still
  takes the bus's three clocks (aligned to an edge, then two more): LSR and
  IIR are registered, which is only correct while accesses are that far
  apart (`fw_uart16550_tlm_rf`).
- **Serial lines** (`uart_tlm_line`, one per direction). A character is a
  method call, timed in clocks from the framing:
  - `send()` waits until the line is free and not in break, then takes the
    character on the next clock, as the kit tx core's `req_ready` does;
  - the line stays busy for the frame (`char_clocks()`);
  - each receiver gets the character half a bit into the first stop bit,
    as the kit rx core samples it, with its data masked to the receiver's
    word length and status `{OE, BI, FE, PE}`;
  - a break of at least a frame gives one `(0, BI)` character, and a
    character the break started under is lost, as in the kit cores.
- **Who is on each line.**
  - `stx` (the model's `tx` port): the VIP rx agent and the `stx` monitor.
  - `srx` (the VIP tx agent): the model's `rx_sink` and the `srx` monitor.
  - In loopback (MCR.LOOP) the model's transmitter feeds its own
    `rx_sink`, and `stx` carries nothing, as `fw_uart16550_top` wires it.
- **The VIP, unchanged.**
  - The tx agent gets `fwvip_uart_tlm_tx_config`, a subclass of
    `fwvip_uart_tx_config` that sends on the `srx` line.
  - The rx and monitor agents get the base configs, which are already
    sinks that need no transactor.
- **Pins as methods.** The model's `pins` port is a class:
  - modem pads from `set_modem()`;
  - MCR, with RTS and DTR going to `modem_out()`;
  - the interrupt goes to `irq_changed()`;
  - `tx_busy()` reads the `stx` line;
  - `baud_tick()` is computed from the time when it is read, one tick
    every `divisor` clocks as `uart_baud_xtor_core`, so it costs no
    process.
- **The clock.** The model's processes still run on the clock: the root's
  domain is the HDL top's `fw_clock_xtor_if`.
- **Not modelled.**
  - Glitches have no meaning at TLM: `send_err()` with `glitch_len > 0`
    and `glitch()` are errors.
  - `baud_ppm` is ignored.
  - A receiver set to a different framing than the sender gets the
    sender's character masked to its word length; there is no bit-level
    misframing.

  The universal tests use none of these; the ref-only tests that do are
  not run on `tlm`.
- **Files.**
  - `tests/uvm/tb/fw_uart16550_tlm_view_pkg.sv`, `hdl_top_tlm.sv`,
    `hvl_top_tlm.sv`.
  - `tlm` in the `view_tb`, `view_top` and `images` values (`flow.yaml`).
  - `view-src-tlm` (`tests/uvm/flow.yaml`).

The line is written against the kit's APIs plus the fwvip configs. A
kit-only `uart_tlm_link` in fw-proto-uart (K7) can take its core later.

## Steps

| # | What | Status |
|---|---|---|
| V1 | View package: root (`rf` port, lines, pins, baud), the model, the TLM tx config | done 2026-10-24 |
| V2 | Tops and flow; `tlm-smoke` passes | done 2026-10-24. `uart_ref_pads_if` moved to its own file (the env names it; `tlm` has no arm) |
| V3 | The universal tests (`regs`, `line`, `status`, `irq`) and `stream` on `tlm` | done 2026-10-24: all pass, and on ref, wb and rtl. The LSR[7] mutation is caught on `tlm` (status) |
| V4 | `scripts/sim-perf.py --views tlm,wb,rtl,ref`; `docs/results.md`; docs (`api/testbench.rst`) | done 2026-10-24: `tlm` 218 kclk/s, between `wb` (150) and `rtl` (235) |

## Status notes

- **Two contracts the view had to keep** (found by failing tests):
  - Register accesses take the bus's three clocks (above).
  - The VIP's `send_err()` returns when the frame is off the line, while
    `send()` returns once the character is queued. The driver times its
    idle wait from that.
- **What the `tlm` image contains.** Instanced: `hdl_top_tlm`, which is a
  clock, a reset, `fw_clock_xtor_if` and fwvip's clock and reset
  interfaces. Compiled but not instanced: the kit transactor interfaces,
  because fwvip's config classes declare virtual handles of those types.
  The kit RTL files also come in through `uvm-env`'s needs. Verilator does
  not build unused modules.
- **Why `tlm` is not faster than `rtl`** (perf, `stream`; docs/results.md):
  the model is clock-driven and Verilator's `--timing` scheduler dominates.
  - `status_proc` resumes on every clock.
  - `tx_proc`'s `wait (txf.wr_ptr != txf.rd_ptr)` is a dynamic trigger
    that is re-evaluated at every evaluation.
  - UVM's own `uvm_objection::wait_for` costs about 20% in every view.
  - `tick(n)` resumes on every one of its n edges. Jumping over them (a
    local experiment in fw-hdl's and fwvip-core's clock interfaces,
    reverted) gave +11%.
- **`tx_proc` polls instead of `wait (expr)`** (2026-10-24). Measured in a
  Verilator 5.052 microbenchmark: one waiter, 2 M clocks, woken every 100
  clocks, against a 1.38 s baseline. Extra time by how it waits:

  | Wait | Extra time |
  |---|---|
  | `wait (o.wr != o.rd)` | +0.41 s |
  | `semaphore` | +0.44 s |
  | `mailbox` | +0.44 s |
  | `@(event)` | +0.05 s |
  | a check every clock | +0.12 s |

  Verilator's semaphore and mailbox are themselves built on `wait (expr)`
  (`verilated_std.sv`), and the lowering rejects event waits in a
  process. So the model now polls the TX FIFO once a clock
  (`while (empty) tick()`), which is what the lowered process does anyway.
  - `tlm`: 218 to 234 kclk/s. `wb`: +2%.
  - Area and Fmax within noise: 764 LUT4, 552 FF, 39.2–41.0 MHz on 6 seeds
    (from 760, 553, 39.5–41.7).
  - All universal tests pass on tlm, wb and rtl.

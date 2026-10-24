# Step 4: the `ref` view and the reference confirmation tests

Plan and status for step 4 of {doc}`plan` (§9). A fresh session can pick up
from this file. Methods per item: {doc}`../reference/verification`. Quirk
definitions: {doc}`../reference/deviations`.

## Shape (as fw-i2c, without the op-model)

fw-i2c's env programs the device through the PSS op-model. That is step 5
here, so step 4 builds the surface the op-model will sit on, and the tests
use the register port directly:

- `tests/uvm/tb/oc_uart16550_ref_arm.sv`: the shim
  (`src/ref/oc_uart16550_wb32.sv`), a fw-proto-wb initiator transactor on
  its bus, the fw-proto-uart transactors on the serial pins (tx into
  `srx`, rx and a monitor on `stx`, a monitor on `srx`), plain bench
  drivers for the modem input pads, and a raw WISHBONE driver for U13
  (the initiator transactor always leaves an idle clock).
- `tests/uvm/env/uart_model_base.svh`: what tests see of a design. It has
  `rf_if()` (the register port), an irq seam, and the modem pads. The
  serial side is the fwvip-uart agents, which the env builds.
- `uart_ref_model.svh`: the reference arm behind that surface.
  `uart_ref_probe.svh`: the core's internals each clock (register strobes,
  `rf_count`, `tf_count`, pending flags, `block_cnt`, `enable`), for tests
  that place an access relative to a push or a pop.
- `fw_uart16550_env`: the fwvip-uart tx, rx and two monitor agents, and the
  model. `fw_uart16550_base_test`: register helpers (by name, DLAB-aware),
  line setup on both sides, and checks.
- Host bus: fw-proto-wb's initiator through its bridge, as fw-i2c does.
  fwvip-wb's UVM agent is not needed.
- Modem pins: plain `logic` pads driven from the HVL side through the
  model, not fw-proto-gpio. It is four inputs and two outputs, and a
  confirmation test needs to place a pad change on a given clock (U9),
  which a GPIO transactor's latency would blur. This replaces the step-3
  note on D6.

## Sub-steps

| # | What | Status |
|---|---|---|
| 4a | Repo setup: `ivpm.yaml` (use / dev sets), root `flow.yaml` (project.dv.uvm, views = [ref]), `.envrc`, `.gitignore`; `lint-rtl` with `lint-waivers.yaml`, zero findings | done 2026-10-24 |
| 4b | Arm, tops, env, probe, base test; `smoke` (init, send and receive 8N1 both ways) and `reg` (U1, U2, U3, U25) pass | done 2026-10-24 |
| 4c | Confirmation tests, one per item, U1–U26 except U10 (step 11) | done 2026-10-24 |
| 4d | Results into `deviations.md` (status column and findings), `verification.md`, `timing.md` "to confirm" marks; plan §9 | done 2026-10-24 |

## Status notes

**Step 4 done 2026-10-24.** `dfm run tests`: 9 cases pass (`ref-smoke`
and eight `ref-*` confirmation tests). `dfm run lint-rtl`: 0 new findings in
both configurations (22 and 16 waived; each waiver is pinned to its line,
so a waiver for one configuration shows as unused in the other).
Results: {doc}`../reference/verification`.

Things a later session needs to know:

- **Verilator and fork.** A `fork ... join_any` branch gets copies of the
  caller's automatic variables, so a result set in a branch never reaches
  the caller. `rx_get()` polls instead. Use class members, not locals, for
  anything a forked branch writes (`track()` does).
- **The probe lags by a clock.** A sample holds the values from the clock
  before the edge it was taken at. After a `reg_write`, wait 2 clocks before
  checking a count the write changes.
- **The lint task does not rerun when only `lint-waivers.yaml` changes**
  (the file is not a task input). Use `dfm run lint-rtl -f`.
- **Races are found, not computed.** U16, U17, U20 and U26 sweep an access
  over clock offsets from a probe trigger and use the probe to see which
  offset hit, so they do not depend on the bus latency.
- **Measured timing:** WB writes are slow enough that 17 THR writes take
  longer than one 8N1 character at divisor 2 (U15 uses divisor 16). A DLL
  write's first tick is DL + 2 clocks after the strobe.
- **Teeth:** four mutations of the reference RTL were each caught by
  exactly the intended test ({doc}`../reference/verification`). Use the same
  approach (patch `packages/oc-uart16550`, run, restore with git) to check
  new tests.

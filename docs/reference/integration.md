# Integration: fork, patch set and 32-bit shim

`fw-uart16550` uses the core in the form described here: U2B0 with a small
patch set that changes no behaviour, compiled with `DATA_BUS_WIDTH_8`,
behind a 32-bit WISHBONE shim. This combination is the reference arm of
the comparison (plan decision D2). It is integrated as `oc-i2c` is in
fw-i2c, with two differences: the 16550 has read side effects, and its
configuration is by `` `define ``. Decided 2026-10-20 ({doc}`../design/plan`
§2.1).

## Source: featherweight-ip/oc-uart16550

The core comes from `featherweight-ip/oc-uart16550` on the local Forgejo
(`ssh://git@a9550.perch-char.ts.net:222/featherweight-ip/oc-uart16550.git`),
a fork of the freecores mirror (`master` tracks freecores). The working
clone is `../oc-uart16550`.

| Ref | Commit | Content |
|---|---|---|
| tag `u2b0` | `2b0ad80` | Upstream master HEAD (2004-11-22), unmodified: the baseline |
| branch `fw-u2b0`, tag `u2b0-fw1` | `ef67d27` | The `fw` patch set below, on `u2b0` |

| Change (`ef67d27`) | Check |
|---|---|
| Remove the 348 `#1` delays (`uart_regs` 117, `uart_receiver` 74, `uart_transmitter` 57, `uart_rfifo` 50, `uart_wb` 35, `uart_tfifo` 15) and the 5 `#Tp` delays and the unused `Tp` parameter of `uart_sync_flops`. All were on non-blocking assignments | Yosys `equiv_make`/`equiv_simple`/`equiv_induct` against `u2b0` proves all points in both configurations (1362 points 32-bit, 1069 `DATA_BUS_WIDTH_8`) |
| Remove `` `include "timescale.v" `` from the 9 files that had it. `timescale.v` is kept: the bench uses it | `synth_ice40 -device u` gives identical cell counts in both configurations |
| Add an include guard to `uart_defines.v`, which every file includes | Upstream bench: the same report as `u2b0` (U11) |

Everything else lint finds is **waived** in `lint-waivers.yaml` (not yet written), not
patched: a logically identical rewrite can still move the Yosys area (as
the WIDTHTRUNC waiver in fw-i2c). Every patch must pass both checks above.

Bug fixes (U13–U26 and the rest of {doc}`deviations`) are deliberately
**not** in the patch set. The line numbers in this specification are
those of `u2b0`; the patch set removes lines, so `u2b0-fw1` line numbers
differ.

## Configuration

By `+define+` on the compile, never by editing `uart_defines.v`.
`DATA_BUS_WIDTH_8`, `LITLE_ENDIAN` and `UART_HAS_BAUDRATE_OUTPUT` are all
commented out there and tested only with `` `ifdef `` ({doc}`interface`). A
`` `define `` applies to a whole compile, so each configuration is its own
fileset and image:

| Fileset | Defines | Bus | Use |
|---|---|---|---|
| `ref-rtl` | `DATA_BUS_WIDTH_8` | 8-bit core + shim, 32-bit | Headline reference (D2) |
| `ref-rtl-32` | none | native 32-bit, big-endian, debug registers; no shim | Step 11 |

## ivpm

In the `dev` package set:

```yaml
- name: oc-uart16550
  url: ssh://git@a9550.perch-char.ts.net:222/featherweight-ip/oc-uart16550.git
  tag: u2b0-fw1
  deps: skip
```

## The 32-bit WISHBONE shim

`src/ref/oc_uart16550_wb32.sv` gives the 8-bit core the fw-XXX bus
convention: a 32-bit data bus with one register per 32-bit word, only the
low byte valid. Its ports are listed in {doc}`interface`.

- Register *n* is at byte address 4·*n*: the core sees `wb_adr_i[4:2]`, and
  `wb_adr_i[1:0]` are ignored.
- Reads return `{24'b0, register}`. Writes take `wb_dat_i[7:0]`.
- `wb_sel_i` is **ignored**. This differs from `oc_i2c_wb32`, which turns a
  write without lane 0 into a read. That is safe for i2c only because its
  reads have no side effects. Here RBR, IIR, LSR and MSR reads change state,
  and gating an access would need an ack flop in front of the reference. A
  driver with `reg-io-width = 4` always sets all lanes. This is recorded as
  a shim deviation; the fw model does the same.
- `wb_rst_i` (the core's asynchronous active-high reset), the core's own
  WISHBONE timing (registered inputs, ack in the third clock, one idle
  clock needed between accesses: U13), `int_o`, `stx`/`srx` and the modem
  pins pass straight through. `wb_err_o` is 0.
- No logic. `scripts/synth-baseline.sh` checks that the shim top costs 0
  LUT4 over `uart_top`.
- Without `DATA_BUS_WIDTH_8` the shim fails elaboration (it instantiates a
  module that does not exist).

### Register map through the shim

| Byte address | DLAB = 0 write | DLAB = 0 read | DLAB = 1 |
|---|---|---|---|
| 0x00 | THR | RBR | DLL |
| 0x04 | IER | IER | DLM |
| 0x08 | FCR | IIR | (same) |
| 0x0C | LCR | LCR | (same) |
| 0x10 | MCR | 0 | (same) |
| 0x14 | — | LSR | (same, no clear) |
| 0x18 | — | MSR | (same, no clear) |
| 0x1C | SCR | SCR | (same) |

This is the layout Linux's `8250_of` driver uses with `reg-shift = <2>` and
`reg-io-width = <4>`.

## Lint

Lint top `oc_uart16550_wb32` with `DATA_BUS_WIDTH_8`, and `uart_top` in the
32-bit configuration. Waivers go in `lint-waivers.yaml` (to be added with the lint task).

## Upstream bench

Run once in step 0 under Icarus by `scripts/upstream-bench.sh`; the
result is U11 in {doc}`deviations`. It is not wired into the dfm flow: the
UVM `ref` view replaces it ({doc}`verification`).

# OpenCores uart16550 (U2B0) reference specification

This part describes what the OpenCores uart16550 core **actually
provides**, taken from its Verilog RTL at the one revision `fw-uart16550`
uses as its reference. It replaces the 2002 OpenCores PDF (rev 0.6, in the
fork's `doc/UART_spec.pdf`) as the reference for `fw-uart16550`. The PDF is
out of date or wrong in several places.

| | |
|---|---|
| Source | <https://github.com/freecores/uart16550> |
| Revision described | **U2B0**: commit `2b0ad80` (2004-11-22, Igor Mohor), "Timeout interrupt should be generated only when there is at least one character in the fifo": tag `rel_4` plus one fix, the last RTL change. Used from the `featherweight-ip/oc-uart16550` fork (tag `u2b0`), with a patch set that changes no behaviour (tag `u2b0-fw1`); see {doc}`integration`. |
| RTL | `rtl/verilog/uart_top.v` (340 lines), `uart_wb.v` (317), `uart_regs.v` (893), `uart_transmitter.v` (351), `uart_tfifo.v` (243), `uart_receiver.v` (482), `uart_rfifo.v` (320), `raminfr.v` (111), `uart_sync_flops.v` (122), `uart_debug_if.v` (126), `uart_defines.v` (247), `timescale.v` (64) |
| Register model | `src/rdl/u2b0_uart16550.rdl` and `src/rdl/u2b0_regs.rdl` (SystemRDL, written for this specification) |
| License | GNU LGPL 2.1 or later (notice in each RTL file) |

```{admonition} Conventions
:class: note
- "The core" or "U2B0" means the RTL at `2b0ad80`.
- "The PDF" means the OpenCores *UART IP Core Specification*, Rev 0.6,
  2002-08-11 (J. Gorban).
- "NS16550A" means the National Semiconductor part the core is meant to
  be compatible with.
- File:line references are to the RTL at tag `u2b0` (in
  `../oc-uart16550`: `git show u2b0:rtl/verilog/<file>`). The `u2b0-fw1`
  patch set removes lines, so its line numbers differ.
- "Tick" means one pulse of the baud generator's clock enable (`enable`
  in `uart_regs.v`), which occurs every DL cycles of `wb_clk_i`, at 16
  times the baud rate.
- The headline configuration is `DATA_BUS_WIDTH_8` behind the 32-bit shim
  ({doc}`integration`). The native 32-bit configuration is described where
  it differs.
- Statements marked **(to confirm)** come from reading the RTL and still
  need a simulation to confirm them. The plan to do this is in
  {doc}`verification`. Quirk and defect IDs (U1, U2, ...) are listed in
  {doc}`deviations`.
```

```{toctree}
:maxdepth: 2

overview
interface
registers
operation
timing
architecture
programming
verification
deviations
synthesis
integration
```

# Interface

Top-level module: `uart_top` (`uart_top.v:140-156`). `fw-uart16550` uses it
through the shim `oc_uart16550_wb32` (below and {doc}`integration`).

## Configuration

The core has no useful parameters. `uart_top` declares `uart_data_width`
and `uart_addr_width` (`uart_top.v:158-159`), but `uart_wb` and
`uart_regs` take their widths from the defines, so overriding the
parameters breaks the core. Configuration is by `` `define ``, all
commented out in `uart_defines.v` and tested only with `` `ifdef ``:

| Define | Default | Effect |
|---|---|---|
| `DATA_BUS_WIDTH_8` | off | On: 8-bit data bus, 3-bit address, no debug interface. Off: 32-bit data bus, 5-bit address, byte lane from `wb_sel_i`, debug registers at 8 and 12 (`uart_defines.v:137-143`) |
| `LITLE_ENDIAN` (sic) | off | 32-bit mode only: byte lane order. Off: big-endian, `wb_sel_i[3]` selects register 0 of a word. On: `wb_sel_i[0]` does (`uart_wb.v:284-300`) |
| `UART_HAS_BAUDRATE_OUTPUT` | off | Adds output `baud_o`, the 16x tick (`uart_regs.v:288-290`) |

The FIFO depth (16) and widths are fixed defines (`uart_defines.v:230-235`).
`fw-uart16550` sets defines with `+define+` on the compile, never by
editing `uart_defines.v`.

## Ports

### System and WISHBONE

| Port | Dir | 8-bit config | 32-bit config | Description |
|---|---|---|---|---|
| `wb_clk_i` | in | 1 | 1 | The only clock. Bit timing is derived from it. |
| `wb_rst_i` | in | 1 | 1 | **Asynchronous** reset, active high. Resets every flop except the two 16×8 FIFO RAM arrays (`raminfr.v:97-107`). |
| `wb_adr_i` | in | 3 | 5 | Register address. In 32-bit mode bits [1:0] are ignored; the byte comes from `wb_sel_i`. |
| `wb_dat_i` | in | 8 | 32 | Write data. |
| `wb_dat_o` | out | 8 | 32 | Read data, registered. |
| `wb_sel_i` | in | 4 | 4 | 32-bit mode: byte lane select (U10). 8-bit mode: present but unused; `uart_top` passes `4'b0` to `uart_wb` (`uart_top.v:236`). |
| `wb_we_i` | in | 1 | 1 | Write enable. |
| `wb_stb_i` | in | 1 | 1 | Strobe. |
| `wb_cyc_i` | in | 1 | 1 | Cycle. |
| `wb_ack_o` | out | 1 | 1 | Acknowledge, registered. |
| `int_o` | out | 1 | 1 | Interrupt request: active high, level, registered (`uart_regs.v:841-853`). |
| `baud_o` | out | 1 | 1 | Only with `UART_HAS_BAUDRATE_OUTPUT`: one-clock pulse per tick (16x baud), not a clock. |

The core has no `wb_err_o`, `wb_rty_o` or stall signal.

### Serial and modem pads

| Port | Dir | Description |
|---|---|---|
| `stx_pad_o` | out | Serial output. 1 when idle, 0 while LCR.BC = 1, 1 in loopback. |
| `srx_pad_i` | in | Serial input. Synchronized with two flops (reset value 1) (`uart_regs.v:382-392`). Ignored in loopback. |
| `rts_pad_o` | out | MCR.RTS, not inverted (U23). Still driven in loopback (U8). |
| `dtr_pad_o` | out | MCR.DTR, not inverted (U23). Still driven in loopback (U8). |
| `cts_pad_i` | in | Read as MSR.CTS, not inverted (U23). Not synchronized (U9). |
| `dsr_pad_i` | in | MSR.DSR. Same. |
| `ri_pad_i` | in | MSR.RI. Same. |
| `dcd_pad_i` | in | MSR.DCD. Same. |

All modem signals are active high in the core: 1 on a pin means the
signal is asserted. The PDF describes the NS16550A's active-low pins. A
board with an RS-232 transceiver (which inverts) needs one more inversion
to match an NS16550A. There are no OUT1 or OUT2 pins.

## The 32-bit shim (headline configuration)

`src/ref/oc_uart16550_wb32.sv` wraps `uart_top` compiled with
`DATA_BUS_WIDTH_8` and gives it the fw-XXX bus convention: a 32-bit data bus,
one register per 32-bit word. It adds no logic.

| Shim port | Width | Behaviour |
|---|---|---|
| `wb_adr_i` | 5 | Byte address. The core sees `wb_adr_i[4:2]`: register *n* is at byte address 4·*n*. Bits [1:0] are ignored. |
| `wb_dat_i` | 32 | Bits [7:0] go to the core; [31:8] are ignored. |
| `wb_dat_o` | 32 | `{24'b0, register}`. |
| `wb_sel_i` | 4 | **Ignored.** A write without lane 0 is still a write, and every read has its side effects. |
| `wb_err_o` | 1 | Constant 0. |
| `wb_rst_i`, `wb_we_i`, `wb_stb_i`, `wb_cyc_i`, `wb_ack_o`, `int_o`, pads | | Passed through, with the core's timing. |

The shim fails elaboration without `DATA_BUS_WIDTH_8`. It has no
`baud_o`. This layout is Linux `8250_of` with `reg-shift = <2>` and
`reg-io-width = <4>`.

## The native 32-bit configuration

Without `DATA_BUS_WIDTH_8` the core decodes the byte lane itself
(`uart_wb.v:257-303`). The internal 5-bit register address is
`{wb_adr_i[4:2], lsb}`, where `lsb` comes from `wb_sel_i`:

| `wb_sel_i` | lsb (default, big-endian) | lsb (`LITLE_ENDIAN`) | Write data used | Read data placed |
|---|---|---|---|---|
| `4'b0001` | 3 | 0 | `[7:0]` | `{24'b0, r}` |
| `4'b0010` | 2 | 1 | `[15:8]` | `{16'b0, r, 8'b0}` |
| `4'b0100` | 1 | 2 | `[23:16]` | `{8'b0, r, 16'b0}` |
| `4'b1000` | 0 | 3 | `[31:24]` | `{r, 24'b0}` |
| `4'b1111` | 0 | 0 | `[7:0]` | the debug word (0 except at 8 and 12) |
| anything else | 0 | 0 | `[7:0]` | 0 |

So with the default big-endian order, register 0 (RBR/THR) is
`wb_sel_i = 4'b1000`, data `[31:24]`, at byte address 0. Every access with
`wb_sel_i` not one-hot still reaches register `{wb_adr_i[4:2], 2'b00}`,
including its side effects: a `4'b1111` or `4'b0000` read at address 0
pops the RX FIFO and returns 0 or the debug word. A `4'b1111` write goes to
register `{wb_adr_i[4:2], 2'b00}` with data `[7:0]` (U10). Only reads
update `wb_dat_o` in this mode (`uart_wb.v:262`).

The debug registers are described in {doc}`registers`.

## WISHBONE timing

The core registers every WISHBONE input (adr, dat, we, cyc, stb, sel) on
every clock (`uart_wb.v:228-243`) and works from the registered copies. A
2-bit FSM makes the acknowledge (`uart_wb.v:193-225`):

- Clock 1: the master drives the cycle; the core registers it at the
  end of the clock.
- Clock 2: the registered strobe is seen with the FSM idle and its flag
  `wre` set, so the register strobe (`we_o` or `re_o`) is high for this one
  clock. At the end of the clock the register is written (or the read
  side effect starts), the read data is registered, and `wb_ack_o` is
  set.
- Clock 3: `wb_ack_o` is high. The master ends the cycle.
- The FSM then spends one more clock (state 2) before it returns to
  idle, and it sets `wre` again only after a clock in idle with no
  registered strobe.

```{wavedrom}
{ "signal": [
  { "name": "wb_clk_i",         "wave": "p........" },
  { "name": "wb_cyc_i/stb_i",   "wave": "01..01..0" },
  { "name": "wb_we_i",          "wave": "x1..x0..x" },
  { "name": "wb_adr_i",         "wave": "x=..x=..x", "data": ["SCR", "SCR"] },
  { "name": "stb (registered)", "wave": "0.1..01.." },
  { "name": "we_o / re_o",      "wave": "0.10..10." },
  { "name": "wb_ack_o",         "wave": "0..10..10" },
  { "name": "wb_dat_o",         "wave": "x......=x", "data": ["d"] },
  { "name": "SCR",              "wave": "x..=.....", "data": ["d"] }
],
  "head": { "text": "WISHBONE write, one idle clock, then a read (3 clocks per access + 1 idle)" }
}
```

Notes (U13 confirmed on the `ref` view; the clock counts still **(to confirm)**):

- An access takes 3 clocks, with `wb_ack_o` in the third. The master
  must leave **at least one idle clock** (STB low) between accesses. An
  access that starts in the clock straight after the previous ack is
  acknowledged, but the FSM comes back to idle with `wre` clear, so no
  register strobe is made: a write is lost and a read has no side effect
  (U13). The fastest sequence is one access per 4 clocks.
- `wb_ack_o` follows the *registered* strobe, so it is not gated by the
  live `wb_cyc_i`: a cycle the master drops early is still acknowledged
  one clock later.
- 8-bit mode: `wb_dat_o` is registered from the read mux on every clock,
  whether or not a cycle is active (`uart_wb.v:246-250`). 32-bit mode:
  only on a read strobe (`uart_wb.v:259-270`).
- Read side effects take place at or after the edge that raises
  `wb_ack_o`, so the value read is always the value before the side
  effect: RBR pops one clock later (`uart_regs.v:421-431`), the LSR
  clear is in the strobe clock (`uart_regs.v:439-455`), the MSR clear is
  one clock later (`uart_regs.v:458-468`, 582).
- A THR write reaches the TX FIFO one clock after the strobe
  (`uart_regs.v:533-557`), with the registered write data, which is still
  valid then.

## Clocking and reset

- There is one clock domain. The baud generator divides `wb_clk_i` by
  DL into a one-clock tick at 16x the baud rate ({doc}`timing`).
- `srx_pad_i` passes two flops before use. The four modem inputs go
  straight into the MSR flops and the delta logic (U9).
- `wb_rst_i` is asynchronous and active high, everywhere. After reset:
  LCR = 0x03, DL = 0 (no ticks), IER = 0, FCR trigger = 14, MCR = 0, SCR = 0,
  IIR = 0xC1, LSR = 0x60, MSR = 0x00 (bits 7:4 follow the pads from the
  first clock). The FIFO RAM arrays are not reset; their error flags and
  pointers are.
- At `u2b0` every RTL file includes `timescale.v` and most non-blocking
  assignments carry `#1`. The `u2b0-fw1` patch set removes both
  ({doc}`integration`).
- `uart_top` prints its configuration from an `initial` block
  (`uart_top.v:324-336`).

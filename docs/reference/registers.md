# Registers

The register map is described in SystemRDL in `src/rdl/u2b0_uart16550.rdl`
(the address maps) and `src/rdl/u2b0_regs.rdl` (the registers, shared with
the `fw-uart16550` map of step 6). The tables at the end of this page are
generated from it by `sphinx-peakrdl`. The read mux is `uart_regs.v:404-417`;
the writes are `uart_regs.v:475-557`.

## Summary

The 8-bit core addresses registers by byte (`wb_adr_i[2:0]`). Through the
32-bit shim that `fw-uart16550` uses, register *n* is at byte address 4·*n*
({doc}`integration`).

| Core offset | Shim address | DLAB | Write | Read | Reset (read) | Notes |
|---|---|---|---|---|---|---|
| 0x0 | 0x00 | 0 | THR | RBR | — | Split. RBR read pops the RX FIFO. THR write pushes the TX FIFO |
| 0x0 | 0x00 | 1 | DLL | DLL | 0x00 | A DLL write restarts the baud divider (U24) |
| 0x1 | 0x04 | 0 | IER | IER | 0x00 | Bits 7:4 read 0 |
| 0x1 | 0x04 | 1 | DLM | DLM | 0x00 | |
| 0x2 | 0x08 | any | FCR | IIR | 0xC1 | Split. FCR is written in either DLAB state. FCR reset value 0xC0 (trigger 14). IIR read clears a THRE interrupt it shows |
| 0x3 | 0x0C | any | LCR | LCR | 0x03 | |
| 0x4 | 0x10 | any | MCR | 0x00 | 0x00 | MCR is write-only (U1) |
| 0x5 | 0x14 | any | — (ignored) | LSR | 0x60 | Read clears OE, PE, FE, BI, bit 7 |
| 0x6 | 0x18 | any | — (ignored) | MSR | 0x00 | Read clears bits 3:0 |
| 0x7 | 0x1C | any | SCR | SCR | 0x00 | Not in the PDF (U2) |

Read side effects (RBR pop, IIR THRE clear, LSR clear, MSR clear) happen
only with LCR.DLAB = 0 (`uart_regs.v:439-443`). With DLAB = 1, IIR, LSR and
MSR read normally but clear nothing (U25).

Offsets 5 and 6 ignore writes: the write decode has no entry for them.
In the 32-bit configuration, internal addresses 8 to 31 read 0 through the
8-bit path and ignore writes; see the debug registers below.

## DLAB banking in the RDL

SystemRDL cannot switch a bank on a field value, and it rejects a
read-write register (DLL) at the same address as RBR and THR. (It accepts
one read-only and one write-only register at one address, which is how
offsets 0, 2 and 4 are split.) So the RDL has two address maps:

| Address map | LCR.DLAB | Contents |
|---|---|---|
| `u2b0_uart16550` | 0 | All eight offsets: RBR/THR, IER, IIR/FCR, LCR, MCR (+ its read-0 view `MCR_RD`), LSR, MSR, SCR |
| `u2b0_uart16550_dlab` | 1 | DLL at 0 and DLM at 1 only. Offsets 2 to 7 are the same registers as in `u2b0_uart16550`, without read side effects (U25) |

`u2b0_regs.rdl` is included once per map. It emits the DLAB = 1 bank when
the macro `U2B0_DLAB` is defined, and the DLAB = 0 registers otherwise. The
including map defines `U2B0_STRIDE` (1 here; 4 for the fw map).

## Things the RDL can only partly express

- **Read side effects that act elsewhere.** An RBR read pops the RX FIFO
  one clock later. An IIR read clears the THRE pending flag only when the
  value read is THRE (0xC2). These are given as `swacc` and described in
  `desc`. The LSR and MSR clears are given as `rclr`; that is exact for
  the field values, but the MSR clear lands one clock after the access, and
  the LSR read also clears the RX FIFO overrun flag and the RLS interrupt.
- **Side effects of a write on other registers.** A THR write clears
  LSR.THRE and LSR.TEMT and the THRE interrupt, and may start the THRE
  hold-off (U6). An FCR RX reset clears LSR.DR. These are in `desc`.
- **Edge-set status bits.** Every LSR bit is a flop set on a rising edge
  of its condition, not a copy of the condition. So after a clear, a
  condition that is still true is not reported again (U18, U19). RDL
  models a status field as `hw = w`, which does not show this.
- **IIR.** IIR is a registered priority encoding of the pending flags and
  of the RDA level (U7), not storage.
- **Undefined offsets.** RDL has no way to say that a read at offset 4
  returns 0. `MCR_RD` (read-only, reads 0) at offset 4 stands for it.
- **DLAB gating of side effects** (U25): only in `desc`.

## Debug registers (32-bit configuration only)

These are not in the RDL. In the native 32-bit configuration, a read with
`wb_sel_i = 4'b1111` returns the 32-bit word from `uart_debug_if`
(`uart_wb.v:268`, `uart_debug_if.v:115-123`). Only internal addresses 8 and
12 are decoded; every other address returns 0 there. Reading them has no
side effect. They are not readable through the shim.

| Byte address | Name | Bits (RTL) |
|---|---|---|
| 8 | Debug 1 | [31:24] MSR, [23:16] LCR, [15:12] IIR[3:0], [11:8] IER[3:0], [7:0] LSR |
| 12 | Debug 2 | [31:24] 0, [23:22] FCR[7:6], [21:17] MCR[4:0], [16:12] RX FIFO count, [11:8] receiver state, [7:3] TX FIFO count, [2:0] transmitter state |

Debug 1 matches the PDF (§4.10). Debug 2 does not: the PDF gives MCR at
[18:17] and FCR at [23:19], which cannot hold 5 and 2 bits. The RTL is
`{8'b0, fcr, mcr, rf_count, rstate, tf_count, tstate}`
(`uart_debug_if.v:121`).

## Register reference

### LCR.DLAB = 0

```{rdl:doctree} u2b0_uart16550
```

### LCR.DLAB = 1

```{rdl:doctree} u2b0_uart16550_dlab
```

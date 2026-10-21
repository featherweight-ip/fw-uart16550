# Programming

The core has no C header or driver in its repository. It is register
compatible with an NS16550A in FIFO mode, so a 16550 driver works, within
the quirks in {doc}`deviations`. Offsets below are core offsets; through
the shim, multiply by 4.

## Divisor

```
DL = round(f(wb_clk_i) / (16 * baud))      1 <= DL <= 65535
actual baud = f(wb_clk_i) / (16 * DL)
```

The receiver samples once per bit, at 8 to 9 ticks of 16 (U4), so the total
error between the two ends should stay well under ±3%.

| f(wb_clk_i) | Baud | DL | Actual | Error |
|---|---|---|---|---|
| 3.6864 MHz | 115200 | 2 | 115200 | 0 |
| 18.432 MHz | 115200 | 10 | 115200 | 0 |
| 12 MHz | 9600 | 78 | 9615 | +0.16% |
| 12 MHz | 115200 | 7 | 107143 | −7.0% (unusable) |
| 25 MHz | 115200 | 14 | 111607 | −3.1% (marginal) |
| 50 MHz | 115200 | 27 | 115741 | +0.47% |
| 100 MHz | 115200 | 54 | 115741 | +0.47% |

## Initialization

After reset: DL = 0 (the UART is stopped), LCR = 0x03 (8N1), FCR trigger =
14, IER = 0, MCR = 0.

```c
wr(LCR, 0x80 | fmt);       // DLAB = 1, plus the line format
wr(DLM, dl >> 8);          // MSB first ...
wr(DLL, dl & 0xff);        // ... LSB last: the DLL write restarts the divider (U24)
wr(LCR, fmt);              // DLAB = 0
wr(FCR, (trig << 6) | 0x06);  // trigger level, reset both FIFOs; bit 0 is ignored (U3)
wr(MCR, mcr);              // DTR, RTS, OUT1, OUT2, LOOP; write-only (U1)
wr(IER, ier);              // RDA | THRE | RLS | MS
```

`fmt` is LCR[6:0]: WLS[1:0] (0 = 5 bits … 3 = 8 bits), STB[2], PEN[3],
EPS[4], SP[5], BC[6]. For 8N1, `fmt` = 0x03.

Notes:

- Reset the FIFOs with IER.RDA = 0, or a pending RDA interrupt can stay
  stuck (U21).
- Do not read IIR, LSR or MSR to clear them while DLAB = 1: the reads have
  no side effects then (U25).
- MCR reads 0. Keep a copy in software.
- The modem pins are active high (U23).
- Leave at least one idle clock between WISHBONE accesses (U13). A CPU bus
  bridge usually does; a DMA engine or a back-to-back test master may not.

## Transmit

Polled:

```c
while (!(rd(LSR) & 0x20)) ;   // THRE
wr(THR, c);
```

THRE comes back about one character time after a write to an empty
transmitter, not at once (U6), so a byte-at-a-time polled loop sends at
close to the line rate but not faster. To use the FIFO, write up to 16
bytes after each THRE. Do not write more than 16: a 17th write overwrites
the next byte to be sent (U15).

Interrupt driven: enable IER.THRE. On IIR = 0xC2 (which the IIR read
clears), write up to 16 bytes. A THR write also clears the interrupt.

## Receive

Polled:

```c
while ((lsr = rd(LSR)) & 0x01) {   // DR
    c = rd(RBR);
    if (lsr & 0x1e) ...            // OE, PE, FE, BI for this character
}
```

Read LSR before RBR: LSR.PE/FE/BI refer to the character at the head of
the FIFO, and the LSR read clears them. A second errored character in a
row is not reported (U18). LSR[7] is cleared by the read even if errors
remain in the FIFO (U19). If LSR.DR stays 1 while RBR returns repeated
stale bytes, the FIFO lost a character (U16); bound the loop.

Interrupt driven: enable IER.RDA (which also enables the timeout) and
IER.RLS. On IIR:

| IIR | Action |
|---|---|
| 0xC6 | Read LSR (clears it); then read RBR as above |
| 0xC4 | Read RBR until LSR.DR = 0 |
| 0xCC | Read RBR until LSR.DR = 0 (any RBR read clears TI) |
| 0xC2 | Write THR |
| 0xC0 | Read MSR (clears it) |
| 0xC1 | Nothing pending. If `int_o` is still high, see U21 |

Reading the FIFO down to empty also covers U20: `int_o` can fall while
data is still at the trigger level, but a full drain on every interrupt
does not depend on a new edge.

## Linux

With the shim, the core matches the device tree binding of `8250_of`:

```
serial@... {
    compatible = "ns16550a";
    reg = <... 0x20>;
    reg-shift = <2>;
    reg-io-width = <4>;
    clock-frequency = <...>;
    interrupts = <...>;     /* level, active high */
};
```

`8250` writes DLL before DLM, which runs one period with the old DLM;
harmless unless DLL = 0 (U24). Its loopback probe (MCR = 0x1A, expects
MSR[7:4] = 0x9) should pass: in loopback MSR[7:4] follow MCR.
**(to confirm; not tested with Linux.)**

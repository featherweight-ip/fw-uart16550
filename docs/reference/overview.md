# Overview

The core is a 16550-style UART with a WISHBONE Classic register
interface. It has a 16-deep transmit FIFO (8 bits wide), a 16-deep
receive FIFO (8 data bits and 3 error bits), a 16-bit baud divider, five
interrupt sources with 16550 priority and identification, and the
16550 modem control and status lines. The FIFOs are always on: there is no
16450 mode and no DMA signalling. The bus is 8 or 32 bits wide, chosen by
a `` `define `` at compile time.

## Provenance

| Period | Author | Change |
|---|---|---|
| 2001–2002 | Jacob Gorban (OpenCores) | The core and the PDF (rev 0.1–0.6): registers, FIFOs, transmitter, receiver. 2001-12: 32-bit bus as default, `wb_sel_i`, debug interface, all WISHBONE inputs registered (one more wait state). 2002-07: FIFOs on inferable RAM (`raminfr`), optional `baud_o`, loopback fixes. |
| 2001–2002 | Igor Mohor (OpenCores) | Interrupt and LSR fixes; THRE delayed one character time after a write (2001-12-17); break fixes; endian define, big-endian by default (2002-02). |
| 2004 | Tadej Markovic (OpenCores) | Self-checking bench; RX input synchronizer; byte-lane address bits from `wb_sel_i` in 32-bit mode; receiver stop-bit fix; break/framing fix from Brandl Tobias. |
| 2004-11-22 | Igor Mohor | `2b0ad80`: the timeout interrupt needs a non-empty RX FIFO. **This is the revision described here.** |

The freecores mirror came through OpenCores SVN, but its history carries
no SVN revision numbers, so the pin is named by commit. Upstream tags are
`initial`, `rel_1` … `rel_4`, `asyst_2`, `asyst_3` and `NewFormat`. There is
no VHDL version (`rtl/vhdl` is empty).

## Features: the PDF compared with the RTL

| Feature | PDF | RTL (U2B0) |
|---|---|---|
| Register set | NS16550A without the scratch register | NS16550A **with** a scratch register (U2) |
| FIFO mode only, no 16450 mode | Yes | Yes; FCR[0] and FCR[3] are ignored (U3) |
| FIFO depth | 16 | 16 (TX 8 bits, RX 8 + 3 error bits) |
| RX trigger levels 1, 4, 8, 14 | Yes, reset 14 | Yes, reset 14 (NS16550A resets to 1) |
| Character format 5–8 bits, parity (odd, even, stick), 1/1.5/2 stop bits | Yes | Yes. The receiver checks the first stop bit only |
| Baud rate f/(16·DL) | Yes | Yes. DL = 0 stops the UART. The divider restarts on a DLL write only (U24) |
| RX sampling | "Perceived middle of the bit time" | One sample per bit, at tick 7 of 16; no majority vote (U4) |
| Break generation and detection | Yes | Yes. A zero character with BI after one character time low (U12) |
| Overrun | Character in the shift register lost, FIFO intact | The new byte **overwrites the oldest one** in the FIFO (U14) |
| Interrupts: RLS, RDA, TI, THRE, MS | Yes, 16550 priority | Yes. Several clearing defects (U7, U20, U21) |
| THRE timing | Not described | THRE held off for about one character time after a write to an empty THR (U6) |
| Modem lines | Active low (MCR '1' → pin '0'; MSR = complement of pin) | **Active high** (U23). Inputs not synchronized (U9) |
| Loopback | Yes | Yes, but RTS and DTR still drive the pads (U8), and the MSR delta bits follow the pads (U22) |
| OUT1, OUT2 pins | Not listed | None; only visible in loopback |
| Debug registers (32-bit mode) | Two 32-bit words at 8 and 12 | Yes; Debug 2's layout differs from the PDF |
| 8-bit or 32-bit bus | Yes | Yes, by `DATA_BUS_WIDTH_8`. In 32-bit mode the byte lane comes from `wb_sel_i`, big-endian unless `LITLE_ENDIAN` (U10) |
| Baud output `baud_o` | Optional | Optional (`UART_HAS_BAUDRATE_OUTPUT`): the 16x tick |
| DMA (TXRDY/RXRDY), autoflow, 64-byte FIFO | No | No |

## Block structure

```{mermaid}
flowchart LR
  WB["WISHBONE<br/>8- or 32-bit classic"] --> WBI
  subgraph TOP["uart_top"]
    WBI["uart_wb<br/>input regs, ack FSM"]
    subgraph REGS["uart_regs"]
      RF["IER LCR FCR MCR SCR DL<br/>LSR MSR IIR, interrupts"]
      BAUD["baud divider<br/>(16x tick)"]
      TX["uart_transmitter<br/>+ uart_tfifo"]
      RX["uart_receiver<br/>+ uart_rfifo"]
      SYNC["uart_sync_flops"]
    end
    DBG["uart_debug_if<br/>(32-bit only)"]
  end
  WBI --> RF
  RF --> TX
  RX --> RF
  BAUD --> TX
  BAUD --> RX
  SYNC --> RX
  TX --> STX["stx_pad_o"]
  SRX["srx_pad_i"] --> SYNC
  RF <--> MODEM["rts/dtr out<br/>cts/dsr/ri/dcd in"]
  RF --> INT["int_o"]
  RF --> DBG
  DBG --> WBI
```

The modules are described in {doc}`architecture`.

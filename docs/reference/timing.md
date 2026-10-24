# Timing

All timing below is from reading the RTL at `u2b0` and is
**(to confirm)** in simulation unless stated. Confirmed on the `ref` view
(2026-10-24): the THRE hold-off table, the baud divider's restart, and the
break time ({doc}`verification`). *T* is one `wb_clk_i`
period. A tick is one baud-generator enable, every DL clocks; a bit is 16
ticks.

## WISHBONE

Described with a waveform in {doc}`interface`. In short:

| Item | Clocks | Source |
|---|---|---|
| Inputs registered | every clock | `uart_wb.v:228-243` |
| STB presented → register strobe (`we_o`/`re_o`) | 1 | `uart_wb.v:224-225` |
| STB presented → `wb_ack_o` high | 2 (ack in the 3rd clock of the cycle) | `uart_wb.v:201-206` |
| Ack → FSM idle again | 2 (states 1, 2) | `uart_wb.v:212-221` |
| Idle clocks needed between accesses | ≥ 1 (else U13) | `uart_wb.v:202-210, 217-220` |
| Minimum period of a stream of accesses | 4 | |
| Register write takes effect | at the edge that raises `wb_ack_o` | `uart_regs.v:475-557` |
| THR → TX FIFO | one clock after that edge | `uart_regs.v:550` |
| RBR read → RX FIFO pop | one clock after that edge | `uart_regs.v:421-431` |
| LSR read → bits cleared | at that edge | `uart_regs.v:439-455` |
| MSR read → bits 3:0 cleared | one clock after that edge | `uart_regs.v:458-468, 582` |
| Interrupt condition → `int_o` | 2 (pending flag, then `int_o`) | `uart_regs.v:804-853` |

The fw-proto-wb target acknowledges sooner. The comparison between
the reference and `fw-uart16550` allows for this bus timing difference
({doc}`../design/plan` §1).

## Baud tick

`enable` is high for one clock every DL clocks, DL ≥ 1
(`uart_regs.v:692-713`). After a DLL write the first tick comes DL + 2
clocks after the write strobe (the strobe sets `start_dlc`, which loads the
counter with DL - 1 a clock later), with the DL value of that moment
(U24; confirmed). With
`UART_HAS_BAUDRATE_OUTPUT`, `baud_o` is this tick.

## Transmitter

| Item | Ticks |
|---|---|
| THR write → start bit on `stx_pad_o`, transmitter idle | 2 to 3 (idle tick, pop_byte tick, then start), plus one clock |
| Start bit, each data bit, parity bit | 16 |
| Stop: one / 1.5 / two stop bits, in `send_stop` | 14 / 22 / 30 |
| Stop seen on the line between back-to-back characters | 16 / 24 / 32 (with the idle and pop_byte ticks) |
| Character period, back to back | 16 × (1 + bits + parity + stop) |

`stx_pad_o` changes one clock after a tick (it is a flop,
`stx_o_tmp`), except that LCR.BC acts at once (combinational,
`uart_transmitter.v:349`).

**TEMT.** The FSM leaves `send_stop` for idle after 14 ticks of a one-stop
character, so LSR.TEMT rises about 2 ticks before the stop bit ends (if the
THRE hold-off has also expired).

### THRE hold-off (`block_cnt`)

A THR write while LSR.THRE = 1 loads `block_cnt` with `block_value`, and the
counter counts down on ticks. THRE (and TEMT) cannot be set until it is 0
(`uart_regs.v:715-742`). `block_value` + 1 is 16 × (the character length
minus one stop bit):

| LCR[3:0] (PEN, STB, WLS) | Character, bits | `block_value` | Hold-off, bit times |
|---|---|---|---|
| `0000` | 5N1: 7 | 95 | 6 |
| `0100` | 5N1.5: 7.5 | 103 | 6.5 |
| `0001`, `1000` | 6N1, 5P1: 8 | 111 | 7 |
| `1100` | 5P1.5: 8.5 | 119 | 7.5 |
| `0010`, `0101`, `1001` | 7N1, 6N2, 6P1: 9 | 127 | 8 |
| `0011`, `0110`, `1010`, `1101` | 8N1, 7N2, 7P1, 6P2: 10 | 143 | 9 |
| `0111`, `1011`, `1110` | 8N2, 8P1, 7P2: 11 | 159 | 10 |
| `1111` | 8P2: 12 | 175 | 11 |

At reset LCR = 0x03 (8N1): 143 ticks. The transmitter itself takes the byte
2 ticks after the write, so after a single write to an empty transmitter
THRE comes back about 9 bit times later, near the end of the last data bit,
instead of at once (U6). A THR write while THRE = 0 does not reload the
counter. This also explains U11: the upstream bench device expects THRE
about 1.23 ms earlier than the RTL gives it ({doc}`deviations`).

## Receiver

| Item | Ticks |
|---|---|
| `srx_pad_i` → receiver input | 2 clocks (synchronizer) |
| Falling edge → start detected | 0 to 1 tick (first tick that sees 0) |
| Start detected → start-bit check (mid-bit) | 8 |
| Start check → first data sample | 16 |
| Data sample → next data sample, parity sample, or stop sample (no parity) | 16 |
| Parity sample → stop sample | **15** |
| Stop sample → push into the RX FIFO | 1 (if the line is 1) |

So each bit is sampled 8 to 9 ticks after its nominal start (U4). With
parity on, the stop bit is sampled one tick earlier than the other bits
(`ca_lc_parity`, `check_parity` and `wait1` take 15 ticks in total,
`uart_receiver.v:358-387`). This is still within the stop bit.

The extra tick in `rec_prepare` comes from a double assignment:
`rcounter16` is set to 14 and then, later in the same branch, to
`rcounter16 - 1` = 15, which wins (`uart_receiver.v:323, 328`). The bit
timing above depends on that.

### Timeout and break counters (`toc_value`)

`toc_value` is four character times in ticks, minus 1; the break counter
uses `toc_value / 4`, one character time minus 1
(`uart_receiver.v:437-452`):

| LCR[3:0] | Character, bits | `toc_value` (TI) | `brc_value` (break) |
|---|---|---|---|
| `0000` | 7 | 447 | 111 |
| `0100` | 7.5 | 479 | 119 |
| `0001`, `1000` | 8 | 511 | 127 |
| `1100` | 8.5 | 543 | 135 |
| `0010`, `0101`, `1001` | 9 | 575 | 143 |
| `0011`, `0110`, `1010`, `1101` | 10 | 639 | 159 |
| `0111`, `1011`, `1110` | 11 | 703 | 175 |
| `1111` | 12 | 767 | 191 |

The character length counts start, data, parity and all stop bits. At
reset `counter_t` is 639 and `counter_b` is 159 (the 8N1 values).

- **TI**: `counter_t` is reloaded on every push and pop and while the FIFO
  is empty, and counts down on ticks. TI is raised `toc_value` ticks after
  the last push or pop (about 4 character times).
- **Break**: `counter_b` is reloaded on every clock with the input at 1.
  `break_error` is set after `brc_value` ticks of continuous 0, about one
  character time from the falling edge. The break character is pushed on
  the next tick of the waiting `push` state.

## Modem inputs

MSR[7:4] follow the pads with one clock of delay. A delta bit is set one
clock after a pad change. Both are taken from the unsynchronized pads (U9).

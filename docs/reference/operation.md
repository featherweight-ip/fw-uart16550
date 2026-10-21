# Operation

All statements on this page come from reading the RTL at `u2b0`. Those
marked **(to confirm)** are not yet checked in simulation. Bit-level
timing is in {doc}`timing`.

## Baud generator

The 16-bit divisor latch DL = {DLM, DLL} (`uart_regs.v:309`) drives a
16-bit down counter `dlc` (`uart_regs.v:692-701`). The counter reloads with
DL − 1 when it reaches 0, or when DLL is written (`start_dlc`). The tick
`enable` is registered: it is high for one clock when DL ≠ 0 and `dlc` = 0
(`uart_regs.v:704-713`). So there is one tick every DL clocks, and

```
baud = f(wb_clk_i) / (16 * DL)
```

- DL = 0 (the reset value) gives no ticks: the transmitter, the receiver,
  the THRE hold-off, the break detector and the timeout counter all stop.
- DL = 1 gives a tick on every clock.
- The generator runs whatever LCR.DLAB is. (The PDF says the engine
  starts when DLAB is cleared.)
- Only a DLL write restarts the counter. A DLM write takes effect at the
  next reload, which can be up to 65536 clocks away (U24). Write DLM, then
  DLL.

The transmitter and receiver share the tick. There is no separate
receiver clock.

## Transmitter

The transmitter (`uart_transmitter.v:201-349`) is a 6-state FSM that
advances on ticks only. It takes bytes from the TX FIFO.

```{mermaid}
stateDiagram-v2
  [*] --> idle
  idle --> pop_byte: TX FIFO not empty
  pop_byte --> send_start: load shift reg, pop
  send_start --> send_byte: 16 ticks
  send_byte --> send_byte: 16 ticks per bit
  send_byte --> send_parity: last bit, PEN
  send_byte --> send_stop: last bit, no PEN
  send_parity --> send_stop: 16 ticks
  send_stop --> idle: 14 / 22 / 30 ticks
```

- **idle** drives 1. When the FIFO count is not 0 at a tick, it goes to
  **pop_byte**.
- **pop_byte** loads the head byte into the shift register, computes its
  parity over the active bits, sets the bit counter from LCR.WLS, and
  pops the FIFO (a one-clock `tf_pop`).
- **send_start** drives 0 for 16 ticks.
- **send_byte** drives the bits LSB first, 16 ticks each.
- **send_parity** drives the parity bit for 16 ticks: odd (EPS = 0), even
  (EPS = 1), or stuck at 1 (SP = 1, EPS = 0) or 0 (SP = 1, EPS = 1)
  (`uart_transmitter.v:294-299`).
- **send_stop** drives 1 for 14, 22 or 30 ticks (one, 1.5 or two stop
  bits; `uart_transmitter.v:324-328`). With the idle and pop_byte ticks
  before the next start bit, back-to-back characters have 16, 24 or 32
  ticks of stop, with no gap.

LCR is read live. Changing it in the middle of a character changes the
rest of that character.

**Break**: LCR.BC forces `stx_pad_o` to 0 after the FSM
(`uart_transmitter.v:349`). The FSM keeps sending FIFO data behind it, so
bytes written during a break are sent invisibly and lost. To send a clean
break, wait for LSR.TEMT, set BC, wait, clear BC.

**TX FIFO reset** (FCR[2]) clears the pointers and count only. A character
already in the shift register is finished. A reset in the one-tick window
between idle and pop_byte sends a stale byte (U26).

**THRE and TEMT.** LSR.THRE is set when the TX FIFO is empty and the THRE
hold-off counter is 0. LSR.TEMT adds "the FSM is in idle". Both are set on
a rising edge of the condition and cleared by a THR write
(`uart_regs.v:598-599, 658-678`). A THR write while THRE = 1 loads the
hold-off counter `block_cnt` with one character time minus one stop bit,
counted in ticks (`uart_regs.v:715-742`): THRE stays 0 for that long even
though the FIFO is empty again two ticks later (U6). A write while THRE
= 0 does not reload it.

## Receiver

The receiver (`uart_receiver.v:262-420`) is an 11-state FSM that advances
on ticks only. Its input is `srx_pad_i` after two synchronizer flops, or the
transmitter output in loopback.

```{mermaid}
stateDiagram-v2
  [*] --> idle
  idle --> rec_start: input 0 and no break
  rec_start --> idle: input 1 at mid-bit
  rec_start --> rec_prepare: input 0 at mid-bit
  rec_prepare --> rec_bit: 7 ticks
  rec_bit --> end_bit: 16 ticks (sample at 7)
  end_bit --> rec_bit: more bits
  end_bit --> rec_parity: last bit, PEN
  end_bit --> rec_stop: last bit, no PEN
  rec_parity --> ca_lc_parity: sample
  ca_lc_parity --> check_parity
  check_parity --> wait1
  wait1 --> rec_stop
  rec_stop --> push: sample stop
  push --> idle: input 1, or break: push
  push --> rec_start: input 0, no FE: push
  push --> push: input 0 with FE: wait
```

- **Start bit.** In idle the receiver looks at the input on each tick. A 0
  starts a 16-tick counter. Eight ticks later (counter value 7) it samples
  again: 1 is a glitch and it returns to idle; 0 is a start bit.
- **Data, parity, stop.** Each bit is sampled once, at counter value 7 of
  its 16 ticks (U4). There is no majority vote and no noise flag. Data
  bits shift in LSB first; for 5–7 bits the high bits of the byte are 0.
  Parity is checked against LCR.EPS/SP (`uart_receiver.v:371-377`). The
  first stop bit is sampled; 0 is a framing error. A second stop bit is
  not checked.
- **Push.** On the tick after the stop sample (`push`), if the input is 1
  or a break was detected, the character goes into the RX FIFO as
  {data, BI, PE, FE} and the FSM returns to idle. If the input is already
  0 and there was no framing error, it is pushed and the FSM goes straight
  to `rec_start` (a start bit that follows the stop sample closely). If the
  input is 0 **and** FE was set, the FSM waits in `push` and pushes
  nothing until the input goes to 1 (then it pushes the FE character) or
  the break detector fires (then it pushes a break character instead; the
  FE character is lost) (`uart_receiver.v:396-416`, U12) **(to confirm)**.
- LCR is read live, as in the transmitter.

**RX FIFO reset** (FCR[1]) clears the FIFO, its error flags and overrun,
and LSR.DR. It does not reset the FSM, so a character in progress is still
pushed. It does not clear a pending RDA interrupt (U21).

## FIFOs

Both FIFOs are 16 deep, with 4-bit pointers and a 5-bit count
(`uart_tfifo.v`, `uart_rfifo.v`). The data bytes are in `raminfr`, a
16×8 array with a synchronous write and an **asynchronous read**, and no
reset (`raminfr.v:83-110`). The RX FIFO keeps the 3 error bits of each
entry in a separate 16×3 flop array, reset and cleared on pop
(`uart_rfifo.v:186, 206-275`). Its `error_bit` output is the OR of all 48
flags (`uart_rfifo.v:315-318`); it drives LSR[7].

The head entry is always visible: RBR reads the head byte and LSR.PE/FE/BI
come from the head entry's flags.

Defects at the edges, all **(to confirm)**:

- The RAM write enable is the push strobe, with no check of the count. A
  push into a full FIFO (when `top == bottom`) writes over the head byte.
  For the RX FIFO that is an overrun: the count and the head's error flags
  stay, but the head's data byte becomes the new byte (U14). For the TX
  FIFO it is a THR write while 16 bytes are waiting: the next byte to be
  sent is replaced (U15).
- A push and a pop in the same clock do not check the count. If the RX
  FIFO is empty (an RBR read of an empty FIFO lands with a received
  character), both pointers move, the count stays 0, and the character is
  lost while LSR.DR is set (U16). If it is not empty, the popped entry's
  error flags are not cleared, so `error_bit` can stay 1 after the errored
  character has been read (U17).

## Interrupts

There are five sources. Each has a pending flag, set on a rising edge of
(enable AND condition) and cleared by its clearing action or by clearing
its enable bit (`uart_regs.v:745-838`):

| Source | IIR | Condition | Pending flag cleared by |
|---|---|---|---|
| RLS: receiver line status | 0xC6 | IER.RLS and any of LSR.OE, PE, FE, BI | LSR read |
| RDA: received data available | 0xC4 | IER.RDA and RX count ≥ trigger level | RBR read while the count equals the trigger level |
| TI: character timeout | 0xCC | IER.RDA and timeout counter = 0 and RX count ≠ 0 | RBR read |
| THRE: THR empty | 0xC2 | IER.THRE and LSR.THRE | THR write, or IIR read that returns 0xC2 |
| MS: modem status | 0xC0 | IER.MS and any of MSR[3:0] | MSR read |

IIR is registered each clock from these, highest first: RLS pending,
**RDA condition** (the level, not its pending flag), TI pending, THRE
pending, MS pending; otherwise 0xC1 (`uart_regs.v:857-891`). So IIR can show
RDA while the RDA pending flag is clear (U7).

`int_o` is registered from the pending flags: it is 1 when any flag is
set (`uart_regs.v:841-853`). For the highest pending source it drops in the
clock of the clearing access instead of one clock after; the THRE term does
not do this, because its expression `!(fifo_write & iir_read)` is never 0.

Clearing defects, all **(to confirm)**:

- **RDA lost** (U20). The RDA flag is cleared by the RBR read at
  count = trigger level, but the pop is one clock later. If a character
  is pushed in the clock of the read or of the pop, the count never drops
  below the trigger level, the RDA condition never falls, and the flag is
  not set again. `int_o` falls while IIR still reads 0xC4 and the FIFO is
  at the trigger level. Only the timeout (which needs four idle character
  times) or a later read below the trigger level brings it back. Under
  continuous traffic the FIFO can overrun.
- **RDA stuck** (U21). If the count falls below the trigger level without
  passing an RBR read at exactly the trigger level, the flag is never
  cleared. That happens with an RX FIFO reset, or when FCR raises the
  trigger level above the count. `int_o` stays 1 while IIR reads 0xC1 (or a
  lower source). Clearing IER.RDA clears it.

## Character timeout

The 10-bit counter `counter_t` (`uart_receiver.v:468-480`) is loaded with
`toc_value` (four character times in ticks, minus 1; {doc}`timing`) on
every push, on every pop, and while the RX FIFO is empty. Otherwise it
counts down on ticks and stops at 0. The TI condition is
counter = 0 with a non-empty FIFO (`uart_regs.v:753`; the 2b0ad80 fix).
So TI fires four character times after the last push or pop, whether the
FIFO is above or below the trigger level. A character being received does
not reload it until it is pushed.

## Break detection

The 8-bit counter `counter_b` (`uart_receiver.v:451-464`) is loaded with
one character time in ticks, minus 1 (`toc_value / 4`), on every clock
where the input is 1, and counts down on ticks while it is 0. At 0,
`break_error` is set. The receiver then pushes one character {0x00,
BI = 1, PE = 0, FE = 0} and returns to idle. It does not start a new
character while `break_error` is 1, so one break gives one break character.
It restarts after the input has been 1 for one clock (U12).

Because the line is low through the stop-bit position, a break first
gives a framing error in the receiver; that FE character is not pushed
(see Receiver above).

## Loopback

MCR.LOOP = 1 (`uart_regs.v:344-348, 394-396`):

- the transmitter output (after the break gate) is the receiver input;
- `stx_pad_o` is 1 and `srx_pad_i` is ignored;
- MSR[7:4] read {OUT2, OUT1, DTR, RTS} as {DCD, RI, DSR, CTS};
- `rts_pad_o` and `dtr_pad_o` still follow MCR (U8);
- the MSR delta bits still follow the input pads, not the loopback
  signals (U22).

## Modem control and status

- `rts_pad_o` = MCR.RTS and `dtr_pad_o` = MCR.DTR, not inverted
  (`uart_regs.v:351-352`). MCR reads 0 (U1).
- MSR[7:4] are registered copies of `{dcd, ri, dsr, cts}_pad_i`, not
  inverted, or the loopback signals (`uart_regs.v:584`) (U23).
- MSR[3:0] are set when the corresponding pad changes level in either
  direction, including TERI (`uart_regs.v:582-583`) (U22). They are cleared
  one clock after an MSR read (`msi_reset`), and are cleared on the first
  clock after reset.
- The pads are not synchronized (U9): a pad change goes straight into
  the MSR and the delta logic.

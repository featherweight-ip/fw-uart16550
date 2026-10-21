# Deviations, defects and quirks

This page lists every point where the RTL (U2B0, `2b0ad80`) differs from
the PDF or from an NS16550A, and every suspected defect found while
reading it. U1–U12 are the list from the plan ({doc}`../design/plan` §2).
U13–U26 were found while writing this specification. Each item gets a
directed test on the `ref` view in step 4, planned in {doc}`verification`.
The IDs are also used in the plan (U1–U12) and in the RDL.

File:line references are to tag `u2b0`. "Status" is the state of
confirmation. Nothing here has been simulated yet except U11.

## Summary

| ID | Area | Summary | Kind | Status |
|---|---|---|---|---|
| U1 | Regs | MCR is write-only and reads 0 | quirk | to confirm (step 4) |
| U2 | Regs | SCR exists; the PDF says it was removed | PDF wrong | to confirm (step 4) |
| U3 | Regs | FIFOs always on; FCR[0] and DMA mode ignored; no 16450 mode | quirk (as PDF) | to confirm (step 4) |
| U4 | RX | One sample per bit, at tick 7 of 16; no majority vote | quirk | to confirm (step 4) |
| U5 | RX FIFO | Overrun: the incoming character's flags are dropped, the count does not change; but see U14 | quirk | to confirm (step 4) |
| U6 | TX | THRE held off one character time minus a stop bit after a THR write with THRE = 1 | quirk | to confirm (step 4) |
| U7 | IRQ | IIR shows RDA from the level; `int_o` uses a latch | quirk | to confirm (step 4) |
| U8 | Modem | Loopback still drives RTS/DTR to the pads; no OUT1/OUT2 pins | quirk | to confirm (step 4) |
| U9 | Modem | Modem inputs not synchronized | defect (CDC) | to confirm (step 4) |
| U10 | Bus (32-bit) | Byte lane from `wb_sel_i`; non-one-hot `sel` reaches byte 0 of the word | quirk | to confirm (step 11) |
| U11 | Bench | The shipped log fails "Bit 5 of LSR register not '1'" | bench | re-run 2026-10-21; reproduces; RTL side to confirm (step 4) |
| U12 | RX | Break: a zero character with BI after one character time low; the FE character before it is lost | quirk | to confirm (step 4) |
| U13 | Bus | A back-to-back access (no idle clock) is acked but not performed | **defect** | to confirm (step 4) |
| U14 | RX FIFO | Overrun overwrites the head character's data byte | **defect** | to confirm (step 4) |
| U15 | TX FIFO | A write to a full TX FIFO overwrites the next byte to send | defect | to confirm (step 4) |
| U16 | RX FIFO | Pop of an empty FIFO in the clock of a push loses the character and leaves LSR.DR stuck at 1 | **defect** | to confirm (step 4) |
| U17 | RX FIFO | Push and pop together leave the popped entry's error flags set | defect | to confirm (step 4) |
| U18 | LSR | PE/FE/BI are edge-set: the second of two errored characters in a row is not reported | **defect** | to confirm (step 4) |
| U19 | LSR | LSR[7] is cleared by a read while errors remain in the FIFO, and not set again | defect | to confirm (step 4) |
| U20 | IRQ | RDA interrupt lost if a character arrives in the 2-clock window of the RBR read at the trigger level | **defect** | to confirm (step 4) |
| U21 | IRQ | RDA pending flag stuck after an RX FIFO reset or a raised trigger level: `int_o` = 1, IIR = 0xC1 | **defect** | to confirm (step 4) |
| U22 | Modem | MSR deltas follow the pads even in loopback; TERI set on both edges of RI | quirk | to confirm (step 4) |
| U23 | Modem | Modem pins active high; the PDF gives active low | PDF wrong | to confirm (step 4) |
| U24 | Baud | Only a DLL write restarts the divider; a later DLM write waits for the next reload (up to 65536 clocks) | quirk | to confirm (step 4) |
| U25 | Regs | With DLAB = 1, IIR, LSR and MSR reads have no side effects | quirk | to confirm (step 4) |
| U26 | TX FIFO | TX FIFO reset within one tick of the transmitter leaving idle sends a stale byte, and can lose a byte written then | defect (race) | to confirm (step 4) |

"Defect" means behaviour a 16550 driver does not expect and that can lose
data or hang an interrupt. "Quirk" means a documented or harmless
difference. Bold defects are the ones most likely to show up in normal use.

## The plan's list (U1–U12)

### U1: MCR is write-only and reads 0

- **RTL.** The read mux has no MCR entry; offset 4 falls to
  `default: wb_dat_o = 8'b0` (`uart_regs.v:404-417`, line 415). MCR[4:0]
  is stored (`uart_regs.v:516-521`).
- **PDF.** §4.6 marks every MCR bit "W". It does not say what a read returns.
- **NS16550A.** MCR is read-write.
- **Status.** To confirm by simulation (step 4).

### U2: SCR exists

- **RTL.** An 8-bit `scratch` register at offset 7, read-write, reset 0
  (`uart_regs.v:523-530`, 414).
- **PDF.** §5: "The scratch register is removed, as it serves no purpose."
  §4.1 does not list it.
- **Status.** To confirm by simulation (step 4).

### U3: FIFOs always on

- **RTL.** FCR stores only bits 7:6 (`fcr <= wb_dat_i[7:6]`) and uses bits
  2:1 as one-clock resets (`uart_regs.v:500-513`). Bits 0 and 3–5 are
  dropped. IIR[7:6] are the constant `2'b11` (`uart_regs.v:410`). There is no
  FIFO-disabled path anywhere.
- **PDF.** §1 "FIFO only operation"; §4.4 bit 0 ignored. Same as the RTL.
- **NS16550A.** FCR[0] = 0 gives 16450 mode; FCR[3] selects DMA mode 1.
- **Status.** To confirm by simulation (step 4).

### U4: one sample per bit

- **RTL.** The start bit is checked, and each data, parity and stop bit is
  sampled, once, when `rcounter16 == 7` (`uart_receiver.v:306, 333, 359,
  389`). There is no 3-sample vote and no noise flag. With parity on, the
  stop bit is sampled one tick early (see {doc}`timing`).
- **PDF.** §5.1: sampling "is performed in the perceived middle of the bit
  time".
- **Status.** To confirm by simulation (step 4).

### U5: overrun drops the incoming character

- **RTL.** A push into a full RX FIFO (`count == 16`) does not move `top`,
  does not change the count and does not store the error flags
  (`uart_rfifo.v:255-260`). It sets `overrun` (`uart_rfifo.v:285-286`),
  which sets LSR.OE. But the data byte is written anyway: see U14. So the
  incoming character is not cleanly dropped.
- **PDF.** LSR[1]: "it will overwrite the data in the shift register but
  the FIFO will remain intact".
- **Status.** To confirm by simulation (step 4), together with U14.

### U6: THRE hold-off

- **RTL.** A THR write while `lsr5r` (THRE) is 1 loads `block_cnt` with
  `block_value` (`uart_regs.v:729-739`): 16 × (character length − one stop
  bit) − 1 ticks, 143 for 8N1 (`uart_regs.v:716-726`). THRE and TEMT
  cannot be set while it is not 0 (`thre_set_en`, `uart_regs.v:598-599,
  742`). The comment (`uart_regs.v:715`) and the 2001-12-17 commit say this
  is intended: THRE "is delayed for one character time".
- **PDF.** LSR[5]: "'1' – The transmitter FIFO is empty"; no delay.
- **NS16550A.** THRE rises when the byte moves to the shift register, at
  once if the transmitter is idle.
- **Status.** To confirm by simulation (step 4). It is the likely cause of
  U11.

### U7: RDA uses the level

- **RTL.** `rda_int = ier[0] && rf_count >= trigger_level`
  (`uart_regs.v:750`). The IIR encoder uses this level directly (`if
  (rda_int)`, `uart_regs.v:867`), while the other sources use their pending
  flags. `int_o` uses the pending flag `rda_int_pnd` (`uart_regs.v:848`),
  which is set on a rising edge of `rda_int` and cleared by an RBR read
  with `rf_count == trigger_level`, or by IER[0] = 0
  (`uart_regs.v:811-816`). The other four pending flags are also set on a
  rising edge (`uart_regs.v:790-794, 804-837`). U20 and U21 are
  consequences.
- **PDF.** §4.3: RDA reset control "FIFO drops below trigger level".
- **Status.** To confirm by simulation (step 4).

### U8: loopback and the modem outputs

- **RTL.** `rts_pad_o = mcr[1]`, `dtr_pad_o = mcr[0]` with no loopback
  term (`uart_regs.v:351-352`). In loopback only `stx_pad_o` is forced
  (to 1) and the receiver input switched (`uart_regs.v:395-396`). `uart_top`
  has no OUT1/OUT2 ports (`uart_top.v:149-152`).
- **PDF.** §4.6 bit 4: STX_PAD_O is set to '1'; nothing about RTS/DTR.
- **NS16550A.** In loopback the modem outputs are forced inactive.
- **Status.** To confirm by simulation (step 4).

### U9: modem inputs not synchronized

- **RTL.** `cts/dsr/ri/dcd_pad_i` go straight from the ports
  (`uart_top.v:276-277`) into the MSR flops and into the XOR with
  `delayed_modem_signals` (`uart_regs.v:341-345, 573-587`). Only `srx_pad_i`
  has a synchronizer (`uart_regs.v:382-392`). A pad change near a clock
  edge can set a delta bit without the change showing in MSR[7:4], or the
  reverse, and is a metastability risk.
- **PDF.** Silent.
- **Status.** To confirm by simulation (step 4) (the functional part:
  deltas on a pad change). Metastability is not simulated.

### U10: 32-bit byte lanes

- **RTL.** In 32-bit mode, write data comes from the lane `wb_sel_i`
  selects, and `[7:0]` for any other `sel` (`uart_wb.v:274-282`). The
  internal address LSBs come from `sel` (big-endian by default:
  `4'b0001` → 3), and are 0 for a non-one-hot `sel`
  (`uart_wb.v:284-303`). Read data goes to the selected lane, the debug
  word for `4'b1111`, and 0 otherwise (`uart_wb.v:259-270`). So a
  `4'b1111` write goes to byte 0 of the word with data `[7:0]`. The upstream
  bench writes with `sel = 4'hF`, so in the 32-bit configuration its LCR
  write (address 3) lands in THR (address 0) and it fails at
  initialization (U11).
- **PDF.** §5: the 32-bit mode "uses the WISHBONE [SEL_I] signal to
  properly receive and return 8-bit data". `LITLE_ENDIAN` is not mentioned.
- **Status.** Applies to the 32-bit configuration only (`ref-rtl-32`). To
  confirm by simulation (step 11).

### U11: the shipped bench log fails on THRE

- **Observed.** `sim/rtl_sim/log/uart_interrupts_report.log` (shipped)
  records one failure: "Bit 5 of LSR register not '1'!" (line 12).
- **Re-run 2026-10-21** (`scripts/upstream-bench.sh`, Icarus, two bench-only
  `#0` race workarounds): with `DATA_BUS_WIDTH_8` it reproduces the shipped
  report exactly, on `u2b0` and `u2b0-fw1` alike. Likely a bench bug, not
  RTL: the bench device's `rx_clk_cnt_en` starts as X, so its bit counter
  runs from t ≈ 0 instead of from the start bit (1.23 ms), and it expects
  THRE 1.23 ms before the RTL raises it (`block_cnt` = 143 at LCR = 0x03,
  U6). In the default 32-bit configuration the bench fails at
  initialization instead (U10).
- **Status.** Bench result recorded. That the RTL's THRE timing is the
  U6 hold-off and nothing else: to confirm on the `ref` view (step 4).

### U12: break

- **RTL.** `counter_b` reloads with `brc_value` (one character time in
  ticks, minus 1) on every clock with the input at 1 and counts down on
  ticks while it is 0; `break_error = (counter_b == 0)`
  (`uart_receiver.v:239, 451-464`). The receiver then pushes
  `{8'b0, 3'b100}`: data 0, BI = 1, PE = 0, FE = 0
  (`uart_receiver.v:399-406`), and does not start a new character until the
  input has been 1 (`uart_receiver.v:299`). Before that, the stop-bit
  sample of the break is 0, so the FSM has a framing error; in `sr_push` it
  waits while the input is 0 and FE is set (`uart_receiver.v:408`), so that
  FE character is never pushed. The same wait drops a real FE character if
  the line goes low straight after it and stays low long enough to be a
  break.
- **PDF.** LSR[4]: "one zero character enters the FIFO and the UART waits
  for a valid start bit".
- **Status.** To confirm by simulation (step 4).

## Found while writing this specification (U13–U26)

### U13: back-to-back WISHBONE access acknowledged but not performed

- **RTL.** The ack FSM (`uart_wb.v:195-222`) goes 0 → 1 → 2 → 0. State 2
  sets `wre <= 0` (`uart_wb.v:217-220`), and state 0 sets `wre <= 1` only
  when no registered strobe is present (`uart_wb.v:207-210`). The register
  strobes are `we_o/re_o = ... & wre` (`uart_wb.v:224-225`). If the master
  starts the next access in the clock right after it sees the ack, the
  registered strobe is already high when the FSM returns to state 0 with
  `wre` = 0: the FSM acks it (`uart_wb.v:203-206`) but no strobe is made.
  The write is lost; a read returns the current register value in 8-bit
  mode (no pop, no clear) and stale data in 32-bit mode
  (`uart_wb.v:262`). One idle clock between accesses avoids it.
- **PDF.** Silent. The 2001-12-06 commit says all WISHBONE signals are now
  sampled, adding a wait state.
- **Impact.** A WISHBONE Classic master may start a new cycle straight after
  an ack. The fwvip-wb initiator in the `ref` bench must leave one idle
  clock between accesses, except in the test for U13.
- **Status.** To confirm by simulation (step 4).

### U14: RX overrun overwrites the head character

- **RTL.** The RAM write enable is the push strobe itself:
  `raminfr ... .we(push), .a(top)` (`uart_rfifo.v:197-204`;
  `raminfr.v:104-107`). The count check guards only the pointer, count and
  flag updates (`uart_rfifo.v:255-260`). With 16 entries, `top == bottom`,
  so the overrun push writes the new byte over the head entry's data. The
  head keeps its own error flags. RBR then returns the newest byte where
  the oldest should be, and that byte's own error flags are lost.
- **PDF.** LSR[1]: "the FIFO will remain intact".
- **Status.** To confirm by simulation (step 4).

### U15: write to a full TX FIFO overwrites the next byte

- **RTL.** Same structure: `raminfr ... .we(push)` (`uart_tfifo.v:185-192`),
  count check on the pointers only (`uart_tfifo.v:212-216`). A THR write
  with 16 bytes waiting replaces the head byte; the count stays 16. The
  `overrun` flag is set but not used (`uart_tfifo.v:239-240`;
  `uart_transmitter.v:183, 195`).
- **PDF.** Silent.
- **NS16550A.** Writing to a full TX FIFO loses the written byte.
- **Status.** To confirm by simulation (step 4).

### U16: pop of an empty RX FIFO with a push loses the character

- **RTL.** `rf_pop` is made by any RBR read, empty or not
  (`uart_regs.v:421-431`). The push-and-pop case has no count check:
  both pointers move and the count is unchanged (`uart_rfifo.v:267-271`).
  If the FIFO is empty, the count stays 0 and the new character is gone.
  `lsr0` (push into an empty FIFO) still sets LSR.DR
  (`uart_regs.v:593, 609-612`), and DR is cleared only by a pop at
  `rf_count == 1`, so DR stays 1 with an empty FIFO. A polled loop
  "while DR, read RBR" then reads stale bytes until a new character
  arrives. RDA and TI are not raised (count 0).
- **When.** An RBR read on an empty FIFO (Linux does this during startup
  to clear the port) whose pop (one clock after the access) lands in the
  clock of a receiver push.
- **Status.** To confirm by simulation (step 4).

### U17: push and pop together leave stale error flags

- **RTL.** A pop alone clears the popped entry's flags
  (`fifo[bottom] <= 0`, `uart_rfifo.v:263`). A pop together with a push
  does not (`uart_rfifo.v:267-271`). `error_bit` is the OR over all 16
  entries (`uart_rfifo.v:315-318`), so it stays 1 after the errored
  character has been read, until `top` writes that entry again (up to 15
  pushes later). That holds LSR[7]'s condition high: LSR[7] is not set by
  a new error in that time (U19).
- **Status.** To confirm by simulation (step 4).

### U18: LSR PE, FE, BI are set on edges of the head's flags

- **RTL.** `lsr2/3/4` are the head entry's flags (`rf_data_out[1]`, `[0]`,
  `[2]`, `uart_regs.v:595-597`). The LSR bits are set on a rising edge of
  them only (`lsr2r <= lsr_mask ? 0 : lsr2r || (lsr2 && ~lsr2_d)`,
  `uart_regs.v:625-656`). With two characters in a row that have the same
  error, the head's flag does not fall when the first is popped. If LSR
  was read (and cleared) in between, as every driver does, the second
  character's error is not reported.
- **PDF.** LSR[2]: "The character that is currently at the top of the
  FIFO has been received with parity error."
- **Status.** To confirm by simulation (step 4).

### U19: LSR[7] is cleared while errors remain

- **RTL.** `lsr7 = rf_error_bit | rf_overrun` (`uart_regs.v:600`); LSR[7]
  is set on its rising edge and cleared by the LSR read
  (`uart_regs.v:687-689`). After a read with errored characters still in
  the FIFO, LSR[7] is 0 and stays 0 until all of them have left (and U17's
  stale flags are overwritten) and a new error arrives.
- **PDF.** LSR[7]: "'1' – At least one parity error, framing error or
  break indications have been received and are inside the FIFO. The bit is
  cleared upon reading from the register." The two halves conflict; the RTL
  follows the second.
- **NS16550A.** LSR[7] is cleared by the read only if there are no more
  errors in the FIFO.
- **Status.** To confirm by simulation (step 4).

### U20: RDA interrupt lost in the read window

- **RTL.** `rda_int_pnd` is cleared when `fifo_read` (the read strobe) sees
  `rf_count == trigger_level` (`uart_regs.v:814`). The pop is one clock
  later (`uart_regs.v:421-431`). If a push lands in the strobe clock or the
  pop clock, the count goes trigger → trigger+1 → trigger (or stays at the
  trigger), `rda_int` never falls (`uart_regs.v:750`), so there is no new
  rising edge and the flag stays 0. `int_o` falls (`uart_regs.v:846-852`)
  while IIR reads 0xC4 (`uart_regs.v:867`) and the FIFO holds
  trigger-level data. Only TI (4 idle character times) or a read below the
  trigger level and a refill raise it again. Under continuous traffic the
  RX FIFO can overrun.
- **PDF.** RDA reset: "FIFO drops below trigger level".
- **Status.** To confirm by simulation (step 4).

### U21: RDA pending flag stuck

- **RTL.** The only clears of `rda_int_pnd` are an RBR read at
  `rf_count == trigger_level` and IER[0] = 0 (`uart_regs.v:814-816`). If the
  count falls below the trigger level any other way, the flag stays set:
  an RX FIFO reset (FCR[1], `uart_rfifo.v:231-251`), or an FCR write that
  raises the trigger level above the count (`uart_regs.v:507, 560-566`).
  Then `int_o` = 1 (`uart_regs.v:848`), while IIR, which looks at the level,
  reads 0xC1 (or a lower source). A driver that sees "no interrupt" in IIR
  leaves a level interrupt asserted; Linux would disable the line.
- **PDF.** Silent.
- **Status.** To confirm by simulation (step 4).

### U22: MSR deltas in loopback; TERI on both edges

- **RTL.** The deltas compare `{dcd, ri, dsr, cts}`, the inverted pads, with
  their delayed copies (`uart_regs.v:342, 582-585`). MSR[7:4] use the
  loopback-switched `*_c` signals (`uart_regs.v:344-345, 584`). So in
  loopback, MCR changes do not set delta bits, and pad changes still do. RI
  uses the same XOR as the other lines, so TERI is set on both edges.
- **PDF.** MSR[2]: TERI when "the RI line has changed its state from low to
  high".
- **NS16550A.** In loopback the deltas follow the looped-back MCR bits;
  TERI is set on the trailing edge of RI only.
- **Status.** To confirm by simulation (step 4).

### U23: modem pins are active high

- **RTL.** `rts_pad_o = mcr[RTS]`, `dtr_pad_o = mcr[DTR]`
  (`uart_regs.v:351-352`). MSR[7:4] = `{dcd, ri, dsr, cts}_pad_i`, not
  complemented (`uart_regs.v:344-345, 584`). Loopback (RTS → CTS etc.) is
  consistent with active-high pins.
- **PDF.** MCR: "'0' – DTR is '1'; '1' – DTR is '0'" (same for RTS).
  MSR[4..7]: "Complement of the CTS input" etc.
- **Status.** To confirm by simulation (step 4).

### U24: only a DLL write restarts the baud divider

- **RTL.** `start_dlc` is set by a DLL write only (`uart_regs.v:541-547`).
  The counter reloads with `dl - 1` on `start_dlc` or when it reaches 0
  (`uart_regs.v:697-698`). A DLM write after the DLL write takes effect at
  the next reload. After reset, `dl` = 0 and the counter runs from 0xFFFF;
  a DLL write of 0 followed by a DLM write gives a first period of 65536
  clocks. The baud generator also runs regardless of LCR.DLAB.
- **PDF.** §4.9: "The internal counter starts to work when the LSB of DL
  is written, so when setting the divisor, write the MSB first and the
  LSB last." §5.1: the engine starts when DLAB is set back to 0 (not so in
  the RTL).
- **Impact.** Linux writes DLL then DLM. Harmless unless DLL = 0.
- **Status.** To confirm by simulation (step 4).

### U25: DLAB = 1 turns off read side effects

- **RTL.** `lsr_mask_condition`, `iir_read` and `msr_read` all include
  `!dlab` (`uart_regs.v:439-441`), but the read mux returns LSR, MSR and
  IIR in either DLAB state (`uart_regs.v:410-413`). With DLAB = 1 these
  reads return the value and clear nothing.
- **NS16550A.** DLAB affects offsets 0 and 1 only.
- **Status.** To confirm by simulation (step 4).

### U26: TX FIFO reset race

- **RTL.** The transmitter decides to send at an idle tick
  (`uart_transmitter.v:227-237`) and loads the head byte one tick later
  in `s_pop_byte` (`uart_transmitter.v:238-260`) without checking the
  count again. An FCR[2] reset between those ticks empties the FIFO
  (`uart_tfifo.v:204-208`), and the transmitter still sends whatever byte
  the RAM holds at entry 0. If a THR write's push lands in the clock of
  that pop, push and pop with count 0 move both pointers
  (`uart_tfifo.v:222-225`) and the written byte is never sent.
- **PDF.** FCR[2]: the shift register is not cleared. Silent on the race.
- **Status.** To confirm by simulation (step 4). Low priority: plan Q5
  treats a FIFO reset during a transfer as undefined.

## Differences from the PDF

| Item | PDF (rev 0.6) | RTL (U2B0) |
|---|---|---|
| Scratch register | removed | present at 7 (U2) |
| Port names | `CLK`, `WB_ADDR_I` | `wb_clk_i`, `wb_adr_i` |
| `wb_sel_i` in 8-bit mode | listed | present, ignored |
| 32-bit byte lanes | "uses SEL_I to properly receive and return 8-bit data" | big-endian by default; `LITLE_ENDIAN` define not documented (U10) |
| MCR, MSR polarity | pins active low | pins active high (U23) |
| TERI | low-to-high edge of RI | either edge (U22) |
| Overrun | FIFO intact | head byte overwritten (U14) |
| LSR[7] | "inside the FIFO … cleared upon reading" | cleared on read, set only on a new rising edge (U19) |
| RDA clear | "FIFO drops below trigger level" | read at exactly the trigger level (U7, U20, U21) |
| Baud generator start | when DLAB is cleared | when DL ≠ 0, regardless of DLAB (U24) |
| Debug 2 | MCR [18:17], FCR [23:19] | MCR [21:17], FCR [23:22] |
| THRE timing | not described | hold-off (U6) |
| Read side effects with DLAB = 1 | not described | none (U25) |

The PDF and the RTL agree on: register addresses 0–6, IER, IIR encodings
and reset value 0xC1, FCR reset 0xC0 (trigger 14), LCR reset 0x03 and its
bit meanings (including stick parity), DL reset 0 stopping the UART, the
break definition, FIFO-only operation, Debug 1, and `baud_o`.

## Differences from the NS16550A not listed above

- FCR resets to trigger level 14 (NS16550A: FIFOs off, level 1). As the PDF.
- No 16450 mode, no DMA mode, no TXRDY/RXRDY (U3).
- No OUT1/OUT2 pins (U8).
- The WISHBONE access takes 3 clocks plus one idle clock (U13).

## Lint and coding notes

- At `u2b0`: every RTL file includes `timescale.v`, and 348 non-blocking
  assignments carry `#1` (5 more `#Tp` in `uart_sync_flops`).
  `uart_defines.v` has no include guard, yet every file includes it. The
  `u2b0-fw1` patch set fixes these three ({doc}`integration`).
- `int_o`'s THRE term is `!(fifo_write & iir_read)` (`uart_regs.v:850`).
  The two strobes are for different addresses, so it is always 1;
  `!(fifo_write | iir_read)` was probably meant. Effect: on a THR write or
  IIR read `int_o` falls one clock later than for the other sources.
- `sr_rec_prepare` assigns `rcounter16` twice (`uart_receiver.v:323,
  328`); the second wins, and the bit timing depends on it.
- The `counter_t` comment says it is reset "above trigger level"
  (`uart_receiver.v:475`); the code does not do that.
- Unused: `rbit_in` (`uart_receiver.v:225`, assigned only in reset),
  `tf_overrun` (`uart_transmitter.v:183`), the `uart_top` width parameters.
- `dl` and `dlc` are commented as 32-bit; they are 16-bit
  (`uart_regs.v:309, 315`).
- `raminfr` has no reset. In 4-state simulation RBR reads X until the
  entry is written.
- `uart_top` prints its configuration from an `initial` block
  (`uart_top.v:324-336`).

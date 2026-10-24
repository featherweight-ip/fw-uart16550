# Verification status

Every item in {doc}`deviations` except U10 (the 32-bit configuration,
step 11) was confirmed on the `ref` view on 2026-10-24. Each test asserts
the behaviour recorded there, so it fails if U2B0 does anything else.

The `ref` view (`dfm run tests`; bench plan in
{doc}`../design/ref-bench`) is U2B0 behind the 32-bit shim, on Verilator.
Around it:

- a fw-proto-wb initiator on the register port, which leaves an idle clock
  between accesses (so U13 never happens by accident);
- a bench driver that can start an access in the clock after the previous
  ack (for U13 only);
- the fwvip-uart agents on `srx` and `stx`, with a monitor on each line;
- the modem input pads, and an `srx` override, driven from the test clock
  by clock;
- a probe that samples the core's internals every clock: register strobes,
  FIFO counts, pushes and pops, LSR, the pending flags, `block_cnt`, the
  receiver and transmitter states, and the baud divider.

## Results

| Test (`ref-…`) | Items | What it does |
|---|---|---|
| `regs` | reset values, U1, U2, U3, U25 | register reads and writes in both DLAB states |
| `modem` | U8, U9, U22, U23 | pads and MCR in normal and loopback mode |
| `bus` | U13 | two writes and two RBR reads with 0 and 1 idle clocks between them |
| `baud` | U24 | tick intervals after DLL and DLM writes, from reset and from DL = 0 |
| `rx-fifo` | U5, U14, U18, U19, U16, U17 | overrun; two errored characters in a row; an RBR read swept over 48 clock offsets of a push (U16, U17) |
| `irq` | U21, U20, U7 | RX FIFO reset and trigger raise with RDA pending; an RBR read at the trigger level swept over 48 offsets of a push (U20) |
| `tx` | U6, U11, U15, U26 | THRE measured for six framings; 18 writes to a slow transmitter; a TX FIFO reset in `s_pop_byte`, and a THR write swept over 32 offsets of the pop (U26) |
| `rx` | U4, U12 | `srx` driven by the test: a one-clock pulse at each of 16 positions in a bit; breaks after a clean and after an FE character |

The swept tests find the clock where the race happens from the probe (a
push and a pop in one clock), not from a computed bus latency. Each also
checks the cases next to that clock, where the race does not happen.
Offsets that hit: U16 and U17 at 5 clocks after the receiver entered its
stop-bit state, U20 at 5 and 6, U26 at 24 clocks after the TX FIFO reset
(divisor 32).

**Teeth.** With each of four mutations of the reference RTL, exactly the
test meant to catch it failed:

| Mutation | Failed |
|---|---|
| MCR readable (U1) | `ref-regs` |
| RX FIFO RAM write gated by the count (no U14) | `ref-rx-fifo` |
| `int_o` from the RDA level instead of the pending flag (no U20/U21) | `ref-irq` |
| `block_value` 150 instead of 143 for LCR[3:0] = 1101 | `ref-tx` |

## Upstream testbench

The repository's bench at U2B0 (`bench/verilog/uart_testbench.v`,
`uart_device.v`, `wb_master_model.v`, one test case
`test_cases/uart_int.v`) is a self-checking interrupt test, with NC-Verilog
scripts (`sim/rtl_sim/run/`). The shipped report log records one failure.

`scripts/upstream-bench.sh` re-ran it on 2026-10-21 under Icarus, with two
bench-only `#0` race workarounds. With `DATA_BUS_WIDTH_8` it reproduces the
shipped report exactly, on `u2b0` and `u2b0-fw1`. In the default 32-bit
configuration it fails at initialization (U10). See U11 for the analysis.

## Confirmation tests as planned (step 4)

Probes: the `ref` top should export the core's register strobes
(`we_o`, `re_o`), `enable`, `rf_count`, `tf_count`, the pending flags and
`block_cnt`, so a test can place an access in a given clock relative to a
push or a pop.

| Item | Method |
|---|---|
| U1, U2, U3 | Register test: write and read every offset in both DLAB states; MCR reads 0; SCR holds data; IIR[7:6] = 11 with FCR[0] = 0 |
| U4 | Drive characters with a single-tick glitch at, and away from, tick 7 of a bit; only the tick-7 sample decides |
| U5, U14 | Fill the RX FIFO, send one more character; check OE, the count, and the byte and flags read first |
| U6 | Write THR to an idle transmitter; measure THRE against `block_value` for several LCR formats |
| U7, U20 | Trigger level 4: read RBR at count 4 with a character pushed in the read and pop clocks; check `int_o` and IIR |
| U21 | RDA pending, then FCR RX reset (and, separately, raise the trigger level); check `int_o` = 1 with IIR = 0xC1 |
| U8, U22 | Loopback: toggle MCR and the pads; check the pads, MSR[7:4] and MSR[3:0] |
| U9 | Functional only: pad changes set deltas |
| U10 | Step 11, `ref-rtl-32`: accesses with each `sel` value, both endian settings |
| U11 | The `ref` view's THRE timing after a single write equals U6 (no other delay) |
| U12 | Hold the line low for less than and more than one character time after a character; check the FIFO contents, BI and FE |
| U13 | Two accesses with 0 and 1 idle clocks between them; the first case must show the second access with no effect |
| U15 | 17 THR writes with the transmitter blocked (DL large); check the bytes sent |
| U16 | RBR read on an empty FIFO whose pop lands in a push clock; check the character lost and DR stuck |
| U17, U18, U19 | Two errored characters in a row; read LSR and RBR as a driver does; check PE/FE/BI and LSR[7] for the second |
| U23 | Pin levels against MCR and MSR |
| U24 | DLL then DLM, with DLL = 0; measure the first tick |
| U25 | LSR, MSR and IIR reads with DLAB = 1 clear nothing |
| U26 | FCR[2] in the window between idle and pop_byte; check the byte sent |

Timing statements in {doc}`timing` confirmed by these tests: the THRE
hold-off table (six rows), the DLL restart (first tick DL + 2 clocks after
the write strobe), and the break time (U12). The others (TX latency, TEMT,
the RX sample points per bit, TI) are still **(to confirm)**; the probe
and the fwvip-uart monitor make them a small addition.

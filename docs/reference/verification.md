# Verification status

Nothing in this specification has been confirmed on the `ref` view yet.
The `ref` view (step 4: dfm flow on Verilator, fwvip-wb initiator on the
shim, fwvip-uart on the serial and modem pins) will run one directed test
per item in {doc}`deviations`, as fw-i2c did for D1–D10. Each test asserts
the behaviour recorded there, so it fails if U2B0 does anything else. The
results go into the status column of {doc}`deviations`.

## Upstream testbench

The repository's bench at U2B0 (`bench/verilog/uart_testbench.v`,
`uart_device.v`, `wb_master_model.v`, one test case
`test_cases/uart_int.v`) is a self-checking interrupt test, with NC-Verilog
scripts (`sim/rtl_sim/run/`). The shipped report log records one failure.

`scripts/upstream-bench.sh` re-ran it on 2026-10-21 under Icarus, with two
bench-only `#0` race workarounds. With `DATA_BUS_WIDTH_8` it reproduces the
shipped report exactly, on `u2b0` and `u2b0-fw1`. In the default 32-bit
configuration it fails at initialization (U10). See U11 for the analysis.

## Planned confirmation tests (step 4)

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

Timing statements marked **(to confirm)** in {doc}`timing` (TX latency,
TEMT, RX sampling points, TI and break times) are checked with the
fwvip-uart monitor in the same tests.

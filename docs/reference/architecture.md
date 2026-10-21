# Architecture

The core is ten modules. All are clocked by `wb_clk_i` and reset
asynchronously by `wb_rst_i`.

```
uart_top
├── uart_wb               WISHBONE slave
├── uart_regs             registers, baud generator, LSR/MSR, interrupts
│   ├── uart_transmitter
│   │   └── uart_tfifo
│   │       └── raminfr   16 x 8
│   ├── uart_sync_flops   srx_pad_i synchronizer
│   └── uart_receiver
│       └── uart_rfifo
│           └── raminfr   16 x 8
└── uart_debug_if         32-bit configuration only
```

| Module | Lines | Contents |
|---|---|---|
| `uart_top` | 340 | Ports and instances only. Selects the 8- or 32-bit `uart_wb` hookup and the debug interface by `DATA_BUS_WIDTH_8` |
| `uart_wb` | 317 | Input registers for adr, dat, we, cyc, stb, sel; the 2-bit ack FSM and `wre`; registered `wb_dat_o`; in 32-bit mode the byte-lane mux and the address LSBs from `wb_sel_i` |
| `uart_regs` | 893 | IER (4), LCR (8), FCR (2), MCR (5), SCR (8), DL (16); baud counter `dlc` (16) and `enable`; LSR flops (8, plus 8 delay flops for edge detection); MSR (8) and 4 delayed modem inputs; `msi_reset`, `lsr_mask_d`, `rf_pop`, `tf_push`, `start_dlc`, `rx_reset`, `tx_reset`; THRE hold-off `block_cnt` (8); 5 interrupt delay flops and 5 pending flags; IIR (4); `int_o`; the read mux |
| `uart_transmitter` | 351 | TX FSM (3 bits, 6 states); 5-bit tick counter; 3-bit bit counter; 7-bit shift register and `bit_out`; parity; `stx_o_tmp`; `tf_pop`; the break gate |
| `uart_tfifo` | 243 | 4-bit `top` and `bottom`, 5-bit count, an unused overrun flag; one `raminfr` 16×8 |
| `uart_receiver` | 482 | RX FSM (4 bits, 11 states); 4-bit tick counter `rcounter16`; 3-bit bit counter; 8-bit shift register; parity and framing flags; 11-bit `rf_data_in`; `rf_push` and its edge detector; break counter `counter_b` (8); timeout counter `counter_t` (10) |
| `uart_rfifo` | 320 | 4-bit `top` and `bottom`, 5-bit count, overrun flag; error flags 16×3 in flops (with reset); data 16×8 in `raminfr`; the 48-input OR for `error_bit` |
| `raminfr` | 111 | 16×W array: synchronous write, asynchronous read, no reset |
| `uart_sync_flops` | 122 | Two flops, reset to 1 (parameterized width, used with width 1) |
| `uart_debug_if` | 126 | Combinational 32-bit mux of internal state for byte addresses 8 and 12 |
| `uart_defines` | 247 | Defines: configuration, register addresses, bit positions, FIFO sizes, bench verbosity |

Line counts are at `u2b0` and include the header comments.

## WISHBONE interface (`uart_wb`)

Described in {doc}`interface`. It turns a registered cycle into a
one-clock `we_o` or `re_o` strobe and an ack one clock later. `uart_regs`
sees the registered address (`wb_adr_int`) and the registered write data
(`wb_dat8_i`).

## Register block (`uart_regs`)

Everything that software sees lives here, except the FIFO contents and
the transmitter and receiver FSMs:

- The **read mux** is combinational on the registered address and DLAB
  (`uart_regs.v:404-417`). `uart_wb` registers its output.
- **Writes** decode the registered address with `we_o`
  (`uart_regs.v:475-557`). DLAB steers offsets 0 and 1.
- **Read strobes** with side effects are decoded with `re_o` and
  `!dlab` (`uart_regs.v:433-443`): `fifo_read`, `lsr_mask_condition`,
  `iir_read`, `msr_read`, and `fifo_write` for THR.
- **LSR** is eight set/clear flops, each set on a rising edge of a
  condition from the FIFOs and the transmitter (`uart_regs.v:590-689`).
- **MSR** samples the modem pads (or the loopback signals) every clock
  and accumulates deltas (`uart_regs.v:572-587`).
- The **baud generator** and the **THRE hold-off** are counters on the
  tick (`uart_regs.v:691-742`).
- The **interrupt logic** is a condition, a delay flop and a pending flag
  per source, then the IIR priority encoder and `int_o`
  (`uart_regs.v:745-891`).

## Transmitter and receiver

Each is an FSM that advances only on ticks, with its FIFO inside it. The
transmitter pops; `uart_regs` pushes (`tf_push`, with the registered
WISHBONE write data). The receiver pushes; `uart_regs` pops (`rf_pop`).
The FSMs are drawn in {doc}`operation`, and their bit timing is in
{doc}`timing`. The receiver also holds the break and timeout counters,
which `uart_regs` reads (`counter_t`) for the TI interrupt.

## Storage

About half of the flops are FIFO storage: the two 16×8 `raminfr` arrays
(256 bits) and the RX error flags (48 bits). `raminfr` reads
asynchronously, so it maps to distributed (LUT) RAM on FPGAs that have it,
and to flops otherwise. iCE40 has no LUT RAM, and its block RAM reads
synchronously, so on iCE40 both arrays become flops plus read muxes
({doc}`synthesis`, plan decision D4).

## Size by module

Yosys 0.69, `synth_ice40 -device u -noflatten`, `DATA_BUS_WIDTH_8`
(`scripts/synth-baseline.sh ... 8`). Each row is the module's own cells,
without its submodules; `raminfr` is instantiated twice. Hierarchy kept, the
total (854 LUT4) is above the flattened median of 820 in {doc}`synthesis`,
and the flop total (555) differs from the flattened 564, because
Yosys optimizes differently with hierarchy kept.

| Module | Flops | SB_LUT4 | SB_CARRY |
|---|---|---|---|
| `uart_wb` | 27 | 5 | 0 |
| `uart_regs` (registers, divider, IIR, timeout, modem) | 118 | 218 | 39 |
| `uart_sync_flops` | 2 | 2 | 0 |
| `uart_transmitter` | 22 | 52 | 4 |
| `uart_tfifo` (control) | 14 | 29 | 10 |
| `uart_receiver` | 54 | 129 | 17 |
| `uart_rfifo` (control and the 16×3 error flags) | 62 | 139 | 10 |
| `raminfr` ×2 (16×8 array and asynchronous read mux) | 2 × 128 | 2 × 140 | 0 |
| Total | 555 | 854 | 80 |

FIFO storage, the two `raminfr` instances, is 280 LUT4 and 256 flops: a
third of the LUT4 and almost half of the flops. In the 32-bit
configuration `uart_wb` grows to 79 flops and 69 LUT4, `uart_regs` to 223
LUT4, and `uart_debug_if` adds 59 LUT4.

# Sphinx documentation (plan and status)

The repo's docs are a Sphinx project in `docs/`. The MyST Markdown pages that
were already here are kept as they are. The SystemVerilog design and
testbench are documented from their sources by `sphinx-systemverilog`
(pyslang). A fresh session can pick up from this file.

## Shape

- `docs/conf.py`: MyST, furo, `sphinx_systemverilog`. The build units are the
  wb and ref sim images' compile lists (UVM, fw-hdl, the WB and UART kits,
  fwvip, the generated register packages, the design, the bench). Only this
  repo's code is documented; the rest is parsed only so that names resolve.
- `docs/index.md`: the root: the fw-uart16550 design, the source reference,
  the U2B0 reference specification, results.
- `docs/api/`: the source reference.
  - `design.rst`: `fw_uart16550_spl_pkg` (the class model),
    `fw_uart16550_spl_rtl_pkg`, `fw_uart16550_top`, `fw_uart16550_xtor_if`,
    `fw_uart16550_sync`, the register packages.
  - `ref.rst`: the `ref` view's shim `oc_uart16550_wb32`.
  - `testbench.rst`: the env and tests packages, the arm, the HDL/HVL tops,
    with the UVM views (`sv:uvm-tree`, `sv:uvm-schematic`, `sv:uvm-binding`,
    `sv:uvm-config`).
- `dfm run docs`: `sphinx-build -W` after the register packages are
  generated. `make -C docs html` for a quick build.

## Steps

| # | What | Status |
|---|---|---|
| D1 | `sphinx-systemverilog` in `ivpm.yaml`; `conf.py`, `Makefile`, root `index.md`; the existing pages build | done 2026-10-24: also sphinx-peakrdl, wavedrom, mermaid (as fw-i2c) |
| D2 | `api/design.rst`, `api/ref.rst` | done 2026-10-24 |
| D3 | `api/testbench.rst` with the UVM views | done 2026-10-24: no `sv:uvm-binding` (no `config_db #(virtual ...)` in the bench) |
| D4 | Doc comments in the sources, where autodoc shows a member with none or a comment renders badly | done 2026-10-24: model, pin package, arm, env, base tests. Rules that came out of it: (a) a banner (`// ---- x ----`) documents the next member even across a blank line, so that member needs its own comment; (b) a trailing comment that runs onto the next line documents the next declaration as well; (c) a column table in a comment runs together, so use bullets (`- ``a``: b`); (d) a line starting `(a)` starts a list. Left: the generated register packages' banners (peakrdl-fw-hdl output) |
| D5 | `dfm run docs` with `-W`: no warnings | done 2026-10-24 (`docs-build` needs `reg-model`) |

## Status notes

- **sphinx-systemverilog fixes (needed here, not yet upstream).** In the
  fvutils clone (`../../fvutils/sphinx-systemverilog`), branch
  `fix/utf8-offsets-compilation-flags`, uncommitted; installed editable into
  `packages/python`. Two fixes: (1) signature text was sliced from decoded
  source by slang's byte offsets, so every multi-byte character (`§`) shifted
  later ports (`nput wire clock,`); (2) a new `sv_compilation_flags` setting,
  used here for `DisableInstanceCaching`. Tests: 803 pass; the 4 new ones
  fail without the fix. Until it is released, `ivpm update` installs the
  unfixed main.
- **slang false positive** (why the flag): a virtual interface taken from the
  second of two identically parameterized wrapper instances, whose interface
  has a port sized by a derived parameter, reports "cyclic dependency"
  (shared cached body). Legal code; Verilator accepts it. Repro in the
  sphinx-systemverilog test `tests/model/test_compilation_flags.py`.
- **RDL root.** sphinx-peakrdl elaborates one root: `docs/_rdl/u2b0_docs.rdl`
  holds both U2B0 maps, the DLAB = 1 bank at a docs-only 0x100
  (noted on `reference/registers.md`).

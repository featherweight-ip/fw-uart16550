# fw-uart16550

A 16550 UART written with fw-hdl, verified against the freecores
(OpenCores) `uart16550` core (U2B0) and compared with it for area. Plan and
status: [`docs/design/plan.md`](docs/design/plan.md). The reference core as
built: [`docs/reference/`](docs/reference/).

```sh
ivpm update
uv pip install --python packages/python/bin/python -e packages/fw-hdl/python   # once
direnv allow

dfm run tests        # every simulation case (step 4: the `ref` view)
dfm run smoke        # the smoke case on every view
dfm run lint-rtl     # Verilator lint, zero findings (lint-waivers.yaml)
```

# fw-uart16550

A 16550-compatible UART written as an fw-hdl class model and lowered to
RTL. Its reference is the OpenCores uart16550 core at revision U2B0. Both
cores run behind the same 32-bit Wishbone shim and the same UVM bench, on
four views:

| View | What runs |
|---|---|
| `ref` | U2B0, the reference core |
| `wb` | the class model, behind the kits' pin transactors |
| `rtl` | the class model lowered to a netlist |
| `tlm` | the class model through its method ports, with no pins |

```{toctree}
:maxdepth: 2
:caption: fw-uart16550

design/index
api/index
results
```

```{toctree}
:maxdepth: 2
:caption: The reference core

reference/index
```

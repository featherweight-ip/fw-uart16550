# Sphinx configuration for the fw-uart16550 documentation
# (docs/design/sphinx-docs.md).
#
# Build:  dfm run docs              (sphinx-build -W: a warning fails the build)
#    or:  make -C docs html SPHINXBUILD=../packages/python/bin/sphinx-build
# The source reference (api/) is generated from the SystemVerilog by
# sphinx-systemverilog. It needs the generated register packages: run
# `dfm run reg-model` once first, or use `dfm run docs`, which does.

import os

_here = os.path.dirname(os.path.abspath(__file__))
_root = os.path.dirname(_here)
_pkgs = os.environ.get("IVPM_PACKAGES", os.path.join(_root, "packages"))
_rundir = os.environ.get("FW_UART16550_RUNDIR", os.path.join(_root, "rundir"))


def _p(*parts):
    return os.path.join(*parts)


_uvm = _p(_pkgs, "verilator", "share", "uvm", "src")
_fw_hdl = _p(_pkgs, "fw-hdl", "src")
_wb = _p(_pkgs, "fw-proto-wb", "src")
_uart = _p(_pkgs, "fw-proto-uart", "src")
_vip_core = _p(_pkgs, "fwvip-core", "src")
_vip_uart = _p(_pkgs, "fwvip-uart", "src", "uvm")
_u2b0 = _p(_pkgs, "oc-uart16550", "rtl", "verilog")
_src = _p(_root, "src")
_tb = _p(_root, "tests", "uvm")

# -- Project information -----------------------------------------------------

project = "fw-uart16550"
copyright = "2026, Featherweight-HDL"
author = "Featherweight-HDL"
release = "0.1.0"

# -- General configuration ---------------------------------------------------

extensions = [
    "myst_parser",
    "sphinx_copybutton",
    "sphinx.ext.graphviz",
    "sphinx_systemverilog",
    "sphinx_peakrdl",
    "sphinxcontrib.wavedrom",
    "sphinxcontrib.mermaid",
]

source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "fieldlist",
]
myst_heading_anchors = 3

exclude_patterns = [
    "_build",
    "Thumbs.db",
    ".DS_Store",
]

# -- Registers (sphinx-peakrdl) ----------------------------------------------
#
# The U2B0 reference maps (reference/registers.md). sphinx-peakrdl elaborates
# one root, so _rdl/u2b0_docs.rdl puts the DLAB = 0 map and the DLAB = 1 bank
# under one.

peakrdl_input_files = [_p(_here, "_rdl", "u2b0_docs.rdl")]
peakrdl_incdirs = [_p(_root, "src", "rdl")]
peakrdl_top_component = "u2b0_docs"
peakrdl_default_link_to = "doc"
peakrdl_html_enable = False

# -- Timing diagrams (sphinxcontrib-wavedrom) ---------------------------------
# Rendered to SVG at build time by the Python wavedrom package, so the HTML
# needs no JavaScript and the build works offline.
render_using_wavedrompy = True

# -- SystemVerilog sources ---------------------------------------------------
#
# The wb and ref sim images' compile lists (tests/uvm/flow.yaml), in compile
# order. UVM, fw-hdl, the kits and fwvip are parsed only so that names
# resolve; they are documented in their own projects. The lowered netlist
# (the rtl view) is generated and is not parsed.

sv_build_units = [
    # UVM, fw-hdl, the kits and the VIP (for resolution only)
    _p(_uvm, "uvm_pkg.sv"),
    _p(_fw_hdl, "fw_hdl_pkg.sv"),
    _p(_fw_hdl, "fw_clock_xtor_if.sv"),
    _p(_fw_hdl, "fw_clock_period_xtor_if.sv"),
    _p(_fw_hdl, "fw_clock_period_xtor.sv"),
    _p(_fw_hdl, "fw_root.sv"),
    _p(_fw_hdl, "std", "fw_std_pkg.sv"),
    _p(_fw_hdl, "std", "fw_put_xtor_if.sv"),
    _p(_wb, "fw_proto_wb_pkg.sv"),
    _p(_wb, "wb_proto_checker.sv"),
    _p(_wb, "wb_initiator_xtor_if.sv"),
    _p(_wb, "wb_initiator_xtor_core.sv"),
    _p(_wb, "wb_initiator_xtor.sv"),
    _p(_wb, "wb_target_xtor_if.sv"),
    _p(_wb, "wb_target_xtor_core.sv"),
    _p(_wb, "wb_target_xtor.sv"),
    _p(_wb, "wb_monitor_xtor_if.sv"),
    _p(_wb, "wb_monitor_xtor_core.sv"),
    _p(_wb, "wb_monitor_xtor.sv"),
    _p(_uart, "fw_proto_uart_pkg.sv"),
    _p(_uart, "uart_baud_xtor_core.sv"),
    _p(_uart, "uart_tx_xtor_if.sv"),
    _p(_uart, "uart_tx_xtor_core.sv"),
    _p(_uart, "uart_tx_xtor.sv"),
    _p(_uart, "uart_rx_xtor_if.sv"),
    _p(_uart, "uart_rx_xtor_core.sv"),
    _p(_uart, "uart_rx_xtor.sv"),
    _p(_uart, "uart_monitor_xtor_if.sv"),
    _p(_uart, "uart_monitor_xtor_core.sv"),
    _p(_uart, "uart_monitor_xtor.sv"),
    _p(_uart, "uart_proto_checker.sv"),
    _p(_vip_uart, "fwvip_uart_xtor_pkg.sv"),
    _p(_vip_core, "sv", "fwvip_core_pkg.sv"),
    _p(_vip_core, "uvm", "fwvip_core_uvm_pkg.sv"),
    _p(_vip_uart, "fwvip_uart_pkg.sv"),
    _p(_vip_core, "sv", "fwvip_clock_xtor_if.sv"),
    _p(_vip_core, "sv", "fwvip_reset_xtor_if.sv"),
    # U2B0, the reference core (for resolution only)
    _p(_u2b0, "raminfr.v"),
    _p(_u2b0, "uart_receiver.v"),
    _p(_u2b0, "uart_regs.v"),
    _p(_u2b0, "uart_rfifo.v"),
    _p(_u2b0, "uart_sync_flops.v"),
    _p(_u2b0, "uart_tfifo.v"),
    _p(_u2b0, "uart_top.v"),
    _p(_u2b0, "uart_transmitter.v"),
    _p(_u2b0, "uart_wb.v"),
    # the design: generated register packages, the class model, the pin top
    _p(_rundir, "org.fwip.uart16550.reg-model-main", "fw_uart16550_reg_pkg.sv"),
    _p(_rundir, "org.fwip.uart16550.reg-model-dlab", "fw_uart16550_dlab_reg_pkg.sv"),
    _p(_src, "spl", "fw_uart16550_spl_pkg.sv"),
    _p(_src, "spl-rtl", "fw_uart16550_sync.sv"),
    _p(_src, "spl-rtl", "fw_uart16550_xtor_if.sv"),
    _p(_src, "spl-rtl", "fw_uart16550_spl_rtl_pkg.sv"),
    _p(_src, "spl-rtl", "fw_uart16550_top.sv"),
    # the ref view's shim
    _p(_src, "ref", "oc_uart16550_wb32.sv"),
    # the bench
    _p(_tb, "env", "fw_uart16550_env_pkg.sv"),
    _p(_tb, "tests", "fw_uart16550_tests_pkg.sv"),
    _p(_tb, "tb", "uart_ref_pads_if.sv"),
    _p(_tb, "tb", "uart16550_arm.sv"),
    _p(_tb, "tb", "hdl_top_wb.sv"),
    _p(_tb, "tb", "hvl_top_wb.sv"),
    _p(_tb, "tb", "hdl_top_ref.sv"),
    _p(_tb, "tb", "hvl_top_ref.sv"),
    _p(_tb, "tb", "fw_uart16550_tlm_view_pkg.sv"),
    _p(_tb, "tb", "hdl_top_tlm.sv"),
    _p(_tb, "tb", "hvl_top_tlm.sv"),
]

sv_include_dirs = [
    _uvm,
    _fw_hdl,
    _p(_fw_hdl, "std"),
    _wb,
    _uart,
    _vip_uart,
    _p(_vip_core, "sv"),
    _p(_vip_core, "uvm"),
    _u2b0,
    _p(_src, "spl"),
    _tb,
    _p(_tb, "env"),
    _p(_tb, "tests"),
    _p(_tb, "tb"),
]

sv_defines = {
    "UVM_HDL_NO_DPI": "",
    "DATA_BUS_WIDTH_8": "",
}

# The HVL tops instance the HDL tops, so these two are the whole bench.
sv_structure_tops = ["hvl_top_wb", "hvl_top_ref", "hvl_top_tlm"]

# slang (9-12) reports a false "cyclic dependency" for the kit interfaces'
# derived width parameters when a virtual interface is taken from the
# second of two identical transactor instances (the arm's u_mon_tx and
# u_mon_rx); its instance cache shares their bodies. Verilator accepts the
# code, and so does slang without the cache.
sv_compilation_flags = ["DisableInstanceCaching"]

sv_doc_style = "auto"
sv_default_options = {}

toc_object_entries_show_parents = "hide"

# -- Options for HTML output -------------------------------------------------

html_theme = "furo"
html_title = "fw-uart16550"

graphviz_output_format = "svg"

# Untagged code fences are plain text, so ASCII diagrams do not fail
# Pygments under -W.
highlight_language = "text"
pygments_style = "friendly"
pygments_dark_style = "monokai"

suppress_warnings = ["misc.highlighting_failure"]

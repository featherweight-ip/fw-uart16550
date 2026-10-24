#########
Testbench
#########

One UVM env and one set of tests run on every view. A view is a pair of
tops: the HDL top instances the DUT and the arm, and the HVL top starts UVM.
See :doc:`/design/ref-bench`.

The bench as built
==================

What ``fw_uart16550_base_test`` builds:

.. sv:uvm-tree:: fw_uart16550_base_test

How the env is wired:

.. sv:uvm-schematic:: fw_uart16550_env

The HVL top hands the bench its interfaces in two ways, neither a
``uvm_config_db #(virtual ...)::set`` (so there is no binding table here):

- the Wishbone initiator's ``u_if`` and the pads go into the model object
  (``model.vwb``, ``model.vpads``), and the model goes into ``config_db``;
- the UART transactors' ``u_if``, the clock and the reset go through fwvip's
  ``*_config_p #(virtual ...)::set``, which files a config object holding the
  handle (the ``fwvip_uart_*_register`` macros).

What is passed through ``config_db``:

.. sv:uvm-config::

The tops
========

.. autosvmodule:: hdl_top_wb
   :members:
   :show-instances:

.. autosvmodule:: hvl_top_wb
   :members:

.. autosvmodule:: hdl_top_ref
   :members:
   :show-instances:

.. autosvmodule:: hvl_top_ref
   :members:

.. autosvmodule:: hdl_top_tlm
   :members:
   :show-instances:

.. autosvmodule:: hvl_top_tlm
   :members:

The tlm view
============

The bench against the class model's method ports, with no pins (see
:doc:`/design/tlm-view`).

.. autosvpackage:: fw_uart16550_tlm_view_pkg

.. autosvclass:: fw_uart16550_tlm_view_pkg::fw_uart16550_tlm_top
   :members:
   :undoc-members:

.. autosvclass:: fw_uart16550_tlm_view_pkg::fw_uart16550_tlm_rf
   :members:

.. autosvclass:: fw_uart16550_tlm_view_pkg::uart_tlm_model
   :members:

.. autosvclass:: fw_uart16550_tlm_view_pkg::uart_tlm_line
   :members:

.. autosvclass:: fw_uart16550_tlm_view_pkg::uart_tlm_baud
   :members:

.. autosvclass:: fw_uart16550_tlm_view_pkg::fwvip_uart_tlm_tx_config
   :members:

The arm
=======

The arm holds what both views share: the Wishbone initiator, the UART VIP's
transactors, the pads and a back-to-back driver.

.. autosvmodule:: uart16550_arm
   :members:
   :show-instances:

.. autosvmodule:: uart_ref_pads_if
   :members:

.. autosvmodule:: wb_b2b_driver
   :members:

The env
=======

.. autosvpackage:: fw_uart16550_env_pkg

.. autosvclass:: fw_uart16550_env_pkg::fw_uart16550_env
   :members:
   :undoc-members:

.. autosvclass:: fw_uart16550_env_pkg::uart_model_base
   :members:
   :undoc-members:

.. autosvclass:: fw_uart16550_env_pkg::uart_ref_model
   :members:
   :undoc-members:

.. autosvclass:: fw_uart16550_env_pkg::uart_ref_probe
   :members:
   :undoc-members:

The tests
=========

.. autosvpackage:: fw_uart16550_tests_pkg

.. sv:inheritance-diagram:: fw_uart16550_tests_pkg::fw_uart16550_base_test

Shared tests (every view)
-------------------------

.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_base_test
   :members:
   :undoc-members:

.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_smoke_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_regs_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_line_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_status_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_irq_test
   :members:

.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_stream_test
   :members:

.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_tx_op_seq
   :members:

.. sv:uvm-sequence:: fw_uart16550_tx_op_seq

Reference confirmation tests (ref view)
---------------------------------------

These confirm the behaviour that :doc:`/reference/index` describes, on U2B0
itself.

.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_base_test
   :members:
   :undoc-members:

.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_regs_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_bus_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_baud_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_tx_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_rx_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_rx_fifo_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_irq_test
   :members:
.. autosvclass:: fw_uart16550_tests_pkg::fw_uart16550_ref_modem_test
   :members:

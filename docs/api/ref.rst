###############
The ref view
###############

U2B0 is an 8-bit Wishbone core. The shim puts it behind the same 32-bit,
4-byte-stride Wishbone port as ``fw_uart16550_top``, so that one bench drives
both. See :doc:`/design/ref-bench`.

.. autosvmodule:: oc_uart16550_wb32
   :members:
   :show-instances:
   :show-used-by:

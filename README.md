# eMMC / iNAND Controller UVM Verification Environment

An UVM testbench designed for block-level verification of an eMMC/iNAND memory controller interface. The environment focuses on accurate protocol compliance, reactive monitoring, and end-to-end data integrity checking.

---

## 🚀 Key Features & Highlights
* **Protocol-Aware Monitor**: Eliminates race conditions and off-by-one phase shift errors by combining reactive handshake synchronization (`while` loop on `wr_en`/`dat_vld`) with deterministic 512-byte payload burst collection (`for` loop).
* **Modular UVM Architecture**: Fully decoupled stimulus generation, driving, monitoring, and scoreboard checking.
* **Automated Scoreboard & Reference Model**: Maintains an LBA-indexed reference memory model to cross-check read data streams against previous writes down to the exact byte.
* **UVM Factory Integration**: Utilizes factory registration (``uvm_object_utils`) and dynamic object creation (`type_id::create`) to ensure flexibility and scalability.

---

## 🏗️ Architectural Overview

### DUT Interface Protocol
The Design Under Test (DUT) communicates via a synchronous, 512-byte block-based command-and-data protocol:
* **Command Path**: `cmd_stb`, `cmd_code`, and `lba` (Logical Block Address) for initiating transactions (e.g., `CMD17` Read, `CMD24` Write).
* **Write Path**: Gated by `wr_en` handshaking and streaming `dat_in` payloads.
* **Read Path**: Flow-controlled via `dat_vld`, `dat_out`, and `ready` signals.

### UVM Environment Hierarchy
```text
+-------------------------------------------------------------+
|                     UVM Testbench Environment               |
|                                                             |
|  +----------------+    +----------------+    +-----------+  |
|  |    Sequence    | -> |  Driver (TX)   | -> | Virtual   |  |
|  +----------------+    +----------------+    | Interface |  |
|                                              | (drv_cb / |  |
|  +----------------+    +----------------+    |  mon_cb)  |  |
|  |   Scoreboard   | <- | Monitor (RX)   | <- |           |  |
|  | (Ref. Model)   |    | (Lock & Burst) |    +-----------+  |
|  +----------------+    +----------------+          |        |
+----------------------------------------------------|--------+
                                                     v
+-------------------------------------------------------------+
|                     DUT: eMMC Controller                    |
+-------------------------------------------------------------+

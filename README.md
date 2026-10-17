# APB UART (16550-compatible) — RTL to GDSII on SKY130 with IndepthSilicon

**`apb_uart` taken from RTL to a signed-off GDSII layout by the IndepthSilicon flow, in one run, at a 15 ns clock (66.7 MHz) on SkyWater SKY130 (`sky130_fd_sc_hd`). Every sign-off number below was re-measured on the shipped layout by independent, widely used open-source sign-off tools, and every one of them is at zero.**

A 16550-compatible UART with an APB3 slave interface: 16-byte TX and RX FIFOs, programmable baud-rate divisor, line control (word length, stop bits, parity) and TX-empty / RX-ready / line-error interrupts.

## Result at a glance

| Check (on the shipped layout) | IndepthSilicon | Independent tool |
|---|---:|---:|
| Design-rule check | **0** violations | **0** — SKY130 foundry rule deck |
| Layout vs schematic | **match** (2,165 / 2,165 nets) | **match** — 2,116 devices |
| Antenna | **0** | **0** nets, **0** pins |
| Setup timing, 3 corners | **met** (worst 1.515 ns) | **met** (worst 1.524 ns) |
| Hold timing, 3 corners | **met** (worst 0.100 ns) | **met** (worst 0.097 ns) |
| Max slew / capacitance / fanout | **0 / 0 / 0** | **0 / 0 / 0** |
| Shipped netlist equal to RTL | **proven** (435 / 435 compare points) | **proven** (953 compare points) |

## Layout

| | |
|---|---|
| ![floorplan](images/01_floorplan.png) | ![placement](images/02_placement.png) |
| **Floorplan** — die, standard-cell rows, I/O pins | **Placement** — placed cells after clock-tree build |
| ![routing](images/03_routing.png) | ![final layout](images/04_final_layout.png) |
| **Routing** — 5 metal layers, before fill | **Final layout** — the shipped GDSII, filler cells and metal fill included |

## Stage-by-stage comparison

Three columns, for the same RTL and the same 15 ns clock:

* **IndepthSilicon** — what the IndepthSilicon flow reports about its own result.
* **Independent tool** — the IndepthSilicon layout and netlist re-measured by an independent open-source sign-off tool (which tool is listed under *How the independent numbers were produced*).
* **Reference flow** — the same RTL taken through the open-source LibreLane 3.0.1 flow (OpenROAD-based), default configuration, same PDK and clock. It is a separate implementation of the same design, shown for scale.

| Stage | Metric | IndepthSilicon | Independent tool | Reference flow |
|---|---|---:|---:|---:|
| RTL read-in | gates / registers after elaboration | 4,370 / 399 | — | — |
| Synthesis | mapped cells | 1,492 | — | 1,350 |
| Synthesis | cell area (µm²) | 19,654 | — | 18,460 |
| Synthesis | registers | 399 | — | 395 |
| Synthesis check | netlist equal to RTL (compare points) | 435 / 435 proven | — | not checked |
| Test insertion | scan chains / registers on chain | 4 / 399 | — | not inserted |
| Test insertion | stuck-at fault coverage (test coverage) | 95.92 % (99.66 %), 143 patterns | — | — |
| Floorplan | die size (µm) | 213.6 × 213.6 | — | 225.9 × 236.6 |
| Floorplan | die area (µm²) | 45,625 | — | 53,436 |
| Clock tree | clock buffers | 58 | — | 68 |
| Routing | signal nets routed | 2,134 | — | 1,919 |
| Routing | routed signal wirelength (µm) ¹ | 62,126 | — | 54,326 |
| Routing | vias ¹ | 16,688 | — | 14,892 |
| Routing | antenna diodes inserted | 0 | — | 1,071 |
| Final netlist | logic cells (no fill, tap or diode) | 2,110 | — | 1,893 |
| Physical verification | DRC violations | **0** | **0** (foundry deck) | 0 |
| Physical verification | LVS | **match** | **match** (2,116 = 2,116 devices) | 0 errors |
| Physical verification | antenna violations | **0** | **0** nets / **0** pins | 0 |
| Physical verification | netlist ↔ layout connections missing / extra | — | **0 / 0** | — |
| Physical verification | undriven / multiply-driven nets | — | **0 / 0** | — |
| Timing — typical, 25 °C, 1.80 V | setup worst slack (ns) ² | **3.139** | **3.155** | 6.071 |
| Timing — slow, 100 °C, 1.60 V | setup worst slack (ns) ² | **1.515** | **1.524** | 1.939 |
| Timing — fast, −40 °C, 1.95 V | setup worst slack (ns) ² | **3.532** | **3.542** | 7.063 |
| Timing — typical, 25 °C, 1.80 V | hold worst slack (ns) | **0.294** | **0.294** | 0.316 |
| Timing — slow, 100 °C, 1.60 V | hold worst slack (ns) | **0.760** | **0.760** | 0.888 |
| Timing — fast, −40 °C, 1.95 V | hold worst slack (ns) | **0.100** | **0.097** | 0.109 |
| Timing | max slew / capacitance / fanout violations | **0 / 0 / 0** | **0 / 0 / 0** | 782 / 0 / 111 |
| Timing | clock-gate enable paths: gates / unconstrained / worst setup (ns) | — | 1 / 0 / 1.52 | — |
| Power | total, typical corner (mW) ³ | 2.594 | 2.603 | 2.854 |
| Power | worst IR drop VPWR / VGND (mV) ³ | 0.511 / 0.755 | 0.502 / 0.748 | 0.202 |
| Sign-off | shipped netlist equal to RTL | **proven** 435 / 435 | **proven** — 391 registers paired, 953 compare points | not checked |

¹ Measured from each flow's DEF the same way (signal nets only, power and ground excluded); the same script reproduces the reference flow's own reported wirelength to within 1 µm.

² IndepthSilicon's column is reported with level-sensitive latch pins timed at their opening edge, the convention the independent timer uses, so the two columns are directly comparable. The reference flow is at its nominal parasitic corner; across all of its nine corners its worst setup slack is 1.810 ns and its worst hold slack 0.108 ns.

³ IndepthSilicon and the independent tool use the same deterministic activity (every data net 0.1 transitions per cycle, clock 2) and agree within a few percent. The reference flow's power uses its own activity setting and its IR drop is on its own power grid at its own power, so that column is shown for scale only, not as a like-for-like comparison.

### Reading the comparison

* **Synthesis.** IndepthSilicon maps this design to 10.5 % more cells than the reference flow (6.5 % more cell area).
* **Routing.** It routes 14 % more signal wire over 11 % more nets. Part of the difference is the 4 scan chains IndepthSilicon inserts for manufacturing test, which the reference flow does not; the dies also differ in size.
* **Timing.** Both flows meet setup and hold at 15 ns; the reference flow has more slack on this design, and leaves 782 slew, 0 capacitance and 111 fanout violations, where IndepthSilicon leaves none and the independent timer agrees.
* **Verification.** IndepthSilicon proves its shipped netlist equal to the RTL inside the flow, and an independent equivalence checker proves the same; the reference flow runs no equivalence check.

## How the independent numbers were produced

None of these tools is part of IndepthSilicon. Each one reads the shipped files (GDSII, DEF, Verilog netlist) directly.

| Check | Independent tool |
|---|---|
| Design rules | KLayout with the SKY130 foundry rule deck (`sky130A_mr.drc`) on the GDSII |
| Parasitics + static timing, 3 corners | OpenRCX extraction from the DEF, OpenSTA with the SKY130 Liberty corners |
| Antenna | OpenROAD antenna checker on the DEF |
| Layout vs schematic | Magic extraction + Netgen comparison, as the reference flow runs them |
| Power, IR drop | OpenSTA power report; OpenROAD PDNSim on the drawn power grid |
| Equivalence, shipped netlist vs RTL | Yosys elaborates the RTL on its own; ABC proves the two equal |

The independent tools' own reports are in [`reports/independent/`](reports/independent/).

## Repository layout

```
apb-uart-gds2-flow/
├── rtl/apb_uart.v                   design RTL
├── flow/run_flow.txt              the complete flow script (one run, RTL to GDSII)
├── netlist/apb_uart_postpnr.v       shipped gate-level netlist
├── layout/apb_uart.gds.gz           shipped GDSII (gzip)
├── layout/apb_uart.def.gz           shipped DEF (gzip)
├── images/                        floorplan, placement, routing, final layout
└── reports/independent/           timing, DRC, LVS, antenna, power, equivalence reports
```

## The flow

One script, one run. The flow chooses the die from the cell area, places, builds the clock tree, routes, closes timing and sign-off, and writes the layout:

```
load_sky130
read_verilog rtl/apb_uart.v
set_clock_period 15
run_all 200 200
write_netlist apb_uart_postpnr.v
write_def apb_uart.def
write_gds apb_uart.gds
write_image images/04_final_layout.png routing
exit
```

Stages, in order: RTL read-in and lint, logic synthesis and technology mapping to `sky130_fd_sc_hd`, equivalence check of the netlist against the RTL, scan insertion and test-pattern generation, floorplan and power grid, placement, clock-tree build, routing, timing and electrical repair, filler and metal fill, then physical verification (DRC, LVS, antenna), multi-corner timing sign-off on extracted parasitics, power and IR drop, and a final equivalence check of the shipped netlist against the RTL.

---

*Layout, netlist and reports produced by the IndepthSilicon flow. SKY130 is an open PDK. Clock 15 ns at every corner.*

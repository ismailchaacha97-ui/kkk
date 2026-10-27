# kkk

Projects in this repository:

| Folder | What it is |
|---|---|
| `mt4/` | **Apex Confluence Pro** — a MetaTrader 4 indicator: price-action + support/resistance + volume + market-structure confluence engine. See [`mt4/README.md`](mt4/README.md). |
| `tools/` | Development tools — `engine_sim.py`, the calibration harness used to tune the indicator defaults. |
| `shorts/` | Short-video rendering project. |

## Apex Confluence Pro (MT4)

A non-lagging, non-repainting indicator that marks qualified entries at
support/resistance zones, confirms them with volume and structure, and prints a
live dashboard that says when to enter and when to stay out.

* Source: [`mt4/indicators/ApexConfluencePro.mq4`](mt4/indicators/ApexConfluencePro.mq4)
* Manual: [`mt4/README.md`](mt4/README.md)
* Quick start: [`mt4/QUICKSTART.md`](mt4/QUICKSTART.md)
* Presets: [`mt4/presets/`](mt4/presets/)

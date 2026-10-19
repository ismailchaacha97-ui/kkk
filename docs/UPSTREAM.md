# Upstream: NautilusTrader

This repository is a thin research layer on top of
[nautechsystems/nautilus_trader](https://github.com/nautechsystems/nautilus_trader).

## What is installed

| | |
|---|---|
| Package | `nautilus_trader` |
| Installed version | **1.221.0** (PyPI wheel, manylinux x86_64) |
| Git tag | [`v1.221.0`](https://github.com/nautechsystems/nautilus_trader/releases/tag/v1.221.0) |
| Tag commit | `dffc3cbe20fc97b049e8fbc0907fa462b7d1f29f` |
| License | **LGPL-3.0-or-later** |
| Python | `>=3.11,<3.14` |
| Extras in this release | `betfair`, `docker`, `dydx`, `ib`, `polymarket` |
| Latest upstream release at install time | v1.231.0 (2026-08-02) |

The package is installed from PyPI rather than cloned: it is a compiled Rust
extension and the published wheel is the supported distribution.

```bash
pip install "nautilus_trader==1.221.0"
```

## Why pin 1.221.0?

NautilusTrader **1.222.0 raised the minimum Python version to 3.12** (and
2.0.0 release candidates require 3.13 in some builds). The execution environment
for this checkout is Python 3.11.2, and 1.221.0 is the newest release that
supports it. The pin keeps the repository reproducible on 3.11.

If you are on Python 3.12+ and want the newer engine:

```bash
python3.12 -m pip install "nautilus_trader==1.231.0"
```

Then update `requirements.txt` and `pyproject.toml`, and run:

```bash
python3 -m unittest discover -s tests -v
python3 -m daytrader compare --days 10
```

### API notes across versions

Everything used here is stable, widely used API:

* `BacktestEngine`, `BacktestEngineConfig`, `LoggingConfig`
* `BacktestVenueConfig` arguments via `engine.add_venue(...)`
* `Strategy`, `BarType`, `BarDataWrangler`, `FillModel`
* `OrderFactory.bracket`, `submit_order_list`, `close_all_positions`
* `trader.generate_orders_report()` / `generate_positions_report()` /
  `generate_account_report()`

Two version-specific details were hit while building this repository:

1. `OrderFactory` is not importable from `nautilus_trader.model.orders` in
   1.221.0; use the strategy's `self.order_factory` (or
   `nautilus_trader.common.factories.OrderFactory`).
2. `nautilus_trader.model` re-exports `TraderId` in 1.221.0. If a future version
   removes that re-export, import it from `nautilus_trader.model.identifiers`.

When upgrading across minor versions, check the
[release notes](https://github.com/nautechsystems/nautilus_trader/releases) for
renamed config fields and adapter extras. The 2.0 line is still in release
candidates and may change APIs.

## Licensing

NautilusTrader is licensed under **LGPL-3.0-or-later**.

* Importing and using it as an installed dependency does not change the license
  of this repository's code.
* If you modify the engine itself and distribute the modified library, the LGPL
  requires you to make those modifications available under the same license.
* This repository does **not** vendor or patch NautilusTrader source.

The QuantConnect LEAN minute-bar sample fetched by
`scripts/fetch_lean_sample.py` is downloaded at runtime and is not
redistributed here. LEAN's source is Apache-2.0; its bundled market data remains
subject to QuantConnect's terms — check them before any redistribution or
commercial use.

## Useful upstream links

* Repository: <https://github.com/nautechsystems/nautilus_trader>
* Documentation: <https://nautilustrader.io/docs/>
* Examples used as reference:
  `examples/backtest/example_01_load_bars_from_custom_csv` (CSV → `Bar`),
  `examples/backtest/example_05_using_portfolio` (bracket orders, portfolio
  reporting), `examples/backtest/fx_ema_cross_bracket_gbpusd_bars_external.py`
  (fill model configuration).
* Issue tracker: <https://github.com/nautechsystems/nautilus_trader/issues>

## Why not the alternatives?

| Project | Why it was not chosen for this use case |
|---|---|
| freqtrade | Crypto-only, exchange-bot oriented; no US-equity session model. |
| QuantConnect Lean | Powerful, but C#/.NET toolchain and cloud/CLI workflow; heavier to run as a single Python repo. |
| backtrader | Effectively unmaintained (last push 2024) and no comparable live adapter layer. |
| jesse | Crypto-only. |
| vectorbt | Research/backtesting only; no live execution engine. |
| qlib | AI research platform, not an order-routing engine. |

Star counts and activity used in this comparison are recorded in the main
[`README.md`](../README.md) (as of 2026-10-19).

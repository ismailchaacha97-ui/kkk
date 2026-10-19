"""Backtest runner that wires strategies into a NautilusTrader engine."""

from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass, field
from decimal import Decimal
from pathlib import Path

import numpy as np
import pandas as pd
from nautilus_trader.backtest.engine import BacktestEngine
from nautilus_trader.backtest.models import FillModel
from nautilus_trader.config import BacktestEngineConfig, LoggingConfig
from nautilus_trader.model import TraderId
from nautilus_trader.model.currencies import USD
from nautilus_trader.model.enums import AccountType, OmsType
from nautilus_trader.model.identifiers import Venue
from nautilus_trader.model.objects import Money

from daytrader import DEFAULT_VENUE
from daytrader.config import BacktestConfig, ORBParams, VWAPParams
from daytrader.data import generate_dataset, load_bars
from daytrader.instruments import bar_type_for, make_equity
from daytrader.metrics import build_daily_frame, compute_summary, sessions_from_timestamps
from daytrader.strategies import OpeningRangeBreakout, VWAPReversion

__all__ = [
    "STRATEGIES",
    "BacktestResult",
    "build_strategy",
    "run_backtest",
]

STRATEGIES = ("orb", "vwap")


@dataclass
class BacktestResult:
    """Everything produced by a single backtest run."""

    strategy: str
    config: BacktestConfig
    params: dict[str, object]
    summary: dict[str, object]
    daily: pd.DataFrame
    positions: pd.DataFrame
    fills: pd.DataFrame
    orders: pd.DataFrame
    account: pd.DataFrame
    sessions: pd.DatetimeIndex = field(default_factory=pd.DatetimeIndex)

    def to_payload(self) -> dict[str, object]:
        """JSON-safe payload combining config, parameters and metrics."""
        return {
            "strategy": self.strategy,
            "config": _json_safe(asdict(self.config)),
            "params": _json_safe(self.params),
            "summary": _json_safe(self.summary),
        }


def build_strategy(
    name: str,
    instrument,
    bar_type,
    params: ORBParams | VWAPParams | None = None,
):
    """Instantiate a strategy by name."""
    if name == "orb":
        return OpeningRangeBreakout(instrument, bar_type, params or ORBParams())
    if name == "vwap":
        return VWAPReversion(instrument, bar_type, params or VWAPParams())
    raise ValueError(f"unknown strategy {name!r}; choose from {STRATEGIES}")


def run_backtest(
    strategy: str,
    config: BacktestConfig,
    params: ORBParams | VWAPParams | None = None,
    *,
    refresh_data: bool = False,
    collect_reports: bool = True,
) -> BacktestResult:
    """Run a single strategy over one or more symbols and collect results."""
    if strategy not in STRATEGIES:
        raise ValueError(f"unknown strategy {strategy!r}; choose from {STRATEGIES}")
    if params is None:
        params = ORBParams() if strategy == "orb" else VWAPParams()

    missing = [
        symbol
        for symbol in config.symbols
        if not (Path(config.data_dir) / f"{symbol}_{config.bar_minutes}min.csv").exists()
    ]
    if missing and not config.auto_generate:
        raise FileNotFoundError(
            "missing data files for "
            + ", ".join(missing)
            + f" in {Path(config.data_dir).resolve()}; "
            + "drop the CSVs there or allow synthetic generation",
        )

    if config.auto_generate:
        generate_dataset(
            symbols=config.symbols,
            data_dir=config.data_dir,
            start_date=config.start_date,
            days=config.days,
            seed=config.seed,
            bar_minutes=config.bar_minutes,
            force=refresh_data,
        )

    instruments = {}
    bar_types = {}
    all_bars: dict[str, list] = {}
    for symbol in config.symbols:
        instrument = make_equity(symbol, fee_bps=config.fee_bps)
        bar_type = bar_type_for(instrument, config.bar_minutes)
        path = Path(config.data_dir) / f"{symbol}_{config.bar_minutes}min.csv"
        instruments[symbol] = instrument
        bar_types[symbol] = bar_type
        all_bars[symbol] = load_bars(path, instrument, bar_type)

    timestamps = [bar.ts_event for bars in all_bars.values() for bar in bars]
    sessions = sessions_from_timestamps(timestamps)

    engine_config = BacktestEngineConfig(
        trader_id=TraderId("DAYTRADER-001"),
        logging=LoggingConfig(log_level=config.log_level),
    )
    engine = BacktestEngine(config=engine_config)

    venue = Venue(DEFAULT_VENUE)
    engine.add_venue(
        venue=venue,
        oms_type=OmsType.NETTING,
        account_type=AccountType.MARGIN,
        starting_balances=[Money(config.starting_balance, USD)],
        base_currency=USD,
        default_leverage=Decimal(str(config.leverage)),
        fill_model=FillModel(
            prob_slippage=config.slippage_prob,
            random_seed=config.seed,
        ),
        bar_execution=True,
        bar_adaptive_high_low_ordering=True,
    )

    for symbol in config.symbols:
        engine.add_instrument(instruments[symbol])
        engine.add_data(all_bars[symbol])

    for symbol in config.symbols:
        engine.add_strategy(
            build_strategy(strategy, instruments[symbol], bar_types[symbol], params),
        )

    try:
        engine.run()

        orders = engine.trader.generate_orders_report() if collect_reports else pd.DataFrame()
        fills = engine.trader.generate_order_fills_report() if collect_reports else pd.DataFrame()
        positions = engine.trader.generate_positions_report() if collect_reports else pd.DataFrame()
        account = (
            engine.trader.generate_account_report(venue) if collect_reports else pd.DataFrame()
        )
        nautilus_stats = _collect_nautilus_stats(engine)
    finally:
        engine.dispose()

    summary = compute_summary(
        positions,
        sessions,
        config.starting_balance,
        strategy=strategy,
        symbols=config.symbols,
    )
    summary["data_source"] = data_source_label(Path(config.data_dir))
    summary.update(nautilus_stats)
    daily = build_daily_frame(positions, sessions, config.starting_balance)

    return BacktestResult(
        strategy=strategy,
        config=config,
        params=_json_safe(asdict(params)),
        summary=summary,
        daily=daily,
        positions=positions,
        fills=fills,
        orders=orders,
        account=account,
        sessions=sessions,
    )


def _collect_nautilus_stats(engine: BacktestEngine) -> dict[str, object]:
    """Pull the framework's own portfolio statistics when available."""
    stats: dict[str, object] = {}
    try:
        analyzer = engine.portfolio.analyzer
        general = analyzer.get_performance_stats_general()
    except Exception:  # pragma: no cover - depends on fills
        return stats
    for key, value in general.items():
        name = "nautilus_" + key.strip().lower().replace(" ", "_").replace("(", "").replace(")", "")
        stats[name] = _scalar(value)
    return stats


def _scalar(value: object) -> object:
    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return None
    return value


def _json_safe(value: object) -> object:
    """Recursively convert dataclasses/paths/numpy scalars to JSON-safe values."""
    if isinstance(value, dict):
        return {str(k): _json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return None
    if hasattr(value, "__dataclass_fields__"):
        return _json_safe(asdict(value))
    return value


def data_source_label(data_dir: Path) -> str:
    """Distinguish the bundled generator from user-supplied CSV data."""
    marker = data_dir / ".synthetic.json"
    if marker.exists():
        try:
            meta = json.loads(marker.read_text())
        except json.JSONDecodeError:
            return "synthetic"
        return f"synthetic (seed {meta.get('seed')}, {meta.get('days')} sessions)"
    return "csv"

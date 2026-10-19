"""Report generation: CSV artefacts, Markdown summaries and charts."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from daytrader.backtest import BacktestResult

__all__ = [
    "format_metric",
    "write_comparison",
    "write_reports",
]

STRATEGY_LABELS = {
    "orb": "Opening Range Breakout (ORB)",
    "vwap": "VWAP Mean Reversion",
}

_METRIC_ROWS: list[tuple[str, str, str]] = [
    ("Net PnL", "net_pnl", "money"),
    ("Return", "return_pct", "pct"),
    ("Trades", "trades", "int"),
    ("Win rate", "win_rate_pct", "pct"),
    ("Profit factor", "profit_factor", "ratio"),
    ("Expectancy / trade", "expectancy", "money"),
    ("Average win", "avg_win", "money"),
    ("Average loss", "avg_loss", "money"),
    ("Largest win", "largest_win", "money"),
    ("Largest loss", "largest_loss", "money"),
    ("Max drawdown", "max_drawdown_pct", "pct"),
    ("Sharpe (daily, ann.)", "sharpe", "ratio"),
    ("Sortino (daily, ann.)", "sortino", "ratio"),
    ("Trades / day", "trades_per_day", "ratio"),
    ("Average hold (min)", "avg_hold_minutes", "minutes"),
]

_PALETTE = ["#0B6E4F", "#1F77B4", "#C0392B", "#8E44AD", "#D68910", "#117864"]


def format_metric(value: object, kind: str) -> str:
    """Human-friendly formatting for a metric value."""
    if value is None:
        return "n/a"
    if isinstance(value, str):
        return value
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    if math.isnan(number) or math.isinf(number):
        return "n/a"
    if kind == "money":
        return f"-${abs(number):,.2f}" if number < 0 else f"${number:,.2f}"
    if kind == "pct":
        return f"{number:.2f}%"
    if kind == "int":
        return f"{int(number):,}"
    if kind == "ratio":
        return f"{number:.2f}"
    if kind == "minutes":
        return f"{number:.1f}"
    return f"{number:,.2f}"


def _strategy_label(name: str) -> str:
    return STRATEGY_LABELS.get(name, name.upper())


def _config_lines(result: BacktestResult) -> list[str]:
    config = result.config
    sessions = result.daily.index
    first = sessions[0].date().isoformat() if len(sessions) else "n/a"
    last = sessions[-1].date().isoformat() if len(sessions) else "n/a"
    return [
        f"- **Strategy:** {_strategy_label(result.strategy)}",
        f"- **Symbols:** {', '.join(config.symbols)}",
        f"- **Sessions:** {len(sessions)} ({first} → {last})",
        f"- **Starting balance:** ${config.starting_balance:,.2f}",
        f"- **Leverage:** {config.leverage:g}x  |  **Fees:** {config.fee_bps:.2f} bps/side",
        f"- **Slippage model:** {config.slippage_prob:.0%} probability of one tick",
        f"- **Data:** {result.summary.get('data_source', 'n/a')}",
        f"- **Seed:** {config.seed}",
    ]


def _params_lines(params: dict[str, object]) -> list[str]:
    lines = ["| Parameter | Value |", "|---|---|"]
    for key, value in params.items():
        if isinstance(value, dict):
            for sub_key, sub_value in value.items():
                lines.append(f"| `{key}.{sub_key}` | {sub_value} |")
        else:
            lines.append(f"| `{key}` | {value} |")
    return lines


def summary_markdown(result: BacktestResult) -> str:
    """Render a Markdown report for one backtest."""
    summary = result.summary
    label = _strategy_label(result.strategy)
    lines = [
        f"# Backtest report — {label}",
        "",
        "## Configuration",
        "",
        *_config_lines(result),
        "",
        "## Performance",
        "",
        "| Metric | Value |",
        "|---|---|",
    ]
    lines += [
        f"| {metric} | {format_metric(summary.get(key), kind)} |"
        for metric, key, kind in _METRIC_ROWS
    ]
    lines += [
        "",
        "## Strategy parameters",
        "",
        *_params_lines(result.params),
        "",
        "## How to read this",
        "",
        "- Results come from an event-driven NautilusTrader backtest with",
        "  market-entry bracket orders (stop + target), 1 bp taker fees and",
        "  probabilistic one-tick slippage.",
        "- Every position is closed before the session close; the equity curve is",
        "  therefore realized PnL, not mark-to-market noise.",
        "- Synthetic data is a fixture for validating the pipeline. It is **not**",
        "  evidence that these strategies are profitable on live markets.",
        "",
        "## Files",
        "",
        (
            "`orders.csv`, `fills.csv`, `positions.csv`, `account.csv`, `daily.csv`, "
            "`summary.json`, `stats.txt`, `equity_curve.png`."
        ),
        "",
    ]
    return "\n".join(lines)


def stats_text(result: BacktestResult) -> str:
    summary = result.summary
    label = _strategy_label(result.strategy)
    header = f"{label} — {', '.join(result.config.symbols)} — {summary.get('sessions')} sessions"
    lines = [header, "=" * len(header)]
    for metric, key, kind in _METRIC_ROWS:
        lines.append(f"{metric:<24}{format_metric(summary.get(key), kind):>16}")
    lines.append("")
    ending = format_metric(summary.get("ending_balance"), "money")
    annualised = format_metric(summary.get("cagr_pct"), "pct")
    lines.append(f"{'Ending balance':<24}{ending:>16}")
    lines.append(f"{'Annualised return*':<24}{annualised:>16}")
    lines.append("")
    lines.append("* Annualisation over a short sample is indicative only.")
    return "\n".join(lines) + "\n"


def _pyplot():
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:  # pragma: no cover - optional dependency
        return None
    plt.rcParams.update(
        {
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "axes.edgecolor": "#CCCCCC",
            "axes.grid": True,
            "grid.color": "#EEEEEE",
            "grid.linewidth": 0.8,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "font.size": 10,
            "axes.titlesize": 12,
            "axes.titleweight": "bold",
        },
    )
    return plt


def plot_equity(result: BacktestResult, path: Path) -> Path | None:
    """Plot equity and drawdown over the backtest sessions."""
    plt = _pyplot()
    if plt is None or result.daily.empty:
        return None
    from matplotlib.ticker import FuncFormatter

    daily = result.daily
    label = _strategy_label(result.strategy)
    color = _PALETTE[0]

    fig, (ax1, ax2) = plt.subplots(
        2,
        1,
        figsize=(11, 6.8),
        sharex=True,
        gridspec_kw={"height_ratios": [3, 1.2]},
    )
    ax1.plot(daily.index, daily["equity"], color=color, lw=1.8)
    ax1.fill_between(
        daily.index,
        result.config.starting_balance,
        daily["equity"],
        color=color,
        alpha=0.08,
    )
    ax1.axhline(
        result.config.starting_balance,
        color="#999999",
        linestyle="--",
        lw=0.9,
    )
    ax1.set_title(f"{label} — {', '.join(result.config.symbols)}")
    ax1.set_ylabel("Equity (USD)")
    ax1.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"${value:,.0f}"))

    ax2.fill_between(daily.index, daily["drawdown_pct"], 0.0, color="#C0392B", alpha=0.35)
    ax2.plot(daily.index, daily["drawdown_pct"], color="#C0392B", lw=1.0)
    ax2.set_ylabel("Drawdown (%)")

    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path


def write_reports(result: BacktestResult, out_dir: Path | str) -> dict[str, Path]:
    """Write all artefacts for one backtest and return their paths."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    written: dict[str, Path] = {}

    for name, frame in (
        ("orders", result.orders),
        ("fills", result.fills),
        ("positions", result.positions),
        ("account", result.account),
        ("daily", result.daily),
    ):
        path = out / f"{name}.csv"
        frame.to_csv(path)
        written[name] = path

    payload = result.to_payload()
    summary_path = out / "summary.json"
    summary_path.write_text(json.dumps(payload, indent=2, default=str))
    written["summary"] = summary_path

    stats_path = out / "stats.txt"
    stats_path.write_text(stats_text(result))
    written["stats"] = stats_path

    markdown_path = out / "summary.md"
    markdown_path.write_text(summary_markdown(result))
    written["markdown"] = markdown_path

    chart = plot_equity(result, out / "equity_curve.png")
    if chart is not None:
        written["chart"] = chart

    return written


def plot_comparison(results: dict[str, BacktestResult], path: Path) -> Path | None:
    plt = _pyplot()
    if plt is None or not results:
        return None
    from matplotlib.ticker import FuncFormatter

    fig, (ax1, ax2) = plt.subplots(
        2,
        1,
        figsize=(11, 6.8),
        sharex=True,
        gridspec_kw={"height_ratios": [3, 1.2]},
    )
    for index, (name, result) in enumerate(results.items()):
        if result.daily.empty:
            continue
        color = _PALETTE[index % len(_PALETTE)]
        returns = (result.daily["equity"] / result.config.starting_balance - 1.0) * 100.0
        ax1.plot(result.daily.index, returns, color=color, lw=1.8, label=_strategy_label(name))
        ax2.plot(
            result.daily.index,
            result.daily["drawdown_pct"],
            color=color,
            lw=1.2,
            label=_strategy_label(name),
        )

    ax1.axhline(0.0, color="#999999", linestyle="--", lw=0.9)
    ax1.set_title("Strategy comparison — cumulative return")
    ax1.set_ylabel("Return (%)")
    ax1.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:.1f}%"))
    ax1.legend(loc="upper left", frameon=False)

    ax2.set_ylabel("Drawdown (%)")

    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path


def comparison_markdown(results: dict[str, BacktestResult]) -> str:
    if not results:
        return "# Strategy comparison\n\nNo results.\n"
    first = next(iter(results.values()))
    labels = {name: _strategy_label(name) for name in results}
    header = "| Metric | " + " | ".join(labels[name] for name in results) + " |"
    separator = "|---|" + "---:|" * len(results)
    lines = [
        "# Strategy comparison",
        "",
        f"Symbols: **{', '.join(first.config.symbols)}** · "
        f"Sessions: **{len(first.sessions)}** · "
        f"Starting balance: **${first.config.starting_balance:,.0f}** · "
        f"Data: **{first.summary.get('data_source', 'n/a')}**",
        "",
        header,
        separator,
    ]
    for metric, key, kind in _METRIC_ROWS:
        cells = [format_metric(result.summary.get(key), kind) for result in results.values()]
        lines.append(f"| {metric} | " + " | ".join(cells) + " |")
    lines += [
        "",
        "## Configuration",
        "",
        f"- Leverage: {first.config.leverage:g}x",
        f"- Fees: {first.config.fee_bps:.2f} bps per side",
        f"- Slippage: {first.config.slippage_prob:.0%} probability of one tick",
        f"- Seed: {first.config.seed}",
        "",
        "## Notes",
        "",
        "- Both strategies run on identical data, fees, slippage and risk limits;",
        "  the only difference is the trading logic and its parameters.",
        "- Synthetic data exercises the full pipeline but says nothing about",
        "  real-world profitability. Re-run against vendor data before drawing",
        "  conclusions.",
        "- The ORB and VWAP books are complementary by construction; a combined",
        "  allocation is a natural next experiment (`--strategy` runs them",
        "  separately, so each result is attributable).",
        "",
    ]
    return "\n".join(lines)


def write_comparison(
    results: dict[str, BacktestResult],
    out_dir: Path | str,
) -> dict[str, Path]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    written: dict[str, Path] = {}

    markdown_path = out / "comparison.md"
    markdown_path.write_text(comparison_markdown(results))
    written["markdown"] = markdown_path

    chart = plot_comparison(results, out / "comparison.png")
    if chart is not None:
        written["chart"] = chart

    payload = {
        name: {
            "summary": result.to_payload()["summary"],
            "params": result.to_payload()["params"],
        }
        for name, result in results.items()
    }
    json_path = out / "comparison.json"
    json_path.write_text(json.dumps(payload, indent=2, default=str))
    written["json"] = json_path

    return written


def print_summary_table(results: dict[str, BacktestResult]) -> str:
    """Plain-text summary suitable for the terminal."""
    if not results:
        return "No results."
    rows = [
        ("Net PnL", "net_pnl", "money"),
        ("Return", "return_pct", "pct"),
        ("Trades", "trades", "int"),
        ("Win rate", "win_rate_pct", "pct"),
        ("Profit factor", "profit_factor", "ratio"),
        ("Max drawdown", "max_drawdown_pct", "pct"),
    ]
    labels = [_strategy_label(name) for name in results]
    width = max(len(label) for label in labels) + 2
    lines = ["", "RESULTS".center(width * len(labels) + 20, "-")]
    lines.append(f"{'':<12}" + "".join(f"{label:>{width}}" for label in labels))
    for metric, key, kind in rows:
        values = [format_metric(result.summary.get(key), kind) for result in results.values()]
        lines.append(f"{metric:<12}" + "".join(f"{value:>{width}}" for value in values))
    lines.append("-" * (12 + width * len(labels)))
    return "\n".join(lines)

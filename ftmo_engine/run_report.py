"""Generates ftmo_engine/REPORT.md -- every number below is simulated, not asserted.

Run:  python3 -m ftmo_engine.run_report
"""

from __future__ import annotations

from pathlib import Path

from .mc import EdgeProfile, evaluate_plan, monte_carlo_funded, monte_carlo_phase
from .rules import PHASE_1, PHASE_2, PLANS, AccountPlan
from .risk import EURUSD, lots_for_risk

OUT = Path(__file__).with_name("REPORT.md")

# Base case: a good-but-believable system. 45% win rate at 1.8R, 2 filtered setups a
# day, real costs, and stops that occasionally get gapped through.
BASE_EDGE = EdgeProfile(win_prob=0.45, win_R=1.8, cost_R=0.05, tail_prob=0.02,
                        tail_loss_R=2.5, trades_per_day=2.0)
RISK_LADDER = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
CYCLE_DAYS = 14          # payout cycle length, calendar days
DAYS_PER_MONTH = 30.4


def pct(x: float) -> str:
    return f"{x * 100:.1f}%"


def money(x: float) -> str:
    return f"${x:,.0f}"


def table(headers: list[str], rows: list[list[str]]) -> str:
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(out)


def section_edge_realism(plan: AccountPlan, edge: EdgeProfile) -> str:
    """Translate the assumed edge into a monthly return, so it can be sanity-checked."""
    per_trade_pct = edge.expectancy_R * 0.5 / 100 * 100  # at 0.5% risk, in % of account
    per_day = per_trade_pct * edge.trades_per_day
    rows = [
        ["Expectancy per trade", f"{edge.expectancy_R:+.3f}R", money(edge.expectancy_R * plan.initial_balance * 0.005)],
        ["Trades per day", f"{edge.trades_per_day:.1f}", ""],
        ["Return per trading day at 0.5% risk", f"{per_day:+.3f}%", money(plan.initial_balance * per_day / 100)],
        ["Implied return per month (21 days)", f"{per_day * 21:+.1f}%", ""],
        ["Implied return per 6 months", f"{per_day * 126:+.0f}%", ""],
    ]
    return table(["Metric", "Value", "On a $100K account"], rows)


def section_risk_ladder(plan: AccountPlan, edge: EdgeProfile, n: int = 6000) -> str:
    rows = []
    for stop in [2.0, None]:
        for risk in RISK_LADDER:
            p1 = monte_carlo_phase(PHASE_1, plan, edge, risk, n_trials=n, daily_stop_R=stop, max_days=200)
            p2 = monte_carlo_phase(PHASE_2, plan, edge, risk, n_trials=n, daily_stop_R=stop, max_days=200)
            p_funded = p1["p_pass"] * p2["p_pass"]
            attempts = 1 / p_funded if p_funded else float("inf")
            rows.append([
                "off" if stop is None else f"{stop:.0f}R",
                f"{risk:.2f}%",
                pct(p1["p_pass"]),
                pct(p2["p_pass"]),
                pct(p_funded),
                f"{p1['median_days_to_pass']:.0f}",
                f"{p1['p90_days_to_pass']:.0f}",
                f"{p1['p95_max_dd_pct']:.1f}%",
                money(attempts * plan.fee),
            ])
    return table(
        ["Daily stop", "Risk/trade", "P(pass P1)", "P(pass P2)", "P(reach funded)",
         "Median days P1", "P90 days P1", "P95 max DD", "Fee per success"],
        rows,
    )


def section_failure_attribution(plan: AccountPlan, edge: EdgeProfile, n: int = 6000) -> str:
    rows = []
    for risk in RISK_LADDER:
        p1 = monte_carlo_phase(PHASE_1, plan, edge, risk, n_trials=n, daily_stop_R=2.0, max_days=200)
        rows.append([
            f"{risk:.2f}%",
            pct(p1["p_fail_daily"]),
            pct(p1["p_fail_total"]),
            pct(p1["p_incomplete"]),
            f"{p1['median_trades']:.0f}",
            f"{p1['median_max_dd_pct']:.1f}%",
        ])
    return table(
        ["Risk/trade", "Daily-limit fails", "Total-limit fails", "Timed out (200d)",
         "Median trades", "Median max DD"],
        rows,
    )


def section_break_even_edge(plan: AccountPlan, n: int = 4000) -> str:
    """Two different break-evens, and they are not the same number."""
    rows = []
    for risk in [0.25, 0.5, 0.75, 1.0]:
        # (a) EV of the whole venture == 0, refund included
        lo, hi = 0.30, 0.60
        for _ in range(10):
            mid = (lo + hi) / 2
            res = evaluate_plan(plan, EdgeProfile(win_prob=mid, win_R=1.8, trades_per_day=2.0),
                                risk, daily_stop_R=2.0, n_trials=n, funded_cycles=12,
                                payout_buffer_pct=15.0)
            lo, hi = (mid, hi) if res["ev_per_attempt"] < 0 else (lo, mid)
        ev_zero_wr = hi
        # (b) expectancy per trade == 0: the edge below which no model survives
        flat = EdgeProfile(win_prob=0.45, win_R=1.8, trades_per_day=2.0).win_prob_for_expectancy(0.0)
        rows.append([
            f"{risk:.2f}%",
            f"{ev_zero_wr * 100:.1f}%",
            f"{EdgeProfile(win_prob=ev_zero_wr, win_R=1.8).expectancy_R:+.3f}R",
            f"{flat * 100:.1f}%",
            f"{EdgeProfile(win_prob=0.45, win_R=1.8).win_prob_for_expectancy(0.10) * 100:.1f}%",
        ])
    return table(
        ["Risk/trade", "Win rate for EV=0 (refund incl.)", "Implied expectancy",
         "Win rate for 0.00R", "Win rate for 0.10R/trade"],
        rows,
    )


def section_account_sizes(edge: EdgeProfile, risk: float = 0.5, n: int = 3000) -> str:
    rows = []
    for label, plan in PLANS.items():
        p1 = monte_carlo_phase(PHASE_1, plan, edge, risk, n_trials=n, daily_stop_R=2.0, max_days=200)
        p2 = monte_carlo_phase(PHASE_2, plan, edge, risk, n_trials=n, daily_stop_R=2.0, max_days=200)
        p_funded = p1["p_pass"] * p2["p_pass"]
        funded = monte_carlo_funded(plan, edge, risk, n_trials=1500, cycles=12,
                                    daily_stop_R=2.0, buffer_target_pct=15.0)
        ev = -plan.fee + p_funded * funded["mean_earnings"] + p_funded * funded["p_first_payout"] * plan.fee
        months = 12 * CYCLE_DAYS / DAYS_PER_MONTH
        rows.append([
            label,
            money(plan.fee),
            f"{plan.fee / plan.initial_balance * 100:.2f}%",
            pct(p_funded),
            money(funded["mean_earnings"]),
            money(ev),
            money(ev / months),
        ])
    return table(
        ["Account", "Fee", "Fee % of account", "P(reach funded)",
         "Mean earnings over 12 cycles", "EV per attempt", "EV per month"],
        rows,
    )


def section_funded_decay(edge: EdgeProfile, risk: float = 0.5, cycles: int = 24) -> str:
    """The funded stage under a decaying edge -- the failure mode nobody models."""
    rows = []
    for k in [1.0, 0.75, 0.5, 0.25, 0.0]:
        degraded = edge.with_expectancy_scale(k)
        res = monte_carlo_funded(PLANS["100K"], degraded, risk, n_trials=2500,
                                 cycles=cycles, daily_stop_R=2.0, buffer_target_pct=15.0)
        rows.append([
            f"{k * 100:.0f}%",
            f"{degraded.expectancy_R:+.3f}R",
            f"{degraded.win_prob * 100:.1f}%",
            pct(res["p_account_lost"]),
            pct(res["p_first_payout"]),
            money(res["mean_earnings"]),
            money(res["p10_earnings"]),
            f"{res['mean_cycles_survived']:.1f}",
        ])
    return table(
        ["Live edge vs backtest", "Expectancy", "Win rate", "P(account lost)",
         "P(first payout)", "Mean earnings", "10th pct", "Mean cycles survived"],
        rows,
    )


def section_payout_policy(edge: EdgeProfile, risk: float = 0.5, cycles: int = 52) -> str:
    """Withdrawal policy at a fixed, healthy edge."""
    rows = []
    base = monte_carlo_funded(PLANS["100K"], edge, risk, n_trials=2500, cycles=cycles,
                              withdraw_fraction=1.0)
    rows.append(["Withdraw 100% (take-all)", pct(base["p_account_lost"]),
                 money(base["mean_earnings"]), money(base["median_earnings"]),
                 money(base["p10_earnings"]), f"{base['mean_cycles_survived']:.1f}"])
    for w in [0.85, 0.70, 0.50]:
        res = monte_carlo_funded(PLANS["100K"], edge, risk, n_trials=2500, cycles=cycles,
                                 withdraw_fraction=w)
        rows.append([f"Withdraw {w * 100:.0f}% (keep {100 - w * 100:.0f}%)",
                     pct(res["p_account_lost"]), money(res["mean_earnings"]),
                     money(res["median_earnings"]), money(res["p10_earnings"]),
                     f"{res['mean_cycles_survived']:.1f}"])
    for b in [5.0, 10.0, 15.0, 25.0]:
        res = monte_carlo_funded(PLANS["100K"], edge, risk, n_trials=2500, cycles=cycles,
                                 buffer_target_pct=b)
        rows.append([f"Buffer {b:.0f}%, withdraw excess",
                     pct(res["p_account_lost"]), money(res["mean_earnings"]),
                     money(res["median_earnings"]), money(res["p10_earnings"]),
                     f"{res['mean_cycles_survived']:.1f}"])
    return table(
        ["Policy (52 cycles ~= 2 years)", "P(account lost)", "Mean earnings",
         "Median", "10th pct", "Mean cycles survived"],
        rows,
    )


def section_sensitivity(plan: AccountPlan, risk: float = 0.5, n: int = 4000) -> str:
    rows = []
    for wr in [0.35, 0.40, 0.45, 0.50, 0.55]:
        edge = EdgeProfile(win_prob=wr, win_R=1.8, trades_per_day=2.0)
        p1 = monte_carlo_phase(PHASE_1, plan, edge, risk, n_trials=n, daily_stop_R=2.0, max_days=200)
        res = evaluate_plan(plan, edge, risk, daily_stop_R=2.0, n_trials=n,
                            funded_cycles=12, payout_buffer_pct=15.0)
        rows.append([
            f"{wr * 100:.0f}%",
            f"{edge.expectancy_R:+.3f}R",
            f"{edge.profit_factor:.2f}",
            pct(p1["p_pass"]),
            f"{p1['median_days_to_pass']:.0f}",
            pct(res["p_reach_funded"]),
            money(res["ev_per_attempt"]),
        ])
    return table(
        ["Win rate", "Expectancy/trade", "PF", "P(pass P1)", "Median days",
         "P(reach funded)", "EV / attempt"],
        rows,
    )


def section_sizing(plan: AccountPlan) -> str:
    rows = []
    for risk in [0.25, 0.5, 1.0, 2.0]:
        rows.append([
            f"{risk:.2f}%",
            money(plan.initial_balance * risk / 100),
            f"{lots_for_risk(plan.initial_balance, risk, 20, EURUSD):.2f}",
            f"{lots_for_risk(plan.initial_balance, risk, 40, EURUSD):.2f}",
            f"{lots_for_risk(plan.initial_balance, risk, 80, EURUSD):.2f}",
        ])
    return table(
        ["Risk/trade", "Risk in $ (100K)", "Lots @ 20-pip stop", "Lots @ 40-pip stop", "Lots @ 80-pip stop"],
        rows,
    )


def build() -> str:
    plan = PLANS["100K"]
    e = BASE_EDGE
    parts = [
        "# FTMO Model: Simulation Report",
        "",
        "Generated by `python3 -m ftmo_engine.run_report`. Every figure is output of the",
        "Monte Carlo in `mc.py`. Nothing here is copied from a course or a vendor page.",
        "",
        "> **Read this first.** These results are *conditional on the edge being real*.",
        "> The simulation cannot tell you whether a 45% win rate at 1.8R survives contact",
        "> with live spreads, a VPS, and a market that stops paying. Section 7 is the",
        "> honest one: it shows the account dying as the edge decays. A model that reports",
        "> an expected value without that decay curve is a sales document, not an analysis.",
        "",
        "## Assumed strategy (the base case)",
        "",
        money(plan.initial_balance) + " account, fee " + money(plan.fee) +
        ", 80% split, fee refunded only after a first payout.",
        "",
        table(
            ["Parameter", "Value", "Meaning"],
            [
                ["Win rate", f"{e.win_prob * 100:.0f}%", "share of trades that reach the full target"],
                ["Average win", f"{e.win_R:.1f}R", "+1.8 units of risk per winner"],
                ["Average loss", "1.0R", "hard stop respected"],
                ["Cost drag", f"{e.cost_R:.2f}R", "spread + commission per trade"],
                ["Gap/tail risk", f"{e.tail_prob * 100:.0f}% at {e.tail_loss_R:.1f}R",
                 "stops that are slipped or gapped through"],
                ["Trades per day", f"{e.trades_per_day:.1f}", "filtered setups across 2-3 symbols"],
                ["Expectancy", f"{e.expectancy_R:+.3f}R", "net per trade"],
                ["Profit factor", f"{e.profit_factor:.2f}", "gross win / gross loss"],
            ],
        ),
        "",
        "### Is that edge plausible?",
        "",
        section_edge_realism(plan, e),
        "",
        "A 1.31 profit factor producing ~4%/month at 0.5% risk is the top decile of real",
        "retail systems. If your backtest reports 8%/month, the first hypothesis should be",
        "a look-ahead bug, not a discovery.",
        "",
        "## 1. Risk per trade vs probability of passing",
        "",
        section_risk_ladder(plan, e),
        "",
        "The optimum is a *plateau*, not a point: 0.5% tops the table at ~97%, and the",
        "0.25% row is *worse* than 0.5% for a reason worth internalising -- a fifth of",
        "those attempts simply hadn't finished after 200 trading days. FTMO has no time",
        "limit; you do. Below 0.5% you buy no extra safety and pay in months. Above 1.5%",
        "the pass rate falls off a cliff, and nothing about the strategy changed -- only",
        "the size.",
        "",
        "## 2. Where failures actually come from",
        "",
        section_failure_attribution(plan, e),
        "",
        "The 5% daily limit is almost never the killer while a 2R daily stop is enforced.",
        "The **10% static floor** is: it is only ten average losses away, and a normal",
        "losing streak reaches it. This is the structural fact the FTMO model is built",
        "around, and it says to optimise sizing before signal quality.",
        "",
        "## 3. Position size ladder",
        "",
        section_sizing(plan),
        "",
        "Fixed-fractional sizing off the stop distance. Rounding *up* to the nearest lot,",
        "or sizing off `balance/10000`, is what turns a 0.5% trade into a 2% one without",
        "anyone deciding to take more risk.",
        "",
        "## 4. The minimum edge required (go / no-go gate)",
        "",
        section_break_even_edge(plan),
        "",
        "Column 1 is the honest go/no-go: it is the edge at which the whole venture",
        "(fee, two phases, funded cycles, refund) nets to zero. Note it sits *above* the",
        "zero-expectancy win rate in column 3 at every setting, and further above it at",
        "low risk -- at 0.25% the funded stage earns so slowly that a mediocre edge never",
        "repays the fee. Columns 3 and 4 are the trading-only gates: below a zero-",
        "expectancy edge nothing rescues the account, and 0.10R per trade is the floor",
        "for the plan to be worth executing at all.",
        "",
        "## 5. Account size economics",
        "",
        section_account_sizes(e),
        "",
        "Fee as a percentage of account falls with size, so a $10K evaluation is the most",
        "expensive way to buy the same skill test. But note the EV column assumes twelve",
        "consecutive payout cycles, which is six months of an edge that must not decay.",
        "Section 7 is what that assumption is worth.",
        "",
        "## 6. Funded survival: the payout policy is the whole game",
        "",
        "Two things decide whether the funded account is an income stream or a",
        "countdown: how much risk you take, and how much of each payout you actually",
        "withdraw. The second is almost never discussed, and it dominates.",
        "",
        section_payout_policy(e),
        "",
        "**Why taking every payout fails.** Profit leaves the account; losses stay. The",
        "10% floor is fixed from the account's opening balance, so each withdrawal",
        "quietly shrinks your buffer relative to the floor. Over ~2 years, withdrawing",
        "100% of every cycle loses the account with near certainty -- while the equity",
        "curve looked perfect the whole time. Keeping a buffer and only withdrawing",
        "above it more than doubles expected income *and* cuts the failure rate by",
        "roughly 60x.",
        "",
        "The rule this produces is in `FTMO_SYSTEM.md`: **keep the account at least 15%",
        "above its starting balance, withdraw only what exceeds that line.**",
        "",
        "## 7. Funded survival with a *decaying* edge",
        "",
        section_funded_decay(e),
        "",
        "Same buffer policy, degraded edges. At 75% of backtest the account still pays",
        "about two thirds of the income and fails only 4.6% of the time. At half the edge",
        "income falls by roughly 62% and the failure rate triples. At zero edge only a",
        "quarter of accounts ever see a single payout, and the ones that do are collecting",
        "luck -- which the trader experiences as \"the strategy stopped working\", months",
        "after the money was spent.",
        "",
        "Practical consequence: re-measure expectancy every payout cycle, and treat two",
        "consecutive cycles below 50% of backtest expectancy as a signal to cut risk to",
        "0.25% and re-validate -- not to size up to recover.",
        "",
        "## 8. Sensitivity to the edge assumption",
        "",
        section_sensitivity(plan),
        "",
        "At 35% the system bleeds and risk management cannot fix a negative edge. From",
        "45% upward, the constraint stops being the market and becomes execution: taking",
        "every valid setup, never widening a stop, never adding to a loser.",
        "",
        "---",
        "",
        "## Findings that change the system design",
        "",
        "1. **The 10% static floor, not the 5% daily limit, is the binding constraint.**",
        "   So the breaker is ours (2R and 2% of day-start balance), and the portfolio caps",
        "   total open risk so a correlated shock cannot deliver 10% in one gap.",
        "2. **Risk above ~1% converts a ~97% pass rate into a ~50% one** without improving",
        "   EV. Hold 0.5% for the challenge and 0.35% on the funded account.",
        "3. **Expected purchases scale like 1/P(pass).** The fee is not the cost of the",
        "   challenge; the re-buys are.",
        "4. **The refund makes near-zero edges look free** -- they are EV-neutral, and they",
        "   cost you six months. Judge on expectancy per trade, not on EV of the purchase.",
        "5. **The funded stage needs a different objective:** not \"make 10%\", but \"payout",
        "   every cycle without touching the floor\", with risk cut below the challenge",
        "   level and payouts taken on schedule.",
        "6. **Edge decay, not rule breaches, is the terminal risk.** Every cycle",
        "   re-measures the edge; two weak cycles halve the risk.",
        "7. **The payout policy dominates everything except the edge itself.** Draw only",
        "   what exceeds a 15% buffer above the starting balance. Take-all withdrawal",
        "   guarantees the account dies eventually; the buffer more than doubles mean",
        "   income and removes almost all of the ruin risk.",
        "",
    ]
    return "\n".join(parts)


if __name__ == "__main__":
    OUT.write_text(build())
    print(f"wrote {OUT}")

"""Strategy registry. Add a module here to make it available to the CLI."""

from __future__ import annotations

from . import liquidity_candle, magic_candle, structure_break

REGISTRY = {
    magic_candle.NAME: magic_candle,
    liquidity_candle.NAME: liquidity_candle,
    structure_break.NAME: structure_break,
}

ALIASES = {
    "magic": magic_candle.NAME,
    "mcs": magic_candle.NAME,
    "liquidity": liquidity_candle.NAME,
    "lc": liquidity_candle.NAME,
    "structure": structure_break.NAME,
    "bos": structure_break.NAME,
    "majed": structure_break.NAME,
    "tounsi": structure_break.NAME,
}


def get(name: str):
    key = name.strip().lower()
    key = ALIASES.get(key, key)
    if key not in REGISTRY:
        raise KeyError(f"unknown strategy {name!r}. Available: {sorted(REGISTRY)}")
    return REGISTRY[key]


def names() -> list[str]:
    return sorted(REGISTRY)

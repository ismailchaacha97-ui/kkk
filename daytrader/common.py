"""Tiny shared helpers."""

from __future__ import annotations

import datetime as dt

__all__ = ["add_minutes", "parse_hhmm"]


def parse_hhmm(value: str) -> dt.time:
    """Parse a ``HH:MM`` string into :class:`datetime.time`."""
    try:
        hours, minutes = (int(part) for part in value.split(":"))
    except ValueError as exc:
        raise ValueError(f"invalid HH:MM time: {value!r}") from exc
    if not (0 <= hours <= 23 and 0 <= minutes <= 59):
        raise ValueError(f"invalid HH:MM time: {value!r}")
    return dt.time(hour=hours, minute=minutes)


def add_minutes(value: dt.time, minutes: int) -> dt.time:
    """Add minutes to a time of day (wrapping within the same day)."""
    base = dt.datetime.combine(dt.date(2000, 1, 1), value)
    return (base + dt.timedelta(minutes=minutes)).time()

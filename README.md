# 3 Tier London Breakout — broker time

The session box is no longer a raw clock string. V.3.3 reads the broker GMT
offset from the server and shifts `StartTime`, `EndTime`, and `SessionEndTime`
onto chart time automatically.

## Why

MT4 charts use **broker server time**. The original V.3.2b built the London
box with `StrToTime("… 06:00")`, so `06:00` meant whatever the book printed.
A GMT+3 server and a GMT+0 server did not show the same real-world window.

## What changed

`indicators/3_Tier_London_Breakout_V3.3_BrokerTime.mq4`

- `AutoAdjustToBrokerTime = true` (default)
- `TimesAreSpecifiedIn = London | GMT | GMT+2 | Broker`
- `BrokerGMTOffsetHours = 99` auto-detects `TimeCurrent() − TimeGMT()`
- `BrokerDST = Auto | EET | EST | Off` so historical days stay aligned
- On-chart dashboard prints the live offset and the converted box

Keep your usual `06:00` / `09:14` / `04:30` inputs. Set the base to **London**
if those are London wall times, **GMT+2** if you want the original GMT+2
calibration on any book, or **Broker** for the old as-is behaviour.

## Install

1. Copy the `.mq4` into `MQL4/Indicators`
2. Compile in MetaEditor
3. Attach to a chart

Open `web/index.html` to preview the same conversion against common brokers.

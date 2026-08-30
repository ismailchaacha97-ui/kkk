#!/usr/bin/env python3
"""Convert Dukascopy tick CSVs (FX-Data/FX-Data-EURUSD-DS) into M1 OHLC bars.

Tick format: 2021.01.04 00:00:00.401,bid,ask,bidvol,askvol   (GMT)

Output: backtest/data/EURUSD_M1_<year>.csv.gz with columns
        time,o,h,l,c,spread   (bid OHLC like an MT4 chart, spread = mean ask-bid)

Usage: python3 build_m1.py /tmp/fxdata/EURUSD/2021 data/EURUSD_M1_2021.csv.gz
"""
import sys, os, glob
import pandas as pd
import numpy as np

def convert(src_dir, out_file):
    files = sorted(glob.glob(os.path.join(src_dir, '*', '*.csv')))
    if not files:
        raise SystemExit('no csv files in %s' % src_dir)
    print('%s: %d hourly files' % (src_dir, len(files)))
    chunks = []
    for i, f in enumerate(files):
        df = pd.read_csv(f, header=None, names=['ts', 'bid', 'ask', 'bv', 'av'],
                         usecols=['ts', 'bid', 'ask'], dtype={'ts': str, 'bid': np.float64, 'ask': np.float64})
        if len(df) == 0:
            continue
        t = pd.to_datetime(df['ts'], format='%Y.%m.%d %H:%M:%S.%f')
        minute = t.dt.floor('min')
        g = df.assign(minute=minute, spread=df['ask'] - df['bid']).groupby('minute', sort=True)
        bars = g.agg(o=('bid', 'first'), h=('bid', 'max'), l=('bid', 'min'),
                     c=('bid', 'last'), spread=('spread', 'mean'))
        chunks.append(bars)
        if (i + 1) % 1000 == 0:
            print('  %d/%d files' % (i + 1, len(files)))
    full = pd.concat(chunks).sort_index()
    full.index.name = 'time'
    full = full.reset_index()
    full['time'] = full['time'].dt.strftime('%Y-%m-%d %H:%M:%S')
    full.to_csv(out_file, index=False, float_format='%.5f',
                compression={'method': 'gzip', 'compresslevel': 9})
    print('bars: %d  range: %s .. %s  avg spread: %.5f (%.1f pips)' % (
        len(full), full['time'].iloc[0], full['time'].iloc[-1],
        full['spread'].mean(), full['spread'].mean() / 1e-4))

if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2])

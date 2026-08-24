/**
 * Second Entry Price Action Indicator - Interactive Web Visualizer & Backtester
 * Implements 21 EMA Dynamic S/R, Naked S/R Levels, and 2EL / 2ES PATs Pattern Recognition.
 */

// Global State
let candles = [];
let emaData = [];
let srLevels = [];
let signals = [];
let trades = [];
let isPlaying = false;
let playInterval = null;
let currentBarIndex = 120; // Visible window endpoint

// Indicator Display Options
let showEMA = true;
let showSR = true;
let showSLTP = true;
let show1E = false;

// Indicator Config Parameters
let config = {
  emaPeriod: 21,
  minWickPct: 35,
  riskReward: 2.0,
  maxProximityPips: 8.0,
  strictTrend: true,
  currentPreset: 'EURUSD'
};

// Preset configurations
const PRESETS = {
  EURUSD: { name: 'EUR/USD', timeframe: 'M5', basePrice: 1.0850, volatility: 0.0004, pipSize: 0.0001, decimals: 5 },
  GBPUSD: { name: 'GBP/USD', timeframe: 'M15', basePrice: 1.2720, volatility: 0.0006, pipSize: 0.0001, decimals: 5 },
  XAUUSD: { name: 'Gold (XAU/USD)', timeframe: 'M5', basePrice: 2380.0, volatility: 1.5, pipSize: 0.1, decimals: 2 },
  ES: { name: 'S&P 500 E-mini', timeframe: 'M5', basePrice: 5620.0, volatility: 2.8, pipSize: 0.25, decimals: 2 }
};

// Canvas & Chart dimensions
let canvas, ctx;
let chartWidth, chartHeight;
let candleWidth = 8;
let candleGap = 4;
let visibleBarsCount = 65;
let dragStartX = 0;
let isDragging = false;

// Initialize on page load
window.addEventListener('DOMContentLoaded', () => {
  initCanvas();
  generateMarketData();
  recalculateStrategy();
  setupEventListeners();
  loadMql4Source();
});

// Canvas Setup & Resize
function initCanvas() {
  canvas = document.getElementById('trading-canvas');
  ctx = canvas.getContext('2d');
  resizeCanvas();
  window.addEventListener('resize', () => {
    resizeCanvas();
    renderChart();
  });
}

function resizeCanvas() {
  const container = document.getElementById('chart-container');
  const dpr = window.devicePixelRatio || 1;
  chartWidth = container.clientWidth;
  chartHeight = container.clientHeight;

  canvas.width = chartWidth * dpr;
  canvas.height = chartHeight * dpr;
  canvas.style.width = `${chartWidth}px`;
  canvas.style.height = `${chartHeight}px`;

  ctx.scale(dpr, dpr);
}

// Generate Realistic Trending Price Action with Pullbacks
function generateMarketData() {
  const preset = PRESETS[config.currentPreset];
  candles = [];
  let price = preset.basePrice;
  let trend = preset.volatility * 0.8;
  const totalBars = 350;

  for (let i = 0; i < totalBars; i++) {
    // Alternate trends to create pullbacks and 2nd entries
    if (i % 45 === 0) {
      trend = (Math.random() > 0.5 ? 1 : -1) * preset.volatility * (0.6 + Math.random() * 0.8);
    }

    const noise = (Math.random() - 0.5) * preset.volatility * 1.5;
    const open = price;
    let change = trend + noise;
    
    // Occasional sharp pullback testing EMA
    if (i % 12 === 0) {
      change = -trend * 1.4;
    }

    const close = open + change;
    const high = Math.max(open, close) + Math.random() * preset.volatility * 0.9;
    const low = Math.min(open, close) - Math.random() * preset.volatility * 0.9;
    price = close;

    candles.push({
      index: i,
      time: new Date(Date.now() - (totalBars - i) * 5 * 60 * 1000),
      open,
      high,
      low,
      close
    });
  }

  currentBarIndex = Math.min(180, totalBars - 1);
}

// Calculate EMA, S/R, and 2EL / 2ES Signals
function recalculateStrategy() {
  const preset = PRESETS[config.currentPreset];
  const pip = preset.pipSize;
  const k = 2.0 / (config.emaPeriod + 1.0);

  // 1. Calculate EMA
  emaData = [];
  let curEma = candles[0].close;
  for (let i = 0; i < candles.length; i++) {
    curEma = (candles[i].close * k) + (curEma * (1.0 - k));
    const prevEma = i > 0 ? emaData[i - 1].value : curEma;
    const slope = (curEma - prevEma) / pip;
    
    let trend = 'neutral';
    if (slope > 0.5) trend = 'bullish';
    else if (slope < -0.5) trend = 'bearish';

    emaData.push({ value: curEma, slope, trend });
  }

  // 2. Calculate Naked Horizontal Support & Resistance Levels
  srLevels = [];
  const swingStrength = 4;
  const rawHighs = [];
  const rawLows = [];

  for (let i = swingStrength; i < candles.length - swingStrength; i++) {
    let isHigh = true;
    let isLow = true;
    for (let s = 1; s <= swingStrength; s++) {
      if (candles[i].high <= candles[i - s].high || candles[i].high < candles[i + s].high) isHigh = false;
      if (candles[i].low >= candles[i - s].low || candles[i].low > candles[i + s].low) isLow = false;
    }
    if (isHigh) rawHighs.push({ price: candles[i].high, bar: i });
    if (isLow) rawLows.push({ price: candles[i].low, bar: i });
  }

  // Cluster S/R touches
  const zoneSize = 6.0 * pip;
  // Resistance
  rawHighs.forEach(h => {
    let matched = srLevels.find(sr => !sr.isSupport && Math.abs(sr.price - h.price) <= zoneSize);
    if (matched) {
      matched.touches++;
      matched.price = (matched.price + h.price) / 2;
    } else {
      srLevels.push({ price: h.price, isSupport: false, touches: 1 });
    }
  });

  // Support
  rawLows.forEach(l => {
    let matched = srLevels.find(sr => sr.isSupport && Math.abs(sr.price - l.price) <= zoneSize);
    if (matched) {
      matched.touches++;
      matched.price = (matched.price + l.price) / 2;
    } else {
      srLevels.push({ price: l.price, isSupport: true, touches: 1 });
    }
  });

  srLevels = srLevels.filter(s => s.touches >= 2).slice(0, 6);

  // 3. Detect Second Entry Long (2EL) and Second Entry Short (2ES)
  signals = [];
  trades = [];

  for (let i = 25; i < candles.length; i++) {
    const c = candles[i];
    const prevC = candles[i - 1];
    const ema = emaData[i].value;
    const slope = emaData[i].slope;
    const range = c.high - c.low;

    if (range <= 0) continue;

    const lowerWick = Math.min(c.open, c.close) - c.low;
    const upperWick = c.high - Math.max(c.open, c.close);
    const lowerWickPct = (lowerWick / range) * 100;
    const upperWickPct = (upperWick / range) * 100;

    // --- BULLISH 2EL SETUP ---
    const isUptrend = config.strictTrend ? (slope > 0.1 && c.close >= ema) : (c.close >= ema - 2 * pip);
    if (isUptrend) {
      // Find Swing High in last 20 bars
      let swingHigh = -1;
      let maxH = -1;
      for (let k = i - 1; k >= Math.max(0, i - 20); k--) {
        if (candles[k].high > maxH && candles[k].high > emaData[k].value) {
          maxH = candles[k].high;
          swingHigh = k;
        }
      }

      if (swingHigh > 0 && i - swingHigh >= 2) {
        // Look for 1EL
        let firstEntryBar = -1;
        for (let b = swingHigh + 1; b < i; b++) {
          if (candles[b].high > candles[b - 1].high) {
            firstEntryBar = b;
            break;
          }
        }

        if (firstEntryBar > 0) {
          // Look for Leg 2 down
          let leg2Down = false;
          for (let b = firstEntryBar + 1; b <= i; b++) {
            if (candles[b].low < candles[b - 1].low) {
              leg2Down = true;
              break;
            }
          }

          if (leg2Down) {
            // Signal candle rejection check
            const touchesEma = c.low <= ema + (config.maxProximityPips * pip);
            const isRejection = lowerWickPct >= config.minWickPct && c.close >= (c.low + range * 0.4);

            if (touchesEma && isRejection) {
              const sl = c.low - (2 * pip);
              const risk = c.close - sl;
              const tp = c.close + (risk * config.riskReward);

              signals.push({
                bar: i,
                type: '2EL',
                price: c.close,
                sl,
                tp,
                wickPct: lowerWickPct,
                firstEntryBar
              });
            }
          }
        }
      }
    }

    // --- BEARISH 2ES SETUP ---
    const isDowntrend = config.strictTrend ? (slope < -0.1 && c.close <= ema) : (c.close <= ema + 2 * pip);
    if (isDowntrend) {
      // Find Swing Low in last 20 bars
      let swingLow = -1;
      let minL = 999999;
      for (let k = i - 1; k >= Math.max(0, i - 20); k--) {
        if (candles[k].low < minL && candles[k].low < emaData[k].value) {
          minL = candles[k].low;
          swingLow = k;
        }
      }

      if (swingLow > 0 && i - swingLow >= 2) {
        // Look for 1ES
        let firstEntryBar = -1;
        for (let b = swingLow + 1; b < i; b++) {
          if (candles[b].low < candles[b - 1].low) {
            firstEntryBar = b;
            break;
          }
        }

        if (firstEntryBar > 0) {
          // Look for Leg 2 up
          let leg2Up = false;
          for (let b = firstEntryBar + 1; b <= i; b++) {
            if (candles[b].high > candles[b - 1].high) {
              leg2Up = true;
              break;
            }
          }

          if (leg2Up) {
            // Signal candle rejection check
            const touchesEma = c.high >= ema - (config.maxProximityPips * pip);
            const isRejection = upperWickPct >= config.minWickPct && c.close <= (c.high - range * 0.4);

            if (touchesEma && isRejection) {
              const sl = c.high + (2 * pip);
              const risk = sl - c.close;
              const tp = c.close - (risk * config.riskReward);

              signals.push({
                bar: i,
                type: '2ES',
                price: c.close,
                sl,
                tp,
                wickPct: upperWickPct,
                firstEntryBar
              });
            }
          }
        }
      }
    }
  }

  // 4. Simulate Trades & Outlier Outcomes
  simulateTradeOutcomes();
  updateBacktestUI();
  renderChart();
}

// Simulate trade outcomes on forward bars
function simulateTradeOutcomes() {
  trades = [];
  for (const sig of signals) {
    let outcome = 'OPEN';
    let exitBar = sig.bar;
    let exitPrice = sig.price;
    let pnlR = 0;

    for (let f = sig.bar + 1; f < candles.length; f++) {
      const c = candles[f];
      if (sig.type === '2EL') {
        if (c.low <= sig.sl) {
          outcome = 'LOSS';
          exitBar = f;
          exitPrice = sig.sl;
          pnlR = -1.0;
          break;
        } else if (c.high >= sig.tp) {
          outcome = 'WIN';
          exitBar = f;
          exitPrice = sig.tp;
          pnlR = config.riskReward;
          break;
        }
      } else if (sig.type === '2ES') {
        if (c.high >= sig.sl) {
          outcome = 'LOSS';
          exitBar = f;
          exitPrice = sig.sl;
          pnlR = -1.0;
          break;
        } else if (c.low <= sig.tp) {
          outcome = 'WIN';
          exitBar = f;
          exitPrice = sig.tp;
          pnlR = config.riskReward;
          break;
        }
      }
    }

    trades.push({
      ...sig,
      outcome,
      exitBar,
      exitPrice,
      pnlR
    });
  }
}

// Render Candlestick Chart & Overlays on HTML5 Canvas
function renderChart() {
  if (!ctx) return;
  const preset = PRESETS[config.currentPreset];
  const decimals = preset.decimals;

  ctx.clearRect(0, 0, chartWidth, chartHeight);

  // Background
  ctx.fillStyle = '#030712';
  ctx.fillRect(0, 0, chartWidth, chartHeight);

  // Compute visible range
  const startIdx = Math.max(0, currentBarIndex - visibleBarsCount);
  const endIdx = currentBarIndex;
  const visibleCandles = candles.slice(startIdx, endIdx + 1);

  if (visibleCandles.length === 0) return;

  // Find min and max price
  let minPrice = Infinity;
  let maxPrice = -Infinity;

  visibleCandles.forEach(c => {
    if (c.low < minPrice) minPrice = c.low;
    if (c.high > maxPrice) maxPrice = c.high;
  });

  // Include EMA in range
  for (let i = startIdx; i <= endIdx; i++) {
    if (emaData[i]) {
      if (emaData[i].value < minPrice) minPrice = emaData[i].value;
      if (emaData[i].value > maxPrice) maxPrice = emaData[i].value;
    }
  }

  // Padding
  const pricePadding = (maxPrice - minPrice) * 0.1 || 0.001;
  minPrice -= pricePadding;
  maxPrice += pricePadding;
  const priceRange = maxPrice - minPrice;

  const chartPaddingTop = 20;
  const chartPaddingBottom = 30;
  const chartPaddingRight = 65;
  const usableHeight = chartHeight - chartPaddingTop - chartPaddingBottom;
  const usableWidth = chartWidth - chartPaddingRight;

  const barStep = usableWidth / visibleCandles.length;
  const barWidth = Math.max(3, barStep * 0.65);

  function getX(index) {
    return (index - startIdx) * barStep + (barStep / 2);
  }

  function getY(price) {
    return chartHeight - chartPaddingBottom - ((price - minPrice) / priceRange) * usableHeight;
  }

  // 1. Grid Lines
  ctx.lineWidth = 1;
  ctx.strokeStyle = '#1e293b';
  const gridSteps = 6;
  for (let i = 0; i <= gridSteps; i++) {
    const p = minPrice + (priceRange / gridSteps) * i;
    const y = getY(p);
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(usableWidth, y);
    ctx.stroke();

    // Price label on right axis
    ctx.fillStyle = '#64748b';
    ctx.font = '10px "JetBrains Mono", monospace';
    ctx.fillText(p.toFixed(decimals), usableWidth + 6, y + 3);
  }

  // 2. Naked Horizontal S/R Levels
  if (showSR) {
    srLevels.forEach(sr => {
      if (sr.price >= minPrice && sr.price <= maxPrice) {
        const y = getY(sr.price);
        ctx.save();
        ctx.strokeStyle = sr.isSupport ? 'rgba(56, 189, 248, 0.45)' : 'rgba(251, 113, 133, 0.45)';
        ctx.setLineDash([5, 4]);
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(usableWidth, y);
        ctx.stroke();

        ctx.fillStyle = sr.isSupport ? '#38bdf8' : '#fb7138';
        ctx.font = '9px "Plus Jakarta Sans", sans-serif';
        const label = `${sr.isSupport ? 'Key Support' : 'Key Resistance'} (${sr.touches} tests)`;
        ctx.fillText(label, 10, y - 4);
        ctx.restore();
      }
    });
  }

  // 3. Dynamic 21 EMA Line
  if (showEMA) {
    ctx.lineWidth = 2.5;
    for (let i = startIdx; i < endIdx; i++) {
      if (!emaData[i] || !emaData[i + 1]) continue;
      const x1 = getX(i);
      const y1 = getY(emaData[i].value);
      const x2 = getX(i + 1);
      const y2 = getY(emaData[i + 1].value);

      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);

      if (emaData[i].trend === 'bullish') ctx.strokeStyle = '#10b981'; // Green
      else if (emaData[i].trend === 'bearish') ctx.strokeStyle = '#f43f5e'; // Red
      else ctx.strokeStyle = '#3b82f6'; // Blue / Neutral

      ctx.stroke();
    }
  }

  // 4. Candlesticks
  for (let i = startIdx; i <= endIdx; i++) {
    const c = candles[i];
    const x = getX(i);
    const isBullish = c.close >= c.open;
    const bodyTop = getY(Math.max(c.open, c.close));
    const bodyBottom = getY(Math.min(c.open, c.close));
    const bodyHeight = Math.max(1.5, bodyBottom - bodyTop);

    const candleColor = isBullish ? '#10b981' : '#f43f5e';

    // Wick
    ctx.strokeStyle = candleColor;
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.moveTo(x, getY(c.high));
    ctx.lineTo(x, getY(c.low));
    ctx.stroke();

    // Body
    ctx.fillStyle = isBullish ? '#064e3b' : '#881337';
    ctx.fillRect(x - barWidth / 2, bodyTop, barWidth, bodyHeight);
    ctx.strokeStyle = candleColor;
    ctx.strokeRect(x - barWidth / 2, bodyTop, barWidth, bodyHeight);
  }

  // 5. Signals: 2EL (Buy) and 2ES (Sell)
  signals.forEach(sig => {
    if (sig.bar < startIdx || sig.bar > endIdx) return;
    const x = getX(sig.bar);
    const c = candles[sig.bar];

    if (sig.type === '2EL') {
      const arrowY = getY(c.low) + 12;
      // Draw Lime Green Arrow
      ctx.fillStyle = '#22c55e';
      ctx.beginPath();
      ctx.moveTo(x, arrowY - 6);
      ctx.lineTo(x - 6, arrowY + 6);
      ctx.lineTo(x + 6, arrowY + 6);
      ctx.closePath();
      ctx.fill();

      // Label "2EL"
      ctx.fillStyle = '#4ade80';
      ctx.font = 'bold 10px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.fillText('2EL', x, arrowY + 18);

      // Draw SL/TP Lines
      if (showSLTP) {
        ctx.save();
        ctx.setLineDash([3, 3]);
        ctx.lineWidth = 1;

        // SL
        ctx.strokeStyle = '#f43f5e';
        ctx.beginPath();
        ctx.moveTo(x, getY(sig.sl));
        ctx.lineTo(x + barStep * 6, getY(sig.sl));
        ctx.stroke();

        // TP
        ctx.strokeStyle = '#10b981';
        ctx.beginPath();
        ctx.moveTo(x, getY(sig.tp));
        ctx.lineTo(x + barStep * 6, getY(sig.tp));
        ctx.stroke();
        ctx.restore();
      }

    } else if (sig.type === '2ES') {
      const arrowY = getY(c.high) - 12;
      // Draw Red Arrow
      ctx.fillStyle = '#ef4444';
      ctx.beginPath();
      ctx.moveTo(x, arrowY + 6);
      ctx.lineTo(x - 6, arrowY - 6);
      ctx.lineTo(x + 6, arrowY - 6);
      ctx.closePath();
      ctx.fill();

      // Label "2ES"
      ctx.fillStyle = '#f87171';
      ctx.font = 'bold 10px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.fillText('2ES', x, arrowY - 12);

      // Draw SL/TP Lines
      if (showSLTP) {
        ctx.save();
        ctx.setLineDash([3, 3]);
        ctx.lineWidth = 1;

        // SL
        ctx.strokeStyle = '#f43f5e';
        ctx.beginPath();
        ctx.moveTo(x, getY(sig.sl));
        ctx.lineTo(x + barStep * 6, getY(sig.sl));
        ctx.stroke();

        // TP
        ctx.strokeStyle = '#10b981';
        ctx.beginPath();
        ctx.moveTo(x, getY(sig.tp));
        ctx.lineTo(x + barStep * 6, getY(sig.tp));
        ctx.stroke();
        ctx.restore();
      }
    }
  });

  // 6. Educational 1E Markers
  if (show1E) {
    signals.forEach(sig => {
      if (sig.firstEntryBar >= startIdx && sig.firstEntryBar <= endIdx) {
        const x = getX(sig.firstEntryBar);
        const c = candles[sig.firstEntryBar];
        ctx.fillStyle = '#94a3b8';
        ctx.beginPath();
        ctx.arc(x, sig.type === '2EL' ? getY(c.low) + 8 : getY(c.high) - 8, 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.font = '8px monospace';
        ctx.fillText(sig.type === '2EL' ? '1EL' : '1ES', x, sig.type === '2EL' ? getY(c.low) + 18 : getY(c.high) - 12);
      }
    });
  }

  // Update Header Bar OHLC
  const lastC = candles[currentBarIndex];
  if (lastC) {
    document.getElementById('bar-o').textContent = lastC.open.toFixed(decimals);
    document.getElementById('bar-h').textContent = lastC.high.toFixed(decimals);
    document.getElementById('bar-l').textContent = lastC.low.toFixed(decimals);
    document.getElementById('bar-c').textContent = lastC.close.toFixed(decimals);

    // Update HUD Panel
    const curEma = emaData[currentBarIndex];
    if (curEma) {
      document.getElementById('hud-ema').textContent = curEma.value.toFixed(decimals);
      document.getElementById('hud-slope').textContent = (curEma.slope >= 0 ? '+' : '') + curEma.slope.toFixed(1) + ' pips';
      
      const trendEl = document.getElementById('hud-trend');
      if (curEma.trend === 'bullish') {
        trendEl.textContent = 'BULLISH';
        trendEl.className = 'text-emerald-400 font-bold';
        document.getElementById('hud-state').textContent = 'Scanning for 2EL pullback off 21 EMA...';
      } else if (curEma.trend === 'bearish') {
        trendEl.textContent = 'BEARISH';
        trendEl.className = 'text-rose-400 font-bold';
        document.getElementById('hud-state').textContent = 'Scanning for 2ES pullback off 21 EMA...';
      } else {
        trendEl.textContent = 'NEUTRAL / FLAT';
        trendEl.className = 'text-amber-400 font-bold';
        document.getElementById('hud-state').textContent = 'Waiting for clean EMA slope...';
      }
    }
  }
}

// Update Backtest Stats and Trade Log in UI
function updateBacktestUI() {
  const el2Count = signals.filter(s => s.type === '2EL').length;
  const es2Count = signals.filter(s => s.type === '2ES').length;
  const completedTrades = trades.filter(t => t.outcome !== 'OPEN');
  const wins = completedTrades.filter(t => t.outcome === 'WIN').length;
  const total = completedTrades.length;

  const winRate = total > 0 ? ((wins / total) * 100).toFixed(1) : '0.0';
  let totalR = 0;
  let maxDD = 0;
  let peakR = 0;
  let grossWin = 0;
  let grossLoss = 0;

  completedTrades.forEach(t => {
    totalR += t.pnlR;
    if (totalR > peakR) peakR = totalR;
    const dd = peakR - totalR;
    if (dd > maxDD) maxDD = dd;

    if (t.pnlR > 0) grossWin += t.pnlR;
    else grossLoss += Math.abs(t.pnlR);
  });

  const profitFactor = grossLoss > 0 ? (grossWin / grossLoss).toFixed(2) : (grossWin > 0 ? '99.0' : '0.00');

  // Overview Stats
  document.getElementById('stat-2el-count').textContent = el2Count;
  document.getElementById('stat-2es-count').textContent = es2Count;
  document.getElementById('stat-winrate').textContent = `${winRate}% (${wins}/${total})`;

  // Backtest Tab Stats
  document.getElementById('bt-total-trades').textContent = total;
  document.getElementById('bt-win-rate').textContent = `${winRate}%`;
  document.getElementById('bt-profit-factor').textContent = profitFactor;
  document.getElementById('bt-total-gain').textContent = `${totalR >= 0 ? '+' : ''}${totalR.toFixed(1)} R`;
  document.getElementById('bt-max-dd').textContent = `-${maxDD.toFixed(1)} R`;
  document.getElementById('bt-avg-rr').textContent = `1:${config.riskReward.toFixed(1)}`;

  // Populate Trade Log Table
  const tbody = document.getElementById('trade-log-tbody');
  tbody.innerHTML = '';

  const decimals = PRESETS[config.currentPreset].decimals;

  trades.slice().reverse().forEach((t, idx) => {
    const tr = document.createElement('tr');
    tr.className = 'hover:bg-slate-900/60 transition';

    const isWin = t.outcome === 'WIN';
    const isLoss = t.outcome === 'LOSS';
    const outcomeBadge = isWin
      ? `<span class="px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-400 font-bold">WIN</span>`
      : isLoss
      ? `<span class="px-2 py-0.5 rounded bg-rose-500/20 text-rose-400 font-bold">LOSS</span>`
      : `<span class="px-2 py-0.5 rounded bg-amber-500/20 text-amber-400">OPEN</span>`;

    const profitText = isWin ? `+${t.pnlR.toFixed(1)} R` : isLoss ? `-1.0 R` : `0.0 R`;
    const profitClass = isWin ? 'text-emerald-400 font-bold' : isLoss ? 'text-rose-400' : 'text-slate-400';

    tr.innerHTML = `
      <td class="py-2.5 px-3 text-slate-500">#${trades.length - idx}</td>
      <td class="py-2.5 px-3 font-bold ${t.type === '2EL' ? 'text-emerald-400' : 'text-rose-400'}">${t.type}</td>
      <td class="py-2.5 px-3 text-slate-200">${t.price.toFixed(decimals)}</td>
      <td class="py-2.5 px-3 text-rose-400">${t.sl.toFixed(decimals)}</td>
      <td class="py-2.5 px-3 text-emerald-400">${t.tp.toFixed(decimals)}</td>
      <td class="py-2.5 px-3 text-slate-400">${t.wickPct.toFixed(0)}%</td>
      <td class="py-2.5 px-3">${outcomeBadge}</td>
      <td class="py-2.5 px-3 ${profitClass}">${profitText}</td>
    `;
    tbody.appendChild(tr);
  });
}

// User Action Handlers
function stepForward() {
  if (currentBarIndex < candles.length - 1) {
    currentBarIndex++;
    renderChart();
  }
}

function toggleAutoPlay() {
  isPlaying = !isPlaying;
  const btn = document.getElementById('btn-play-pause');
  const icon = document.getElementById('play-icon');
  const text = document.getElementById('play-text');

  if (isPlaying) {
    text.textContent = 'Pause Stream';
    icon.innerHTML = '<path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"></path>';
    btn.className = 'px-3 py-1.5 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/30 font-semibold flex items-center space-x-1 transition';

    playInterval = setInterval(() => {
      if (currentBarIndex < candles.length - 1) {
        currentBarIndex++;
        renderChart();
      } else {
        toggleAutoPlay();
      }
    }, 450);
  } else {
    clearInterval(playInterval);
    text.textContent = 'Auto Stream';
    icon.innerHTML = '<path d="M8 5v14l11-7z"></path>';
    btn.className = 'px-3 py-1.5 rounded-lg bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 border border-emerald-500/30 font-semibold flex items-center space-x-1 transition';
  }
}

function regenerateData() {
  generateMarketData();
  recalculateStrategy();
}

function selectPreset(name) {
  config.currentPreset = name;
  const p = PRESETS[name];
  document.getElementById('market-pair-display').textContent = p.name;
  document.getElementById('timeframe-display').textContent = p.timeframe;

  document.querySelectorAll('.preset-btn').forEach(btn => btn.classList.remove('active'));
  event.currentTarget.classList.add('active');

  generateMarketData();
  recalculateStrategy();
}

function updateParams() {
  config.emaPeriod = parseInt(document.getElementById('param-ema-period').value);
  config.minWickPct = parseInt(document.getElementById('param-wick-pct').value);
  config.riskReward = parseFloat(document.getElementById('param-rr-ratio').value) / 10.0;
  config.maxProximityPips = parseFloat(document.getElementById('param-proximity').value);
  config.strictTrend = document.getElementById('param-strict-trend').checked;

  document.getElementById('val-ema-period').textContent = config.emaPeriod;
  document.getElementById('val-wick-pct').textContent = `${config.minWickPct}%`;
  document.getElementById('val-rr-ratio').textContent = `1:${config.riskReward.toFixed(1)}`;
  document.getElementById('val-proximity').textContent = config.maxProximityPips.toFixed(1);

  recalculateStrategy();
}

// Display Toggles
function toggleEMA() {
  showEMA = !showEMA;
  updateToggleBtn('toggle-ema', showEMA, 'bg-blue-500/20 text-blue-300 border-blue-500/30');
  renderChart();
}

function toggleSR() {
  showSR = !showSR;
  updateToggleBtn('toggle-sr', showSR, 'bg-purple-500/20 text-purple-300 border-purple-500/30');
  renderChart();
}

function toggleSLTP() {
  showSLTP = !showSLTP;
  updateToggleBtn('toggle-sltp', showSLTP, 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30');
  renderChart();
}

function toggle1E() {
  show1E = !show1E;
  updateToggleBtn('toggle-1e', show1E, 'bg-slate-700 text-slate-200 border-slate-600');
  renderChart();
}

function updateToggleBtn(id, active, activeClasses) {
  const el = document.getElementById(id);
  if (active) {
    el.className = `px-2.5 py-1 rounded-md font-medium border ${activeClasses}`;
  } else {
    el.className = 'px-2.5 py-1 rounded-md font-medium border bg-slate-900 text-slate-500 border-slate-800';
  }
}

// Navigation Tabs
function switchTab(tabId) {
  document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
  document.getElementById(`tab-${tabId}`).classList.remove('hidden');

  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.className = 'tab-btn px-3 py-1.5 rounded-lg text-sm font-medium transition text-slate-300 hover:text-white hover:bg-slate-800';
  });

  const activeBtn = document.getElementById(`tab-btn-${tabId}`);
  if (activeBtn) {
    activeBtn.className = 'tab-btn px-3 py-1.5 rounded-lg text-sm font-medium transition text-emerald-400 bg-slate-800/80 border border-slate-700';
  }

  if (tabId === 'chart') {
    resizeCanvas();
    renderChart();
  }
}

function runDetailedBacktest() {
  generateMarketData();
  recalculateStrategy();
}

// Load MQL4 source code into viewer
async function loadMql4Source() {
  try {
    const res = await fetch('/api/indicator-code');
    const data = await res.json();
    if (data.code) {
      document.getElementById('code-container').textContent = data.code;
    }
  } catch (e) {
    console.error('Failed to load MQL4 code', e);
  }
}

function copyCode() {
  const code = document.getElementById('code-container').textContent;
  navigator.clipboard.writeText(code).then(() => {
    const btn = document.getElementById('copy-text');
    btn.textContent = 'Copied!';
    setTimeout(() => btn.textContent = 'Copy Code', 2000);
  });
}

// Tooltip and Drag Event Listeners
function setupEventListeners() {
  canvas.addEventListener('mousemove', (e) => {
    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const startIdx = Math.max(0, currentBarIndex - visibleBarsCount);
    const usableWidth = chartWidth - 65;
    const barStep = usableWidth / (currentBarIndex - startIdx + 1);

    const hoverBarIndex = Math.floor(x / barStep) + startIdx;
    const tooltip = document.getElementById('chart-tooltip');

    if (hoverBarIndex >= 0 && hoverBarIndex < candles.length) {
      const c = candles[hoverBarIndex];
      const ema = emaData[hoverBarIndex];
      const sig = signals.find(s => s.bar === hoverBarIndex);
      const decimals = PRESETS[config.currentPreset].decimals;

      let html = `
        <div class="font-bold text-slate-200 border-b border-slate-700 pb-1">Bar #${hoverBarIndex}</div>
        <div class="text-slate-400">Open: <span class="text-white">${c.open.toFixed(decimals)}</span></div>
        <div class="text-slate-400">High: <span class="text-emerald-400">${c.high.toFixed(decimals)}</span></div>
        <div class="text-slate-400">Low: <span class="text-rose-400">${c.low.toFixed(decimals)}</span></div>
        <div class="text-slate-400">Close: <span class="text-white">${c.close.toFixed(decimals)}</span></div>
        <div class="text-slate-400">21 EMA: <span class="text-blue-300">${ema ? ema.value.toFixed(decimals) : '--'}</span></div>
      `;

      if (sig) {
        html += `
          <div class="mt-1 pt-1 border-t border-slate-700 font-bold ${sig.type === '2EL' ? 'text-emerald-400' : 'text-rose-400'}">
            ★ Setup: ${sig.type} (Rejection ${sig.wickPct.toFixed(0)}%)
          </div>
          <div class="text-[10px] text-slate-300">SL: ${sig.sl.toFixed(decimals)} | TP: ${sig.tp.toFixed(decimals)}</div>
        `;
      }

      tooltip.innerHTML = html;
      tooltip.style.left = `${Math.min(x + 15, chartWidth - 180)}px`;
      tooltip.style.top = `${Math.min(y + 15, chartHeight - 160)}px`;
      tooltip.classList.remove('hidden');
    } else {
      tooltip.classList.add('hidden');
    }
  });

  canvas.addEventListener('mouseleave', () => {
    document.getElementById('chart-tooltip').classList.add('hidden');
  });
}

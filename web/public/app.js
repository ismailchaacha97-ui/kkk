/**
 * 2L / 2S Price Action Strategy - Ultra-Clean Web Visualizer & Backtester
 * 1. Static S/R Mapping
 * 2. Candlestick Rejection & Absorption
 * 3. Second Entry Failure Patterns (2L & 2S)
 * 4. Market Structure Alignment (HH/HL vs LH/LL)
 * 5. Confluence with 13 / 50 EMA Dynamic Value Zone
 */

// Global State
let candles = [];
let fastEmaData = [];
let slowEmaData = [];
let srLevels = [];
let signals = [];
let trades = [];
let isPlaying = false;
let playInterval = null;
let currentBarIndex = 140;

// Display Options
let showEMA = true;
let showSR = true;
let showSLTP = false; // Off by default for cleaner chart
let show1E = false;

// Config Parameters
let config = {
  fastEmaPeriod: 13,
  slowEmaPeriod: 50,
  minWickPct: 35,
  riskReward: 2.0,
  maxProximityPips: 8.0,
  strictStructure: true,
  currentPreset: 'EURUSD'
};

// Preset configurations
const PRESETS = {
  EURUSD: { name: 'EUR/USD', timeframe: 'M5', basePrice: 1.0850, volatility: 0.0004, pipSize: 0.0001, decimals: 5 },
  GBPUSD: { name: 'GBP/USD', timeframe: 'M15', basePrice: 1.2720, volatility: 0.0006, pipSize: 0.0001, decimals: 5 },
  XAUUSD: { name: 'Gold (XAU/USD)', timeframe: 'M5', basePrice: 2380.0, volatility: 1.5, pipSize: 0.1, decimals: 2 },
  ES: { name: 'S&P 500 E-mini', timeframe: 'M5', basePrice: 5620.0, volatility: 2.8, pipSize: 0.25, decimals: 2 }
};

let canvas, ctx;
let chartWidth, chartHeight;
let visibleBarsCount = 65;

window.addEventListener('DOMContentLoaded', () => {
  initCanvas();
  generateMarketData();
  recalculateStrategy();
  setupEventListeners();
  loadMql4Source();
});

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

function generateMarketData() {
  const preset = PRESETS[config.currentPreset];
  candles = [];
  let price = preset.basePrice;
  let trend = preset.volatility * 0.9;
  const totalBars = 350;

  for (let i = 0; i < totalBars; i++) {
    if (i % 50 === 0) {
      trend = (Math.random() > 0.5 ? 1 : -1) * preset.volatility * (0.8 + Math.random() * 0.7);
    }

    const noise = (Math.random() - 0.5) * preset.volatility * 1.5;
    const open = price;
    let change = trend + noise;
    
    // Occasional 2-leg counter-trend pullback
    if (i % 14 === 0) {
      change = -trend * 1.4;
    }

    const close = open + change;
    const high = Math.max(open, close) + Math.random() * preset.volatility * 0.8;
    const low = Math.min(open, close) - Math.random() * preset.volatility * 0.8;
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

  currentBarIndex = Math.min(200, totalBars - 1);
}

function recalculateStrategy() {
  const preset = PRESETS[config.currentPreset];
  const pip = preset.pipSize;

  const kFast = 2.0 / (config.fastEmaPeriod + 1.0);
  const kSlow = 2.0 / (config.slowEmaPeriod + 1.0);

  fastEmaData = [];
  slowEmaData = [];

  let curFast = candles[0].close;
  let curSlow = candles[0].close;

  for (let i = 0; i < candles.length; i++) {
    curFast = (candles[i].close * kFast) + (curFast * (1.0 - kFast));
    curSlow = (candles[i].close * kSlow) + (curSlow * (1.0 - kSlow));

    const prevFast = i > 0 ? fastEmaData[i - 1].value : curFast;
    const slope = (curFast - prevFast) / pip;

    let trend = 'neutral';
    if (curFast > curSlow && slope > 0.2) trend = 'bullish';
    else if (curFast < curSlow && slope < -0.2) trend = 'bearish';

    fastEmaData.push({ value: curFast, slope, trend });
    slowEmaData.push({ value: curSlow });
  }

  // Static S/R Mapping
  srLevels = [];
  const swingStrength = 5;
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

  const zoneSize = 6.0 * pip;
  rawHighs.forEach(h => {
    let matched = srLevels.find(sr => !sr.isSupport && Math.abs(sr.price - h.price) <= zoneSize);
    if (matched) {
      matched.touches++;
      matched.price = (matched.price + h.price) / 2;
    } else {
      srLevels.push({ price: h.price, isSupport: false, touches: 1 });
    }
  });

  rawLows.forEach(l => {
    let matched = srLevels.find(sr => sr.isSupport && Math.abs(sr.price - l.price) <= zoneSize);
    if (matched) {
      matched.touches++;
      matched.price = (matched.price + l.price) / 2;
    } else {
      srLevels.push({ price: l.price, isSupport: true, touches: 1 });
    }
  });

  srLevels = srLevels.filter(s => s.touches >= 2).slice(0, 5);

  // Detect 2L and 2S Failure Patterns
  signals = [];
  trades = [];

  for (let i = 35; i < candles.length; i++) {
    const c = candles[i];
    const fastEma = fastEmaData[i].value;
    const slowEma = slowEmaData[i].value;
    const slope = fastEmaData[i].slope;
    const range = c.high - c.low;

    if (range <= 0) continue;

    const lowerWick = Math.min(c.open, c.close) - c.low;
    const upperWick = c.high - Math.max(c.open, c.close);
    const lowerWickPct = (lowerWick / range) * 100;
    const upperWickPct = (upperWick / range) * 100;

    // --- BULLISH SETUP: 2L ---
    const isBullTrend = (fastEma >= slowEma && slope >= -0.1 && c.close >= slowEma - 2 * pip);

    if (isBullTrend) {
      let swingHigh = -1;
      let maxH = -1;
      for (let k = i - 1; k >= Math.max(0, i - 20); k--) {
        if (candles[k].high > maxH && candles[k].high > fastEmaData[k].value) {
          maxH = candles[k].high;
          swingHigh = k;
        }
      }

      if (swingHigh > 0 && i - swingHigh >= 2) {
        let firstEntryBar = -1;
        for (let b = swingHigh + 1; b < i; b++) {
          if (candles[b].high > candles[b - 1].high) {
            firstEntryBar = b;
            break;
          }
        }

        if (firstEntryBar > 0) {
          let leg2Down = false;
          for (let b = firstEntryBar + 1; b <= i; b++) {
            if (candles[b].low < candles[b - 1].low) {
              leg2Down = true;
              break;
            }
          }

          if (leg2Down) {
            const isAbsorption = lowerWickPct >= config.minWickPct && c.close >= (c.low + range * 0.45);
            const touchesEMA = (c.low <= fastEma + (config.maxProximityPips * pip) && c.high >= fastEma - (config.maxProximityPips * pip)) ||
                               (c.low <= slowEma + (config.maxProximityPips * pip) && c.high >= slowEma - (config.maxProximityPips * pip));
            const nearSR = srLevels.some(sr => sr.isSupport && Math.abs(c.low - sr.price) <= 8 * pip);

            if (isAbsorption && (touchesEMA || nearSR)) {
              const sl = c.low - (2 * pip);
              const risk = c.close - sl;
              const tp = c.close + (risk * config.riskReward);

              signals.push({
                bar: i,
                type: '2L',
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

    // --- BEARISH SETUP: 2S ---
    const isBearTrend = (fastEma <= slowEma && slope <= 0.1 && c.close <= slowEma + 2 * pip);

    if (isBearTrend) {
      let swingLow = -1;
      let minL = 999999;
      for (let k = i - 1; k >= Math.max(0, i - 20); k--) {
        if (candles[k].low < minL && candles[k].low < fastEmaData[k].value) {
          minL = candles[k].low;
          swingLow = k;
        }
      }

      if (swingLow > 0 && i - swingLow >= 2) {
        let firstEntryBar = -1;
        for (let b = swingLow + 1; b < i; b++) {
          if (candles[b].low < candles[b - 1].low) {
            firstEntryBar = b;
            break;
          }
        }

        if (firstEntryBar > 0) {
          let leg2Up = false;
          for (let b = firstEntryBar + 1; b <= i; b++) {
            if (candles[b].high > candles[b - 1].high) {
              leg2Up = true;
              break;
            }
          }

          if (leg2Up) {
            const isAbsorption = upperWickPct >= config.minWickPct && c.close <= (c.high - range * 0.45);
            const touchesEMA = (c.high >= fastEma - (config.maxProximityPips * pip) && c.low <= fastEma + (config.maxProximityPips * pip)) ||
                               (c.high >= slowEma - (config.maxProximityPips * pip) && c.low <= slowEma + (config.maxProximityPips * pip));
            const nearSR = srLevels.some(sr => !sr.isSupport && Math.abs(c.high - sr.price) <= 8 * pip);

            if (isAbsorption && (touchesEMA || nearSR)) {
              const sl = c.high + (2 * pip);
              const risk = sl - c.close;
              const tp = c.close - (risk * config.riskReward);

              signals.push({
                bar: i,
                type: '2S',
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

  simulateTradeOutcomes();
  updateBacktestUI();
  renderChart();
}

function simulateTradeOutcomes() {
  trades = [];
  for (const sig of signals) {
    let outcome = 'OPEN';
    let exitBar = sig.bar;
    let exitPrice = sig.price;
    let pnlR = 0;

    for (let f = sig.bar + 1; f < candles.length; f++) {
      const c = candles[f];
      if (sig.type === '2L') {
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
      } else if (sig.type === '2S') {
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

// Render Clean Candlestick Chart
function renderChart() {
  if (!ctx) return;
  const preset = PRESETS[config.currentPreset];
  const decimals = preset.decimals;

  ctx.clearRect(0, 0, chartWidth, chartHeight);

  // Dark clean background
  ctx.fillStyle = '#080c14';
  ctx.fillRect(0, 0, chartWidth, chartHeight);

  const startIdx = Math.max(0, currentBarIndex - visibleBarsCount);
  const endIdx = currentBarIndex;
  const visibleCandles = candles.slice(startIdx, endIdx + 1);

  if (visibleCandles.length === 0) return;

  let minPrice = Infinity;
  let maxPrice = -Infinity;

  visibleCandles.forEach(c => {
    if (c.low < minPrice) minPrice = c.low;
    if (c.high > maxPrice) maxPrice = c.high;
  });

  for (let i = startIdx; i <= endIdx; i++) {
    if (fastEmaData[i]) {
      if (fastEmaData[i].value < minPrice) minPrice = fastEmaData[i].value;
      if (fastEmaData[i].value > maxPrice) maxPrice = fastEmaData[i].value;
    }
    if (slowEmaData[i]) {
      if (slowEmaData[i].value < minPrice) minPrice = slowEmaData[i].value;
      if (slowEmaData[i].value > maxPrice) maxPrice = slowEmaData[i].value;
    }
  }

  const pricePadding = (maxPrice - minPrice) * 0.1 || 0.001;
  minPrice -= pricePadding;
  maxPrice += pricePadding;
  const priceRange = maxPrice - minPrice;

  const chartPaddingTop = 25;
  const chartPaddingBottom = 30;
  const chartPaddingRight = 65;
  const usableHeight = chartHeight - chartPaddingTop - chartPaddingBottom;
  const usableWidth = chartWidth - chartPaddingRight;

  const barStep = usableWidth / visibleCandles.length;
  const barWidth = Math.max(3, barStep * 0.65);

  function getX(index) {
    return Math.floor((index - startIdx) * barStep + (barStep / 2)) + 0.5;
  }

  function getY(price) {
    return Math.floor(chartHeight - chartPaddingBottom - ((price - minPrice) / priceRange) * usableHeight) + 0.5;
  }

  // 1. Subtle Horizontal-Only Grid Lines (NO vertical lines)
  ctx.lineWidth = 1;
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
  const gridSteps = 5;
  for (let i = 0; i <= gridSteps; i++) {
    const p = minPrice + (priceRange / gridSteps) * i;
    const y = getY(p);
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(usableWidth, y);
    ctx.stroke();

    ctx.fillStyle = '#64748b';
    ctx.font = '10px "JetBrains Mono", monospace';
    ctx.fillText(p.toFixed(decimals), usableWidth + 6, y + 3);
  }

  // 2. Static Horizontal S/R Levels (Clean subtle dashed lines)
  if (showSR) {
    srLevels.forEach(sr => {
      if (sr.price >= minPrice && sr.price <= maxPrice) {
        const y = getY(sr.price);
        ctx.save();
        ctx.strokeStyle = sr.isSupport ? 'rgba(56, 189, 248, 0.35)' : 'rgba(251, 113, 133, 0.35)';
        ctx.setLineDash([4, 4]);
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(usableWidth, y);
        ctx.stroke();

        ctx.fillStyle = sr.isSupport ? '#38bdf8' : '#fb7138';
        ctx.font = '9px "Plus Jakarta Sans", sans-serif';
        const label = `${sr.isSupport ? 'Support' : 'Resistance'} (${sr.touches})`;
        ctx.fillText(label, 12, y - 4);
        ctx.restore();
      }
    });
  }

  // 3. Dual EMAs: 13 Fast & 50 Slow
  if (showEMA) {
    // 50 Slow EMA
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = '#f59e0b'; // Amber
    ctx.beginPath();
    for (let i = startIdx; i <= endIdx; i++) {
      const x = getX(i);
      const y = getY(slowEmaData[i].value);
      if (i === startIdx) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // 13 Fast EMA
    ctx.lineWidth = 2;
    for (let i = startIdx; i < endIdx; i++) {
      if (!fastEmaData[i] || !fastEmaData[i + 1]) continue;
      const x1 = getX(i);
      const y1 = getY(fastEmaData[i].value);
      const x2 = getX(i + 1);
      const y2 = getY(fastEmaData[i + 1].value);

      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);

      if (fastEmaData[i].trend === 'bullish') ctx.strokeStyle = '#10b981';
      else if (fastEmaData[i].trend === 'bearish') ctx.strokeStyle = '#f43f5e';
      else ctx.strokeStyle = '#3b82f6';

      ctx.stroke();
    }
  }

  // 4. Candlesticks (Clean & centered)
  for (let i = startIdx; i <= endIdx; i++) {
    const c = candles[i];
    const x = getX(i);
    const isBullish = c.close >= c.open;
    const bodyTop = getY(Math.max(c.open, c.close));
    const bodyBottom = getY(Math.min(c.open, c.close));
    const bodyHeight = Math.max(1.5, bodyBottom - bodyTop);

    const candleColor = isBullish ? '#22c55e' : '#ef4444';

    // Wick (Crisp 1px line exactly on candle center)
    ctx.strokeStyle = candleColor;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, getY(c.high));
    ctx.lineTo(x, getY(c.low));
    ctx.stroke();

    // Body
    ctx.fillStyle = isBullish ? '#15803d' : '#991b1b';
    ctx.fillRect(Math.floor(x - barWidth / 2), bodyTop, barWidth, bodyHeight);
    ctx.strokeStyle = candleColor;
    ctx.strokeRect(Math.floor(x - barWidth / 2), bodyTop, barWidth, bodyHeight);
  }

  // 5. Signals: 2L (Buy) and 2S (Sell)
  signals.forEach(sig => {
    if (sig.bar < startIdx || sig.bar > endIdx) return;
    const x = getX(sig.bar);
    const c = candles[sig.bar];

    if (sig.type === '2L') {
      const arrowY = getY(c.low) + 12;
      ctx.fillStyle = '#22c55e';
      ctx.beginPath();
      ctx.moveTo(x, arrowY - 5);
      ctx.lineTo(x - 5, arrowY + 5);
      ctx.lineTo(x + 5, arrowY + 5);
      ctx.closePath();
      ctx.fill();

      ctx.fillStyle = '#4ade80';
      ctx.font = 'bold 9px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.fillText('2L', x, arrowY + 16);

      if (showSLTP) {
        ctx.save();
        ctx.setLineDash([2, 2]);
        ctx.lineWidth = 1;
        ctx.strokeStyle = '#f43f5e';
        ctx.beginPath();
        ctx.moveTo(x - 4, getY(sig.sl));
        ctx.lineTo(x + 16, getY(sig.sl));
        ctx.stroke();

        ctx.strokeStyle = '#10b981';
        ctx.beginPath();
        ctx.moveTo(x - 4, getY(sig.tp));
        ctx.lineTo(x + 16, getY(sig.tp));
        ctx.stroke();
        ctx.restore();
      }

    } else if (sig.type === '2S') {
      const arrowY = getY(c.high) - 12;
      ctx.fillStyle = '#ef4444';
      ctx.beginPath();
      ctx.moveTo(x, arrowY + 5);
      ctx.lineTo(x - 5, arrowY - 5);
      ctx.lineTo(x + 5, arrowY - 5);
      ctx.closePath();
      ctx.fill();

      ctx.fillStyle = '#f87171';
      ctx.font = 'bold 9px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.fillText('2S', x, arrowY - 10);

      if (showSLTP) {
        ctx.save();
        ctx.setLineDash([2, 2]);
        ctx.lineWidth = 1;
        ctx.strokeStyle = '#f43f5e';
        ctx.beginPath();
        ctx.moveTo(x - 4, getY(sig.sl));
        ctx.lineTo(x + 16, getY(sig.sl));
        ctx.stroke();

        ctx.strokeStyle = '#10b981';
        ctx.beginPath();
        ctx.moveTo(x - 4, getY(sig.tp));
        ctx.lineTo(x + 16, getY(sig.tp));
        ctx.stroke();
        ctx.restore();
      }
    }
  });

  // 6. Educational 1E Markers (Optional)
  if (show1E) {
    signals.forEach(sig => {
      if (sig.firstEntryBar >= startIdx && sig.firstEntryBar <= endIdx) {
        const x = getX(sig.firstEntryBar);
        const c = candles[sig.firstEntryBar];
        ctx.fillStyle = '#64748b';
        ctx.beginPath();
        ctx.arc(x, sig.type === '2L' ? getY(c.low) + 6 : getY(c.high) - 6, 2.5, 0, Math.PI * 2);
        ctx.fill();
      }
    });
  }

  // Update Header Bar OHLC & HUD
  const lastC = candles[currentBarIndex];
  if (lastC) {
    document.getElementById('bar-o').textContent = lastC.open.toFixed(decimals);
    document.getElementById('bar-h').textContent = lastC.high.toFixed(decimals);
    document.getElementById('bar-l').textContent = lastC.low.toFixed(decimals);
    document.getElementById('bar-c').textContent = lastC.close.toFixed(decimals);

    const curFast = fastEmaData[currentBarIndex];
    const curSlow = slowEmaData[currentBarIndex];
    if (curFast && curSlow) {
      document.getElementById('hud-ema').textContent = `${curFast.value.toFixed(decimals)} / ${curSlow.value.toFixed(decimals)}`;
      document.getElementById('hud-slope').textContent = (curFast.slope >= 0 ? '+' : '') + curFast.slope.toFixed(1) + ' pips';
      
      const trendEl = document.getElementById('hud-trend');
      if (curFast.trend === 'bullish') {
        trendEl.textContent = 'BULLISH (HH/HL)';
        trendEl.className = 'text-emerald-400 font-bold';
        document.getElementById('hud-state').textContent = 'Scanning for 2L pullback testing 13/50 EMA...';
      } else if (curFast.trend === 'bearish') {
        trendEl.textContent = 'BEARISH (LH/LL)';
        trendEl.className = 'text-rose-400 font-bold';
        document.getElementById('hud-state').textContent = 'Scanning for 2S pullback testing 13/50 EMA...';
      } else {
        trendEl.textContent = 'CHOP / CONSOLIDATION';
        trendEl.className = 'text-amber-400 font-bold';
        document.getElementById('hud-state').textContent = 'Waiting for clean EMA separation...';
      }
    }
  }
}

// Update Backtest Stats and Trade Log in UI
function updateBacktestUI() {
  const el2Count = signals.filter(s => s.type === '2L').length;
  const es2Count = signals.filter(s => s.type === '2S').length;
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

  document.getElementById('stat-2el-count').textContent = el2Count;
  document.getElementById('stat-2es-count').textContent = es2Count;
  document.getElementById('stat-winrate').textContent = `${winRate}% (${wins}/${total})`;

  document.getElementById('bt-total-trades').textContent = total;
  document.getElementById('bt-win-rate').textContent = `${winRate}%`;
  document.getElementById('bt-profit-factor').textContent = profitFactor;
  document.getElementById('bt-total-gain').textContent = `${totalR >= 0 ? '+' : ''}${totalR.toFixed(1)} R`;
  document.getElementById('bt-max-dd').textContent = `-${maxDD.toFixed(1)} R`;
  document.getElementById('bt-avg-rr').textContent = `1:${config.riskReward.toFixed(1)}`;

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
      <td class="py-2.5 px-3 font-bold ${t.type === '2L' ? 'text-emerald-400' : 'text-rose-400'}">${t.type}</td>
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
  config.fastEmaPeriod = parseInt(document.getElementById('param-fast-ema').value);
  config.slowEmaPeriod = parseInt(document.getElementById('param-slow-ema').value);
  config.minWickPct = parseInt(document.getElementById('param-wick-pct').value);
  config.riskReward = parseFloat(document.getElementById('param-rr-ratio').value) / 10.0;
  config.strictStructure = document.getElementById('param-strict-trend').checked;

  document.getElementById('val-fast-ema').textContent = config.fastEmaPeriod;
  document.getElementById('val-slow-ema').textContent = config.slowEmaPeriod;
  document.getElementById('val-wick-pct').textContent = `${config.minWickPct}%`;
  document.getElementById('val-rr-ratio').textContent = `1:${config.riskReward.toFixed(1)}`;

  recalculateStrategy();
}

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
      const fastEma = fastEmaData[hoverBarIndex];
      const slowEma = slowEmaData[hoverBarIndex];
      const sig = signals.find(s => s.bar === hoverBarIndex);
      const decimals = PRESETS[config.currentPreset].decimals;

      let html = `
        <div class="font-bold text-slate-200 border-b border-slate-700 pb-1">Bar #${hoverBarIndex}</div>
        <div class="text-slate-400">Open: <span class="text-white">${c.open.toFixed(decimals)}</span></div>
        <div class="text-slate-400">High: <span class="text-emerald-400">${c.high.toFixed(decimals)}</span></div>
        <div class="text-slate-400">Low: <span class="text-rose-400">${c.low.toFixed(decimals)}</span></div>
        <div class="text-slate-400">Close: <span class="text-white">${c.close.toFixed(decimals)}</span></div>
        <div class="text-slate-400">13 EMA: <span class="text-blue-300">${fastEma ? fastEma.value.toFixed(decimals) : '--'}</span></div>
        <div class="text-slate-400">50 EMA: <span class="text-amber-400">${slowEma ? slowEma.value.toFixed(decimals) : '--'}</span></div>
      `;

      if (sig) {
        html += `
          <div class="mt-1 pt-1 border-t border-slate-700 font-bold ${sig.type === '2L' ? 'text-emerald-400' : 'text-rose-400'}">
            ★ Setup: ${sig.type} (Absorption ${sig.wickPct.toFixed(0)}%)
          </div>
          <div class="text-[10px] text-slate-300">SL: ${sig.sl.toFixed(decimals)} | TP: ${sig.tp.toFixed(decimals)}</div>
        `;
      }

      tooltip.innerHTML = html;
      tooltip.style.left = `${Math.min(x + 15, chartWidth - 180)}px`;
      tooltip.style.top = `${Math.min(y + 15, chartHeight - 170)}px`;
      tooltip.classList.remove('hidden');
    } else {
      tooltip.classList.add('hidden');
    }
  });

  canvas.addEventListener('mouseleave', () => {
    document.getElementById('chart-tooltip').classList.add('hidden');
  });
}

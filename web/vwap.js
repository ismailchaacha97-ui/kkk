/*!
 * VWAP Pro - JavaScript port of the MQL4 engine (web/vwap.js)
 *
 * This is a line-by-line port of MQL4/Include/VWAPPro/VpEngine.mqh and its
 * siblings, kept deliberately literal (same order of operations, same
 * compensated accumulators, same guards) so that it can be used as a THIRD
 * independent implementation for cross-checking:
 *
 *     node tools/check_js_port.js        # JS vs the C++ engine, bit for bit
 *
 * It powers the in-browser demonstration in web/index.html.
 *
 * Licence: MIT.  See LICENSE.
 */
(function (root, factory) {
  if (typeof module !== "undefined" && module.exports) module.exports = factory();
  else root.VWAPPro = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  //--- compat helpers (VpCompat.mqh) ---------------------------------
  function abs(x) { return Math.abs(x); }
  function sqrt(x) { return x <= 0 ? 0 : Math.sqrt(x); }
  function floor(x) { return Math.floor(x); }
  function round(x) { return Math.floor(x + 0.5); }
  function log(x) { return x > 0 ? Math.log(x) : 0; }
  function max(a, b) { return a > b ? a : b; }
  function min(a, b) { return a < b ? a : b; }
  function imax(a, b) { return a > b ? a : b; }
  function iabs(x) { return x < 0 ? -x : x; }
  function isFinite2(x) { return typeof x === "number" && isFinite(x); }

  function divSafe(num, den, fallback) {
    if (den === 0) return fallback;
    if (isNaN(den) || isNaN(num)) return fallback;
    var r = num / den;
    if (!isFinite(r)) return fallback;
    return r;
  }
  function clamp(x, lo, hi) {
    if (isNaN(x)) return lo;
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
  }
  function tanh(x) {
    if (isNaN(x)) return 0;
    if (x > 20) return 1;
    if (x < -20) return -1;
    var e2 = Math.exp(2 * x);
    if (!isFinite(e2)) return x > 0 ? 1 : -1;
    var t = (e2 - 1) / (e2 + 1);
    if (!isFinite(t)) return x > 0 ? 1 : -1;
    return t;
  }
  function floorDiv(a, b) { var q = a / b; return q < 0 ? Math.ceil(q) : Math.floor(q); }
  function floorMod(a, b) { var r = a % b; return r < 0 ? r + b : r; }

  //--- Kahan / Neumaier accumulator (VpEngine.mqh) -------------------
  function KSum() { this.sum = 0; this.comp = 0; }
  KSum.prototype.reset = function () { this.sum = 0; this.comp = 0; };
  KSum.prototype.add = function (x) {
    var t = this.sum + x;
    if (abs(this.sum) >= abs(x)) this.comp = this.comp + (this.sum - t) + x;
    else this.comp = this.comp + (x - t) + this.sum;
    this.sum = t;
  };
  KSum.prototype.val = function () { return this.sum + this.comp; };

  //--- moments (VpMath.mqh) -----------------------------------------
  function Moments() { this.n = 0; this.mean = 0; this.m2 = 0; }
  Moments.prototype.reset = function () { this.n = 0; this.mean = 0; this.m2 = 0; };
  Moments.prototype.push = function (x) {
    this.n++;
    var d = x - this.mean;
    this.mean = this.mean + d / this.n;
    this.m2 = this.m2 + d * (x - this.mean);
    if (this.m2 < 0) this.m2 = 0;
  };
  Moments.prototype.var_ = function () { return this.n < 2 ? 0 : Math.max(0, this.m2 / (this.n - 1)); };
  Moments.prototype.stdDev = function () { return sqrt(this.var_()); };

  function ATR() { this.period = 1; this.count = 0; this.seedSum = 0; this.value = 0; }
  ATR.prototype.reset = function (p) { this.period = imax(1, p); this.count = 0; this.seedSum = 0; this.value = 0; };
  ATR.prototype.push = function (tr0) {
    var tr = abs(tr0);
    if (!isFinite2(tr)) return;
    if (this.count < this.period) {
      this.seedSum += tr; this.count++;
      if (this.count === this.period) this.value = this.seedSum / this.period;
    } else {
      this.value = this.value + (tr - this.value) / this.period;
    }
  };
  ATR.prototype.ready = function () { return this.count >= this.period; };
  ATR.prototype.val = function () { return this.ready() ? this.value : 0; };

  function ADX() {
    this.period = 2; this.count = 0; this.trS = 0; this.dmpS = 0; this.dmmS = 0;
    this.trR = 0; this.dmpR = 0; this.dmmR = 0; this.adx = 0;
    this.adxCount = 0; this.adxSeedSum = 0;
    this.prevHigh = 0; this.prevLow = 0; this.prevClose = 0; this.havePrev = false;
  }
  ADX.prototype.reset = function (p) {
    this.period = imax(2, p);
    this.count = 0; this.trS = this.dmpS = this.dmmS = 0;
    this.trR = this.dmpR = this.dmmR = 0;
    this.adx = 0; this.adxCount = 0; this.adxSeedSum = 0; this.havePrev = false;
    this.prevHigh = this.prevLow = this.prevClose = 0;
  };
  ADX.prototype.push = function (high, low, close) {
    if (!this.havePrev) {
      this.prevHigh = high; this.prevLow = low; this.prevClose = close;
      this.havePrev = true; return;
    }
    var upMove = high - this.prevHigh, downMove = this.prevLow - low;
    var dmp = (upMove > downMove && upMove > 0) ? upMove : 0;
    var dmm = (downMove > upMove && downMove > 0) ? downMove : 0;
    var tr1 = high - low, tr2 = abs(high - this.prevClose), tr3 = abs(low - this.prevClose);
    var tr = max(tr1, max(tr2, tr3));
    this.prevHigh = high; this.prevLow = low; this.prevClose = close;

    if (this.count < this.period) {
      this.trS += tr; this.dmpS += dmp; this.dmmS += dmm; this.count++;
      if (this.count === this.period) { this.trR = this.trS; this.dmpR = this.dmpS; this.dmmR = this.dmmS; }
      return;
    }
    var p = this.period;
    this.trR = this.trR - this.trR / p + tr;
    this.dmpR = this.dmpR - this.dmpR / p + dmp;
    this.dmmR = this.dmmR - this.dmmR / p + dmm;

    var diP = 100 * divSafe(this.dmpR, this.trR, 0);
    var diM = 100 * divSafe(this.dmmR, this.trR, 0);
    var dx = 100 * divSafe(abs(diP - diM), diP + diM, 0);

    this.adxCount++;
    if (this.adxCount <= p) {
      this.adxSeedSum += dx;
      if (this.adxCount === p) this.adx = this.adxSeedSum / p;
    } else {
      this.adx = (this.adx * (p - 1) + dx) / p;
    }
  };
  ADX.prototype.ready = function () { return this.adxCount >= this.period; };
  ADX.prototype.val = function () { return this.ready() ? this.adx : 0; };

  //--- volume truth engine (VpVolume.mqh) ---------------------------
  var VOL = { TICK: 0, REAL: 1, BVC: 2, RANGE: 3, BODY: 4, UNIFORM: 5, INVRANGE: 6, AUTO: 7 };

  function VolumeProbe() { this.reset(); }
  VolumeProbe.prototype.reset = function () {
    this.tickUsable = true; this.realUsable = false; this.tickConstant = false;
    this.samples = 0; this.tickMean = 0; this.tickMin = 0; this.tickMax = 0;
    this.realMean = 0; this.lastTick = 0;
  };
  VolumeProbe.prototype.push = function (tickVol, realVol) {
    var tickOk = isFinite2(tickVol) && tickVol > 0;
    var realOk = isFinite2(realVol) && realVol > 0;
    if (!tickOk) this.tickUsable = false;
    if (realOk) this.realUsable = true;
    if (tickOk) {
      if (this.samples === 0) { this.tickMin = tickVol; this.tickMax = tickVol; }
      if (tickVol < this.tickMin) this.tickMin = tickVol;
      if (tickVol > this.tickMax) this.tickMax = tickVol;
      this.tickMean = (this.tickMean * this.samples + tickVol) / (this.samples + 1);
      this.lastTick = tickVol;
      this.samples++;
    }
    if (realOk) this.realMean = this.realMean * 0.98 + realVol * 0.02;
    if (this.samples >= 64 && this.tickMax === this.tickMin) this.tickConstant = true;
  };

  function buyFraction(o, h, l, c, k) {
    var range = h - l;
    if (!(range > 0)) return 0.5;
    var pos = (c - l) / range;
    if (pos < 0) pos = 0;
    if (pos > 1) pos = 1;
    var f = 0.5 + 0.5 * k * (2 * pos - 1);
    if (f < 0.02) f = 0.02;
    if (f > 0.98) f = 0.98;
    return f;
  }

  function barWeight(mode, o, h, l, c, tickVol, realVol, rangeScale, tickUsable, tickConstant, realUsable) {
    var range = h - l;
    if (range < 0) range = -range;
    if (!(rangeScale > 0)) rangeScale = 1;
    var v = 0, haveV = false;
    switch (mode) {
      case VOL.REAL:
        if (realUsable && isFinite2(realVol) && realVol > 0) { v = realVol; haveV = true; }
        break;
      case VOL.BVC:
        if (realUsable && isFinite2(realVol) && realVol > 0) { v = realVol; haveV = true; }
        else if (tickUsable && !tickConstant && isFinite2(tickVol) && tickVol > 0) { v = tickVol; haveV = true; }
        else if (range > 0) { v = range; haveV = true; }
        break;
      case VOL.TICK:
        if (tickUsable && !tickConstant && isFinite2(tickVol) && tickVol > 0) { v = tickVol; haveV = true; }
        break;
      case VOL.RANGE:
        if (range > 0) { v = range; haveV = true; }
        break;
      case VOL.BODY:
        if (abs(c - o) > 0) { v = abs(c - o); haveV = true; }
        break;
      case VOL.UNIFORM:
        v = 1; haveV = true;
        break;
      case VOL.INVRANGE:
        if (tickUsable && !tickConstant && isFinite2(tickVol) && tickVol > 0 && range > 0) {
          var rs = range / rangeScale;
          v = tickVol / (rs * rs); haveV = true;
        }
        break;
      default: // AUTO
        if (realUsable && isFinite2(realVol) && realVol > 0) { v = realVol; haveV = true; }
        else if (tickUsable && !tickConstant && isFinite2(tickVol) && tickVol > 0) { v = tickVol; haveV = true; }
        else if (range > 0) { v = range; haveV = true; }
        break;
    }
    if (!haveV || !(v > 0)) v = 1e-6;
    return v;
  }

  function effectivePrice(o, h, l, c, buyFrac) {
    var typical = (h + l + c) / 3;
    if (!(h > l)) return typical;
    var pBuy = (h + c) * 0.5, pSell = (l + c) * 0.5;
    var vwapProxy = pBuy * buyFrac + pSell * (1 - buyFrac);
    return 0.6 * vwapProxy + 0.4 * typical;
  }

  //--- anchoring (VpAnchor.mqh) ------------------------------------
  var ANCHOR = { SESSION: 0, SERVERDAY: 1, UTCDAY: 2, FIXED: 3, WEEK: 4 };
  var SECS_DAY = 86400;

  function weekStartDay(dayIndex, weekStart) {
    var delta = floorMod(dayIndex + 4 - weekStart, 7);
    return dayIndex - delta;
  }

  function anchorKey(cfg, serverTime) {
    var t = serverTime + cfg.anchorShiftSec;
    switch (cfg.anchorMode) {
      case ANCHOR.SESSION: return t;
      case ANCHOR.SERVERDAY: return floorDiv(t, SECS_DAY);
      case ANCHOR.UTCDAY: {
        var utc = t - round(cfg.tzOffsetHours * 3600);
        return floorDiv(utc, SECS_DAY);
      }
      case ANCHOR.WEEK: return weekStartDay(floorDiv(t, SECS_DAY), cfg.weekStartDay);
      default: {
        var dayIdx = floorDiv(t, SECS_DAY);
        var secOfDay = floorMod(t, SECS_DAY);
        var aSec = cfg.anchorHour * 3600 + cfg.anchorMinute * 60;
        if (secOfDay >= aSec) return dayIdx * SECS_DAY + aSec;
        return (dayIdx - 1) * SECS_DAY + aSec;
      }
    }
  }

  //--- configuration -----------------------------------------------
  function defaultConfig() {
    return {
      anchorMode: ANCHOR.SERVERDAY, anchorHour: 0, anchorMinute: 0, anchorShiftSec: 0,
      weekStartDay: 1, tzOffsetHours: 0,
      volumeMode: VOL.AUTO, bvcK: 1,
      sigmaMode: 0, zWindow: 0, adaptSigma: true, adaptPriorBars: 40,
      atrPeriod: 14, adxPeriod: 14,
      bandMode: 0, mult1: 1, mult2: 2, mult3: 3,
      adaptiveSignal: true, minBars: 3
    };
  }

  //--- the engine ----------------------------------------------------
  function Engine(cfgIn) {
    this.cfg = Object.assign(defaultConfig(), cfgIn || {});
    this.reset();
  }

  Engine.prototype.reset = function () {
    var cfg = this.cfg;
    var ap = (cfg.atrPeriod >= 1 && cfg.atrPeriod <= 1000) ? cfg.atrPeriod : 14;
    var xp = (cfg.adxPeriod >= 2 && cfg.adxPeriod <= 1000) ? cfg.adxPeriod : 14;
    var zw = (cfg.zWindow >= 0 && cfg.zWindow <= 4096) ? cfg.zWindow : 0;

    this.vol = new VolumeProbe();
    this.started = false; this.anchorKey = 0; this.anchorTime = 0;
    this.barIndex = -1; this.barsInAnchor = 0;
    this.origin = 0;
    this.sw = new KSum(); this.swd = new KSum(); this.swd2 = new KSum();
    this.swd3 = new KSum(); this.swd4 = new KSum();
    this.swBuy = new KSum(); this.swSell = new KSum();
    this.sx = new KSum(); this.sy = new KSum(); this.sxx = new KSum(); this.sxy = new KSum();
    this.su1 = new KSum(); this.su2 = new KSum();
    this.atr = new ATR(); this.atr.reset(ap);
    this.adx = new ADX(); this.adx.reset(xp);
    this.retMom = new Moments();
    this.prevClose = 0; this.havePrevClose = false; this.rangeEwma = 0;
    this.lastOpen = this.lastHigh = this.lastLow = this.lastClose = 0;
    this.lastTickVol = this.lastRealVol = 0;
    this.lastWeight = 0; this.lastBuyFrac = 0.5; this.lastEffPrice = 0;
    this.ringCap = zw; this.ringCount = 0; this.ringHead = 0;
    this.ringPrice = []; this.ringWeight = [];
    this.vwap = this.sigma = this.sigmaObs = this.sigmaPrior = 0;
    this.z = this.slopePct = this.slopeSigma = 0;
    this.deltaTilt = this.r2 = this.signal = this.skew = this.kurt = 0;
    this.up1 = this.dn1 = this.up2 = this.dn2 = this.up3 = this.dn3 = 0;
    this.sigmaRatio = 1; this.tStat = 0; this.ready = false;
    this.feedWarnings = 0;
  };

  Engine.prototype.vwap_ = function () {
    var W = this.sw.val();
    if (!(W > 0)) return 0;
    return this.origin + this.swd.val() / W;
  };

  Engine.prototype.variance = function () {
    var W = this.sw.val();
    if (!(W > 0) || this.barsInAnchor < 2) return 0;
    var mean = this.swd.val() / W;
    var v = this.swd2.val() / W - mean * mean;
    return v < 0 ? 0 : v;
  };

  Engine.prototype.varUnweighted = function () {
    if (this.barsInAnchor < 2) return 0;
    var n = this.barsInAnchor;
    var U1 = this.su1.val();
    var v = this.su2.val() - U1 * U1 / n;
    return (v < 0 ? 0 : v) / n;
  };

  Engine.prototype.shape = function () {
    var skewOut = 0, kurtOut = 0;
    var W = this.sw.val();
    if (W > 0 && this.barsInAnchor >= 6) {
      var S1 = this.swd.val() / W, S2 = this.swd2.val() / W;
      var S3 = this.swd3.val() / W, S4 = this.swd4.val() / W;
      var m2 = S2 - S1 * S1;
      if (m2 > 0) {
        var m3 = S3 - 3 * S1 * S2 + 2 * S1 * S1 * S1;
        var m4 = S4 - 4 * S1 * S3 + 6 * S1 * S1 * S2 - 3 * S1 * S1 * S1 * S1;
        var s = sqrt(m2);
        skewOut = divSafe(m3, s * s * s, 0);
        kurtOut = divSafe(m4, m2 * m2, 0) - 3;
        if (!isFinite2(skewOut)) skewOut = 0;
        if (!isFinite2(kurtOut)) kurtOut = 0;
      }
    }
    return { skew: skewOut, kurt: kurtOut };
  };

  Engine.prototype.reorigin = function (newOrigin) {
    var dl = newOrigin - this.origin;
    if (dl === 0) return;
    var W = this.sw.val(), S1 = this.swd.val(), S2 = this.swd2.val();
    var S3 = this.swd3.val(), S4 = this.swd4.val();
    var nS1 = S1 - dl * W;
    var nS2 = S2 - 2 * dl * S1 + dl * dl * W;
    var nS3 = S3 - 3 * dl * S2 + 3 * dl * dl * S1 - dl * dl * dl * W;
    var nS4 = S4 - 4 * dl * S3 + 6 * dl * dl * S2 - 4 * dl * dl * dl * S1 + dl * dl * dl * dl * W;
    this.swd.reset(); this.swd.add(nS1);
    this.swd2.reset(); this.swd2.add(nS2);
    this.swd3.reset(); this.swd3.add(nS3);
    this.swd4.reset(); this.swd4.add(nS4);
    var U1 = this.su1.val(), U2 = this.su2.val(), n = this.barsInAnchor;
    this.su1.reset(); this.su1.add(U1 - dl * n);
    this.su2.reset(); this.su2.add(U2 - 2 * dl * U1 + dl * dl * n);
    this.origin = newOrigin;
  };

  Engine.prototype.beginAnchor = function (key, time, openPrice) {
    this.anchorKey = key; this.anchorTime = time;
    this.barIndex = -1; this.barsInAnchor = 0;
    this.origin = openPrice;
    this.sw.reset(); this.swd.reset(); this.swd2.reset(); this.swd3.reset(); this.swd4.reset();
    this.swBuy.reset(); this.swSell.reset();
    this.sx.reset(); this.sy.reset(); this.sxx.reset(); this.sxy.reset();
    this.su1.reset(); this.su2.reset();
    this.ringCount = 0; this.ringHead = 0;
    this.started = true; this.ready = false;
    this.vwap = openPrice; this.sigma = 0; this.z = 0;
    this.slopePct = 0; this.slopeSigma = 0; this.deltaTilt = 0; this.r2 = 0;
    this.skew = 0; this.kurt = 0; this.signal = 0;
    this.up1 = openPrice; this.dn1 = openPrice;
    this.up2 = openPrice; this.dn2 = openPrice;
    this.up3 = openPrice; this.dn3 = openPrice;
  };

  Engine.prototype.ringPush = function (price, weight) {
    if (this.ringCap <= 0) return;
    if (this.ringCount < this.ringCap) {
      this.ringPrice[this.ringCount] = price;
      this.ringWeight[this.ringCount] = weight;
      this.ringCount++;
    } else {
      this.ringPrice[this.ringHead] = price;
      this.ringWeight[this.ringHead] = weight;
      this.ringHead = (this.ringHead + 1) % this.ringCap;
    }
  };

  Engine.prototype.ringVariance = function () {
    var out = { var_: 0, mean: 0, n: 0 };
    if (this.ringCount < 2) return out;
    var W = 0, S = 0, i;
    for (i = 0; i < this.ringCount; i++) { W += this.ringWeight[i]; S += this.ringWeight[i] * this.ringPrice[i]; }
    if (!(W > 0)) return out;
    var mean = S / W, V = 0;
    for (i = 0; i < this.ringCount; i++) { var d = this.ringPrice[i] - mean; V += this.ringWeight[i] * d * d; }
    out.var_ = divSafe(V, W, 0); out.mean = mean; out.n = this.ringCount;
    return out;
  };

  function barUsable(o, h, l, c) {
    if (!isFinite2(o) || !isFinite2(h) || !isFinite2(l) || !isFinite2(c)) return false;
    if (!(o > 0) || !(c > 0)) return false;
    if (!(h >= l)) return false;
    if (!(h > 0)) return false;
    if (h - l > c) return false;
    return true;
  }

  Engine.prototype.pushBar = function (anchor, barTime, b) {
    if (!barUsable(b.open, b.high, b.low, b.close)) { this.feedWarnings++; return; }
    if (!this.started || anchor !== this.anchorKey) this.beginAnchor(anchor, barTime, b.open);

    this.barIndex++;
    this.lastOpen = b.open; this.lastHigh = b.high; this.lastLow = b.low; this.lastClose = b.close;
    this.lastTickVol = b.tickVol; this.lastRealVol = b.realVol;

    this.vol.push(b.tickVol, b.realVol);

    var cfg = this.cfg;
    var buyFrac = buyFraction(b.open, b.high, b.low, b.close, cfg.bvcK);
    var w = barWeight(cfg.volumeMode, b.open, b.high, b.low, b.close, b.tickVol, b.realVol,
      this.rangeEwma, this.vol.tickUsable, this.vol.tickConstant, this.vol.realUsable);

    var p;
    if (cfg.volumeMode === VOL.BVC || cfg.volumeMode === VOL.INVRANGE)
      p = effectivePrice(b.open, b.high, b.low, b.close, buyFrac);
    else
      p = (b.high + b.low + b.close) / 3;
    if (!isFinite2(p) || p <= 0) p = b.close;
    if (!isFinite2(p) || p <= 0) { this.feedWarnings++; return; }

    var d = p - this.origin;
    if (!isFinite2(d) || abs(d) > 1e150) { this.feedWarnings++; return; }

    var tr1 = b.high - b.low;
    var tr2 = this.havePrevClose ? abs(b.high - this.prevClose) : tr1;
    var tr3 = this.havePrevClose ? abs(b.low - this.prevClose) : tr1;
    var tr = max(tr1, max(tr2, tr3));
    this.atr.push(tr);
    this.adx.push(b.high, b.low, b.close);
    if (this.havePrevClose && this.prevClose > 0 && b.close > 0) {
      var r = log(b.close / this.prevClose);
      if (isFinite2(r)) this.retMom.push(r);
    }
    this.prevClose = b.close; this.havePrevClose = true;

    var range = abs(b.high - b.low);
    this.rangeEwma = (this.rangeEwma <= 0) ? range : (this.rangeEwma * 0.98 + range * 0.02);

    this.lastWeight = w; this.lastBuyFrac = buyFrac; this.lastEffPrice = p;

    var d2 = d * d;
    this.sw.add(w);
    this.swd.add(w * d);
    this.swd2.add(w * d2);
    this.swd3.add(w * d2 * d);
    this.swd4.add(w * d2 * d2);
    this.swBuy.add(w * buyFrac);
    this.swSell.add(w * (1 - buyFrac));

    var x = this.barIndex;
    this.sx.add(x); this.sy.add(p); this.sxx.add(x * x); this.sxy.add(x * p);
    this.su1.add(d); this.su2.add(d2);

    this.barsInAnchor++;
    this.ringPush(p, w);
    if (this.barsInAnchor > 0 && this.barsInAnchor % 128 === 0) this.reorigin(this.vwap_());
  };

  function cornishFisher(zNorm, skew, exKurt) {
    var z = zNorm, z2 = z * z, z3 = z2 * z;
    var g1 = clamp(skew, -3, 3), g2 = clamp(exKurt, -2, 25);
    var x = z + (z2 - 1) * g1 / 6 + (z3 - 3 * z) * g2 / 24 - (2 * z3 - 5 * z) * g1 * g1 / 36;
    var a = z * 0.5, b = z * 2;
    var lo = min(a, b), hi = max(a, b);
    if (x < lo) x = lo;
    if (x > hi) x = hi;
    return x;
  }

  Engine.prototype.compositeSignal = function () {
    var cfg = this.cfg;
    if (this.barsInAnchor < imax(1, cfg.minBars)) return 0;
    var trendness = 0;
    if (cfg.adaptiveSignal) {
      var adxN = clamp((this.adx.val() - 15) / 25, 0, 1);
      var conf = clamp(this.r2 * 3, 0, 1);
      trendness = clamp(0.6 * adxN + 0.4 * conf, 0, 1);
    }
    var fade = -tanh(this.z / 1.6);
    var trend = tanh(this.tStat / 6);
    var flow = tanh(this.deltaTilt * 2.5);
    var sig;
    if (cfg.adaptiveSignal) sig = 0.85 * ((1 - trendness) * fade + trendness * trend) + 0.15 * flow;
    else sig = 0.60 * fade + 0.25 * trend + 0.15 * flow;
    return clamp(sig, -1, 1);
  };

  Engine.prototype.evaluate = function () {
    var cfg = this.cfg;
    this.ready = false;

    var W = this.sw.val();
    if (!(W > 0) || this.barsInAnchor < 1) {
      this.vwap = this.lastClose;
      this.sigma = this.sigmaObs = this.sigmaPrior = 0;
      this.z = this.slopePct = this.slopeSigma = 0;
      this.deltaTilt = this.r2 = this.signal = this.skew = this.kurt = 0;
      this.up1 = this.dn1 = this.lastClose;
      this.up2 = this.dn2 = this.lastClose;
      this.up3 = this.dn3 = this.lastClose;
      return;
    }

    this.vwap = this.vwap_();
    var varObs = this.variance();
    this.sigmaObs = sqrt(varObs);

    var T = imax(1, this.barsInAnchor);
    var sBar = 0;
    if (this.atr.ready()) sBar = this.atr.val() * 0.5;
    else if (this.retMom.n >= 2) sBar = this.retMom.stdDev() * this.vwap;
    var sigmaPrior = sBar * sqrt(T / 3);
    if (!isFinite2(sigmaPrior) || sigmaPrior < 0) sigmaPrior = 0;
    this.sigmaPrior = sigmaPrior;

    this.sigma = this.sigmaObs;
    var vWin = 0, nWin = 0;
    if (cfg.sigmaMode !== 0) {
      var rv = this.ringVariance();
      vWin = rv.var_; nWin = rv.n;
    }
    if (cfg.sigmaMode === 1) {
      if (nWin >= 2) this.sigma = sqrt(vWin);
    } else if (cfg.sigmaMode === 2) {
      if (nWin >= 2) this.sigma = sqrt(vWin * 0.5 + varObs * 0.5);
    }

    if (cfg.adaptSigma && sigmaPrior > 0) {
      var nPrior = imax(0, cfg.adaptPriorBars);
      var nObs = imax(1, this.barsInAnchor);
      var wPrior = nPrior / (nObs + nPrior);
      var sigmaShrunk = sqrt(varObs * (1 - wPrior) + sigmaPrior * sigmaPrior * wPrior);
      if (cfg.sigmaMode === 0) this.sigma = sigmaShrunk;
      else if (nWin < 5) this.sigma = sigmaShrunk;
    }
    this.sigmaRatio = divSafe(this.sigma, this.sigmaPrior, 1);

    var dx = this.lastClose - this.vwap;
    this.z = divSafe(dx, this.sigma, 0);
    if (!isFinite2(this.z)) this.z = 0;
    if (this.z > 99) this.z = 99;
    if (this.z < -99) this.z = -99;

    //--- OLS slope (VpOLS::Solve) -----------------------------------
    var dn = this.barsInAnchor;
    var olsOk = false, slope = 0;
    if (dn >= 2) {
      var xx = this.sxx.val() - this.sx.val() * this.sx.val() / dn;
      var xy = this.sxy.val() - this.sx.val() * this.sy.val() / dn;
      if (abs(xx) > 1e-18) { slope = xy / xx; olsOk = isFinite2(slope); }
    }
    if (olsOk) {
      this.slopePct = divSafe(slope * 100, this.vwap, 0);
      this.slopeSigma = divSafe(slope, this.sigma, 0);
    } else { this.slopePct = 0; this.slopeSigma = 0; }

    var Sxx = this.sxx.val() - this.sx.val() * this.sx.val() / dn;
    var Sxy = this.sxy.val() - this.sx.val() * this.sy.val() / dn;
    var Syy = this.varUnweighted() * dn;
    this.tStat = 0;
    if (Sxx > 0 && Syy > 0) {
      var rr = Sxy * Sxy / (Sxx * Syy);
      if (rr > 1) rr = 1;
      if (rr < 0) rr = 0;
      this.r2 = rr;

      var sse = Syy - (Sxx > 0 ? Sxy * Sxy / Sxx : 0);
      if (sse < 0) sse = 0;
      var dof = dn > 2 ? dn - 2 : 1;
      var mse = sse / dof;
      var slope2 = divSafe(Sxy, Sxx, 0);
      if (mse > 0) {
        var se = sqrt(mse / Sxx);
        this.tStat = divSafe(slope2, se, 0);
      } else {
        this.tStat = slope2 > 0 ? 1e6 : (slope2 < 0 ? -1e6 : 0);
      }
      if (!isFinite2(this.tStat)) this.tStat = 0;
    } else this.r2 = 0;

    var buy = this.swBuy.val(), sell = this.swSell.val();
    this.deltaTilt = divSafe(buy - sell, buy + sell, 0);
    if (!isFinite2(this.deltaTilt)) this.deltaTilt = 0;

    var sh = this.shape();
    this.skew = sh.skew; this.kurt = sh.kurt;

    var m1u = cfg.mult1, m2u = cfg.mult2, m3u = cfg.mult3;
    var m1d = cfg.mult1, m2d = cfg.mult2, m3d = cfg.mult3;
    if (cfg.bandMode === 1) {
      m1u = cornishFisher(cfg.mult1, this.skew, this.kurt);
      m1d = -cornishFisher(-cfg.mult1, this.skew, this.kurt);
      m2u = cornishFisher(cfg.mult2, this.skew, this.kurt);
      m2d = -cornishFisher(-cfg.mult2, this.skew, this.kurt);
      m3u = cornishFisher(cfg.mult3, this.skew, this.kurt);
      m3d = -cornishFisher(-cfg.mult3, this.skew, this.kurt);
    }
    var sd = this.sigma;
    this.up1 = this.vwap + m1u * sd; this.dn1 = this.vwap - m1d * sd;
    this.up2 = this.vwap + m2u * sd; this.dn2 = this.vwap - m2d * sd;
    this.up3 = this.vwap + m3u * sd; this.dn3 = this.vwap - m3d * sd;

    this.ready = this.barsInAnchor >= imax(1, cfg.minBars);
    this.signal = this.compositeSignal();

    //--- last line of defence ---------------------------------------
    var cap = this.vwap > 0 ? this.vwap : 0;
    if (!isFinite2(this.vwap) || this.vwap <= 0) this.vwap = this.lastClose;
    if (!isFinite2(this.sigma) || this.sigma < 0) this.sigma = 0;
    if (cap > 0 && this.sigma > cap) this.sigma = cap;
    if (!isFinite2(this.z)) this.z = 0;
    if (!isFinite2(this.signal)) this.signal = 0;
    if (!isFinite2(this.deltaTilt)) this.deltaTilt = 0;
    if (!isFinite2(this.r2)) this.r2 = 0;
    if (!isFinite2(this.skew)) this.skew = 0;
    if (!isFinite2(this.kurt)) this.kurt = 0;
    if (!isFinite2(this.tStat)) this.tStat = 0;
    if (!isFinite2(this.up1)) this.up1 = this.vwap;
    if (!isFinite2(this.dn1)) this.dn1 = this.vwap;
    if (!isFinite2(this.up2)) this.up2 = this.vwap;
    if (!isFinite2(this.dn2)) this.dn2 = this.vwap;
    if (!isFinite2(this.up3)) this.up3 = this.vwap;
    if (!isFinite2(this.dn3)) this.dn3 = this.vwap;
    if (this.dn1 > this.vwap) this.dn1 = this.vwap;
    if (this.up1 < this.vwap) this.up1 = this.vwap;
    if (this.dn2 > this.dn1) this.dn2 = this.dn1;
    if (this.up2 < this.up1) this.up2 = this.up1;
    if (this.dn3 > this.dn2) this.dn3 = this.dn2;
    if (this.up3 < this.up2) this.up3 = this.up2;
  };

  //| Feed one closed bar (anchor key computed for you).
  Engine.prototype.push = function (bar) {
    this.pushBar(anchorKey(this.cfg, bar.time), bar.time, bar);
  };

  //| Evaluate a *forming* bar without committing it: exactly what the
  //| indicator does on every tick, and the reason it cannot repaint.
  Engine.prototype.preview = function (bar) {
    var clone = cloneEngine(this);
    clone.pushBar(anchorKey(clone.cfg, bar.time), bar.time, bar);
    clone.evaluate();
    return clone;
  };

  function cloneEngine(src) {
    var dst = new Engine(src.cfg);
    dst.vol = Object.assign(Object.create(VolumeProbe.prototype), src.vol);
    dst.started = src.started; dst.anchorKey = src.anchorKey; dst.anchorTime = src.anchorTime;
    dst.barIndex = src.barIndex; dst.barsInAnchor = src.barsInAnchor;
    dst.origin = src.origin;
    dst.sw = Object.assign(new KSum(), src.sw); dst.swd = Object.assign(new KSum(), src.swd);
    dst.swd2 = Object.assign(new KSum(), src.swd2); dst.swd3 = Object.assign(new KSum(), src.swd3);
    dst.swd4 = Object.assign(new KSum(), src.swd4);
    dst.swBuy = Object.assign(new KSum(), src.swBuy); dst.swSell = Object.assign(new KSum(), src.swSell);
    dst.sx = Object.assign(new KSum(), src.sx); dst.sy = Object.assign(new KSum(), src.sy);
    dst.sxx = Object.assign(new KSum(), src.sxx); dst.sxy = Object.assign(new KSum(), src.sxy);
    dst.su1 = Object.assign(new KSum(), src.su1); dst.su2 = Object.assign(new KSum(), src.su2);
    dst.atr = Object.assign(new ATR(), src.atr);
    dst.adx = Object.assign(new ADX(), src.adx);
    dst.retMom = Object.assign(new Moments(), src.retMom);
    dst.prevClose = src.prevClose; dst.havePrevClose = src.havePrevClose; dst.rangeEwma = src.rangeEwma;
    dst.lastOpen = src.lastOpen; dst.lastHigh = src.lastHigh;
    dst.lastLow = src.lastLow; dst.lastClose = src.lastClose;
    dst.lastTickVol = src.lastTickVol; dst.lastRealVol = src.lastRealVol;
    dst.lastWeight = src.lastWeight; dst.lastBuyFrac = src.lastBuyFrac; dst.lastEffPrice = src.lastEffPrice;
    dst.feedWarnings = src.feedWarnings;
    dst.ringCap = src.ringCap; dst.ringCount = src.ringCount; dst.ringHead = src.ringHead;
    dst.ringPrice = src.ringPrice.slice(0, src.ringCount);
    dst.ringWeight = src.ringWeight.slice(0, src.ringCount);
    dst.vwap = src.vwap; dst.sigma = src.sigma;
    dst.sigmaObs = src.sigmaObs; dst.sigmaPrior = src.sigmaPrior;
    dst.z = src.z; dst.slopePct = src.slopePct; dst.slopeSigma = src.slopeSigma;
    dst.deltaTilt = src.deltaTilt; dst.r2 = src.r2; dst.skew = src.skew; dst.kurt = src.kurt;
    dst.signal = src.signal;
    dst.up1 = src.up1; dst.dn1 = src.dn1; dst.up2 = src.up2; dst.dn2 = src.dn2;
    dst.up3 = src.up3; dst.dn3 = src.dn3;
    dst.sigmaRatio = src.sigmaRatio; dst.tStat = src.tStat; dst.ready = src.ready;
    return dst;
  }

  return {
    Engine: Engine,
    defaultConfig: defaultConfig,
    anchorKey: anchorKey,
    weekStartDay: weekStartDay,
    buyFraction: buyFraction,
    barWeight: barWeight,
    effectivePrice: effectivePrice,
    barUsable: barUsable,
    cornishFisher: cornishFisher,
    tanh: tanh,
    VOL: VOL,
    ANCHOR: ANCHOR,
    cloneEngine: cloneEngine
  };
});

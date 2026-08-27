# TA+FA Confluence — مؤشر MT4 (فني + أساسي)

مؤشر MetaTrader 4 كيجمع **تحليل فني كلاسيكي** مع **تحليل أساسي حقيقي**.  
ماكاينش SMC، ماكاينش ICT، ماكاينش order blocks، FVG، BOS، CHoCH، ولا "liquidity grab".

هادشي مبني على أدوات كيستعملها المتداولين من عشرات السنين، وماشي نظام سحري. الأسهم كيبانو غير ملي الفني والأساسي **متافقين**، على **شمعة مسكورة** (ما كيعاودش يرسم / no repaint).

---

## شنو كاين فالصندوق

| ملف | فين تحطو |
|---|---|
| `MQL4/Indicators/TA_FA_Confluence.mq4` | `[Data Folder]/MQL4/Indicators/` |
| `MQL4/Files/economic_calendar.csv` | `[Data Folder]/MQL4/Files/` |

فـ MT4: **File → Open Data Folder**.

1. نسخ الملفات.
2. فـ Navigator: دير كليك يمين على Indicators → **Refresh**.
3. حل المؤشر فـ MetaEditor (`F4`) → **Compile**.
4. جرّو على الشارت (H1 أو H4 أحسن بداية).
5. فـ Market Watch زيد الأزواج الرئيسية كاملين (EURUSD, GBPUSD, USDJPY, … والـ crosses). قوة العملة كتحتاجهم. المؤشر كيحاول يختارهم أوتوماتيكياً.

---

## كيفاش كيحسب

كل تيك كيعطي ثلاث نقاط من **-100** حتى **+100**:

- **TA** — فني
- **FA** — أساسي
- **SUM** — متوسط موزون (افتراضي 55% فني / 45% أساسي)

### التحليل الفني (كلاسيكي)

- محاذاة **EMA 21 / 50 / 200** وميل الـ 50
- **MACD** (فوق/تحت الصفر + اتجاه الهيستوغرام)
- **RSI(14)** و **Stochastic** — الزخم، مع تخفيف فالأطراف (ما كيشتريش RSI 80)
- **ADX +DI/-DI** — إلا ADX ضعيف = سوق مقطوع، ما كايناش أسهم
- تأكيد **H4 و D1** (الاتجاه ديال EMA)
- دايفيرجينس RSI بسيط على swing highs/lows (اختياري)
- **Daily floor pivots** (PP, R1–R3, S1–S3) — مستويات أرضية كلاسيكية، ماشي ICT

### التحليل الأساسي (حقيقي، ماشي قصة)

MT4 ماعندوش تقويم اقتصادي مدمج. لذلك الأساسي هنا مبني على حوايج قابلة للقياس:

1. **فارق أسعار الفائدة (carry / policy rate)**  
   USD 3.75% · EUR 2.15% · GBP 3.75% · JPY 1.00% · CHF 0.00% · AUD 4.35% · CAD 2.25% · NZD 2.25%  
   (تقريباً غشت 2026 — **بدّلهم من Inputs من بعد كل اجتماع بنك مركزي**).  
   هادشي **انحياز بطيء**، ماشي إشارة دخول. الوزن قابل للتعديل (`InpCarryWeight`).

2. **قوة العملة (currency strength)**  
   معدل التغير على 28 زوج رئيسي (H1، 14 شمعة). السوق كيسعّر الأساسي قبل ما يبان فالأخبار. إلا EUR قوية و USD ضعيفة، EURUSD كياخد دعم أساسي.

3. **Intermarket** (تحليل جون مورفي)  
   - أزواج الدولار ↔ مؤشر الدولار DXY إلا كان عند البروكر  
   - CAD ↔ النفط  
   - AUD ↔ الذهب  
   - الذهب ↔ عكس الدولار

4. **الجلسة**  
   الأسهم غير فـ لندن / نيويورك (وطوكيو لأزواج الين/الأود). السيولة الرقيقة كتكذب.

5. **أخبار high-impact**  
   نافذة صمت ±30 دقيقة. كيقرا `economic_calendar.csv` + NFP أوتوماتيك (أول جمعة فالشهر). تقدر تزيد خبر يدوي من Inputs: `InpNextNewsTime`.

---

## شنو خاص باش تطلع سهم (BUY أو SELL)

كل هاد الشروط **دابا**، على الشمعة **اللي تسكرات**:

1. TA و FA فنفس الاتجاه
2. `|TA| ≥ 55` و `|FA| ≥ 40` و `|SUM| ≥ 55`
3. ADX ≥ 18 (ماشي chop)
4. H4 و D1 متافقين مع الاتجاه
5. ما كايناش نافذة أخبار
6. جلسة فيها سيولة
7. RSI ماشي مشدود (ما كيشريش فوق 78، ما كيبيعش تحت 22)

اللوحة كتعرض النقط **الحية** (الشمعة الحالية). السهم كيتأكد غير من بعد الإغلاق. هادشي مقصود باش ما يكرّرش الرسم.

---

## Inputs اللي خاصك تلمس

| Input | علاش |
|---|---|
| `InpRateUSD` … `InpRateNZD` | حدّثهم من بعد FOMC / ECB / BoE / BoJ |
| `InpBrokerGMTOffset` | ساعات: توقيت البروكر ناقص GMT |
| `InpNextNewsTime` | الخبر الجاي إلا ما بغيتيش CSV: `2026.08.28 12:30` |
| `InpCalendarFile` | اسم الملف فـ `MQL4/Files/` |
| `InpTAMin` / `InpFAMin` | صعّب أو سهّل الأسهم |
| `InpSessionFilter` | `false` إلا بغيتي أسهم فآسيا على EURUSD |
| `InpDollarIndex` | رموز DXY عند البروكر ديالك (`USDX,DXY,DX`) |

---

## كيفاش تخدمو بصح (ماشي holygrail)

- إطار زمني: **H1 أو H4**. M1/M5 غادي يعطيك ضوضاء.
- السهم = **فلتر التقاء**، ماشي أمر تنفيذ أعمى. شوف البنية الكلاسيكية (higher high / lower low) والمستوى (pivot / EMA 50).
- SL تقريبي: **1.5 ATR**. TP: **2R** (مكتوبين فاللوحة كاقتراح).
- نهار NFP / FOMC: وقف. النافذة ±30 دقيقة حد أدنى — التقلب كيبقى ساعات ساعات.
- إلا اللوحة كتبّات `pairs in Market Watch: 8/28` قوة العملة ناقصة. زيد الأزواج.
- ما كاينش martingale، ما كاينش grid، ما كاينش "smart money".

---

## English summary

Classic technical score (EMA stack, MACD, RSI, Stochastic, ADX, H4/D1) plus a fundamental score from **policy-rate differential**, **28-pair currency strength**, **intermarket confirmation**, **session quality**, and a **high-impact news blackout**. Signals fire only on a **closed bar** when TA and FA agree. No SMC/ICT. Update the eight policy rates after each central-bank meeting. This is confluence, not a holy grail.

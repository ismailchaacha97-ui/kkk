const BROKERS = [
  { id: "ic", name: "IC Markets / Pepperstone / FTMO (EET)", offset: 2, dst: "eet" },
  { id: "xm", name: "XM / Exness Standard (EET)", offset: 2, dst: "eet" },
  { id: "eet3", name: "Typical MT4 book GMT+3 summer", offset: 3, dst: "eet" },
  { id: "gmt", name: "GMT / UTC book (no DST)", offset: 0, dst: "off" },
  { id: "gmt2fix", name: "Fixed GMT+2 (no DST)", offset: 2, dst: "off" },
  { id: "gmt3fix", name: "Fixed GMT+3 (no DST)", offset: 3, dst: "off" },
  { id: "est", name: "US book EST/EDT", offset: -5, dst: "est" },
  { id: "cst", name: "US book CST/CDT", offset: -6, dst: "est" },
];

const $ = (id) => document.getElementById(id);

function pad(n) {
  return String(n).padStart(2, "0");
}

function lastSunday(year, monthIndex) {
  const d = new Date(Date.UTC(year, monthIndex + 1, 0));
  d.setUTCDate(d.getUTCDate() - d.getUTCDay());
  return d;
}

function nthSunday(year, monthIndex, n) {
  const d = new Date(Date.UTC(year, monthIndex, 1));
  const add = d.getUTCDay() === 0 ? 0 : 7 - d.getUTCDay();
  d.setUTCDate(1 + add + (n - 1) * 7);
  return d;
}

function isEUDST(date) {
  const y = date.getUTCFullYear();
  const start = lastSunday(y, 2);
  const end = lastSunday(y, 9);
  const t = date.getTime();
  return t >= start.getTime() && t < end.getTime();
}

function isUSDST(date) {
  const y = date.getUTCFullYear();
  const start = nthSunday(y, 2, 2);
  const end = nthSunday(y, 10, 1);
  const t = date.getTime();
  return t >= start.getTime() && t < end.getTime();
}

function parseHHMM(value) {
  const [h, m] = value.split(":").map((x) => parseInt(x, 10));
  return { h: h || 0, m: m || 0 };
}

function formatHHMM(h, m) {
  let hh = h;
  while (hh < 0) hh += 24;
  while (hh > 23) hh -= 24;
  return `${pad(hh)}:${pad(m)}`;
}

function formatHMS(date) {
  return `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`;
}

function offsetLabel(hours) {
  return hours >= 0 ? `GMT+${hours}` : `GMT${hours}`;
}

function sourceOffset(base, now) {
  if (base === "gmt") return 0;
  if (base === "london") return isEUDST(now) ? 1 : 0;
  if (base === "gmt+2") return 2;
  if (base === "gmt+3") return 3;
  return null;
}

function brokerOffset(preset, dstMode, now) {
  const winter = preset.offset;
  const mode = dstMode === "auto" ? preset.dst : dstMode;
  if (mode === "off") return winter;
  if (mode === "est") return winter + (isUSDST(now) ? 1 : 0);
  if (mode === "eet") return winter + (isEUDST(now) ? 1 : 0);
  return winter;
}

function convertToBroker(hhmm, base, bOff, now, auto) {
  const { h, m } = parseHHMM(hhmm);
  if (!auto || base === "broker") return { h, m, shift: 0 };
  const sOff = sourceOffset(base, now);
  const shift = bOff - (sOff ?? bOff);
  return { h: h + shift, m, shift };
}

function clockAtOffset(now, offsetHours) {
  return new Date(now.getTime() + offsetHours * 3600 * 1000);
}

function minutesOf({ h, m }) {
  let tot = h * 60 + m;
  while (tot < 0) tot += 1440;
  return tot % 1440;
}

function populateBrokers() {
  const sel = $("brokerPreset");
  BROKERS.forEach((b) => {
    const opt = document.createElement("option");
    opt.value = b.id;
    opt.textContent = b.name;
    sel.appendChild(opt);
  });
}

function selectedBroker() {
  return BROKERS.find((b) => b.id === $("brokerPreset").value) || BROKERS[0];
}

function currentState() {
  const now = new Date();
  const preset = selectedBroker();
  const dstMode = $("brokerDst").value;
  const base = $("timeBase").value;
  const auto = $("autoAdjust").checked;
  const bOff = brokerOffset(preset, dstMode, now);
  const sOff = base === "broker" ? bOff : sourceOffset(base, now);
  const start = convertToBroker($("startTime").value, base, bOff, now, auto);
  const end = convertToBroker($("endTime").value, base, bOff, now, auto);
  const sess = convertToBroker($("sessionEnd").value, base, bOff, now, auto);
  return { now, preset, dstMode, base, auto, bOff, sOff, start, end, sess };
}

function render() {
  const s = currentState();
  const brokerNow = clockAtOffset(s.now, s.bOff);
  const londonOff = isEUDST(s.now) ? 1 : 0;
  const londonNow = clockAtOffset(s.now, londonOff);
  const gmtNow = new Date(s.now.getTime());
  const localOff = -s.now.getTimezoneOffset() / 60;

  $("clkBroker").textContent = formatHMS(brokerNow);
  $("clkBrokerOff").textContent = `${offsetLabel(s.bOff)} · ${s.preset.name.split("(")[0].trim()}`;
  $("clkLondon").textContent = formatHMS(londonNow);
  $("clkLondonOff").textContent = londonOff ? "BST GMT+1" : "GMT";
  $("clkGmt").textContent = formatHMS(gmtNow);
  $("clkLocal").textContent = s.now.toLocaleTimeString("en-GB", { hour12: false });
  $("clkLocalOff").textContent = offsetLabel(localOff);

  const boxA = formatHHMM(s.start.h, s.start.m);
  const boxB = formatHHMM(s.end.h, s.end.m);
  const ses = formatHHMM(s.sess.h, s.sess.m);
  $("boxBroker").textContent = `${boxA} – ${boxB}`;
  $("sessBroker").textContent = ses;

  const shift = s.auto && s.base !== "broker" ? s.start.shift : 0;
  const sign = shift >= 0 ? `+${shift}` : `${shift}`;
  $("shiftMath").innerHTML = s.auto && s.base !== "broker"
    ? `${$("timeBase").selectedOptions[0].text} ${$("startTime").value} (${offsetLabel(s.sOff)})<br>` +
      `+ broker is ${offsetLabel(s.bOff)}  →  shift ${sign}h<br>` +
      `= <span style="color:#4aa3ff">${boxA}–${boxB}</span> on the MT4 chart`
    : `Auto-adjust off — times are used exactly as typed, as raw broker/chart time.`;

  const inBox = isInWindow(brokerNow, s.start, s.end);
  const inSess = !inBox && isInWindow(brokerNow, s.end, s.sess, true);
  const phase = inBox ? "INSIDE BOX" : inSess ? "BREAKOUT SESSION" : "WAITING";
  $("phaseLabel").textContent = phase;
  $("liveFlag").style.color = inBox ? "#4aa3ff" : inSess ? "#c9a227" : "#3ecf8e";

  $("statusGrid").innerHTML = `
    <div><b>Detected offset</b><br>${offsetLabel(s.bOff)}</div>
    <div><b>DST policy</b><br>${s.dstMode.toUpperCase()} · EU ${isEUDST(s.now) ? "summer" : "winter"}</div>
    <div><b>Input window</b><br>${$("startTime").value}–${$("endTime").value}</div>
    <div><b>Weekend rule</b><br>Sat/Sun box rolls back to Friday</div>
  `;

  $("tlDate").textContent = brokerNow.toISOString().slice(0, 10) + " broker date";
  drawTimeline(s, brokerNow);

  $("inputsPreview").textContent = [
    `StartTime = "${$("startTime").value}"`,
    `EndTime = "${$("endTime").value}"`,
    `SessionEndTime = "${$("sessionEnd").value}"`,
    `TimesAreSpecifiedIn = "${labelBase(s.base)}"`,
    `AutoAdjustToBrokerTime = ${s.auto}`,
    `BrokerGMTOffsetHours = 99   // auto from TimeCurrent-TimeGMT`,
    `BrokerDST = "${s.dstMode === "auto" ? "Auto" : s.dstMode.toUpperCase()}"`,
  ].join("\n");
}

function labelBase(base) {
  if (base === "gmt+2") return "GMT+2";
  if (base === "gmt") return "GMT";
  if (base === "broker") return "Broker";
  return "London";
}

function isInWindow(brokerNow, a, b, overnight = false) {
  const cur = brokerNow.getUTCHours() * 60 + brokerNow.getUTCMinutes();
  const start = minutesOf(a);
  let end = minutesOf(b);
  if (overnight || start > end) {
    return cur >= start || cur < end;
  }
  return cur >= start && cur < end;
}

function drawTimeline(s, brokerNow) {
  const track = $("track");
  const hours = $("hours");
  track.innerHTML = "";
  hours.innerHTML = "";
  for (let i = 0; i < 24; i++) {
    const el = document.createElement("div");
    el.textContent = pad(i);
    hours.appendChild(el);
  }

  const startM = minutesOf(s.start);
  const endM = minutesOf(s.end);
  const sessM = minutesOf(s.sess);

  addSeg(track, "box", startM, endM);
  addSeg(track, "sess", endM, sessM);

  const nowM = brokerNow.getUTCHours() * 60 + brokerNow.getUTCMinutes();
  const needle = document.createElement("div");
  needle.className = "needle";
  needle.style.left = `${(nowM / 1440) * 100}%`;
  track.appendChild(needle);
}

function addSeg(track, cls, fromM, toM) {
  const mk = (a, b) => {
    const el = document.createElement("div");
    el.className = `seg ${cls}`;
    el.style.left = `${(a / 1440) * 100}%`;
    el.style.width = `${((b - a) / 1440) * 100}%`;
    track.appendChild(el);
  };
  if (fromM <= toM) mk(fromM, toM);
  else {
    mk(fromM, 1440);
    mk(0, toM);
  }
}

function copyInputs() {
  navigator.clipboard.writeText($("inputsPreview").textContent).then(() => {
    $("copyInputs").textContent = "Copied";
    setTimeout(() => { $("copyInputs").textContent = "Copy suggested inputs"; }, 1400);
  });
}

function bind() {
  populateBrokers();
  ["brokerPreset", "brokerDst", "timeBase", "startTime", "endTime", "sessionEnd", "autoAdjust"]
    .forEach((id) => $(id).addEventListener("input", render));
  $("brokerPreset").addEventListener("change", () => {
    const b = selectedBroker();
    $("brokerDst").value = b.dst === "off" ? "off" : b.dst === "est" ? "est" : "auto";
    render();
  });
  $("copyInputs").addEventListener("click", copyInputs);
  render();
  setInterval(render, 1000);
}

bind();

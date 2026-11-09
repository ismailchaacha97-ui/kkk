import { useEffect, useRef, useState } from "react";
import { Floor } from "../engine/floor.js";
import { SYMBOLS, TICK_MS } from "../engine/market.js";

export function useSim() {
  const floorRef = useRef(null);
  if (!floorRef.current) floorRef.current = new Floor();
  const floor = floorRef.current;

  const [, setV] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [paused, setPaused] = useState(false);
  const [selectedSymbol, setSelectedSymbol] = useState("EURUSD");
  const [activeThread, setActiveThread] = useState(null);
  const debateTimer = useRef(0);
  const visibleRef = useRef(true);

  useEffect(() => {
    // never accumulate a tick backlog while the tab is in the background
    const onVis = () => {
      visibleRef.current = document.visibilityState === "visible";
    };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, []);

  useEffect(() => {
    const tick = () => {
      if (!visibleRef.current) return;
      floor.step();
      setV((v) => v + 1);
    };
    const id = setInterval(tick, Math.max(120, TICK_MS / speed));
    return () => clearInterval(id);
  }, [floor, speed]);

  useEffect(() => {
    floor.paused = paused;
  }, [floor, paused]);

  // scheduler: open a debate every ~9-14 ticks, rotating symbols, max 1 at a time
  useEffect(() => {
    const id = setInterval(() => {
      if (paused) return;
      const live = floor.threads.filter((t) => t.status === "talking").length;
      if (live >= 1) return;
      const sym = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)].symbol;
      const th = floor.startDebate(sym);
      if (th) {
        setActiveThread(th.id);
        setSelectedSymbol(sym);
      }
    }, 2600);
    return () => clearInterval(id);
  }, [floor, paused]);

  const thread = floor.threads.find((t) => t.id === activeThread) || floor.threads[0] || null;

  const actions = {
    togglePause: () => setPaused((p) => !p),
    setSpeed,
    setSelectedSymbol: (s) => {
      setSelectedSymbol(s);
    },
    forceDebate: () => {
      const live = floor.threads.filter((t) => t.status === "talking").length;
      if (live >= 1) return;
      const sym = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)].symbol;
      const th = floor.startDebate(sym);
      if (th) {
        setActiveThread(th.id);
        setSelectedSymbol(sym);
      }
    },
    selectThread: (id) => {
      const t = floor.threads.find((x) => x.id === id);
      setActiveThread(id);
      if (t) setSelectedSymbol(t.symbol);
    },
    setRules: (r) => {
      Object.assign(floor.rules, r);
      setV((v) => v + 1);
    },
    reevaluate: () => {
      floor.market.recomputeAll();
      setV((v) => v + 1);
    },
  };

  return { floor, thread, selectedSymbol, speed, paused, actions, version: floor.market.tick };
}

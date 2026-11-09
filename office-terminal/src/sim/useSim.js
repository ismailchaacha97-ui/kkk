import { useEffect, useRef, useState } from "react";
import { Floor } from "../engine/floor.js";
import { TICK_MS, LEVERAGE } from "../engine/market.js";
import { INSTRUMENTS } from "../engine/instruments.js";

export function useSim() {
  const floorRef = useRef(null);
  if (!floorRef.current) floorRef.current = new Floor();
  const floor = floorRef.current;

  const [, force] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [paused, setPaused] = useState(false);
  const [selectedSymbol, setSelectedSymbol] = useState(INSTRUMENTS[0].symbol);
  const [selectedAgent, setSelectedAgent] = useState(null);
  const [booted, setBooted] = useState(false);
  const visible = useRef(true);

  // live boot: fetch real candles once, then keep polling on the market clock
  useEffect(() => {
    let cancelled = false;
    floor.connect().then(() => {
      if (cancelled) return;
      setBooted(true);
      force((v) => v + 1);
    });
    return () => {
      cancelled = true;
    };
  }, [floor]);

  useEffect(() => {
    const onVis = () => {
      visible.current = document.visibilityState === "visible";
    };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, []);

  useEffect(() => {
    const id = setInterval(() => {
      if (!visible.current) return;
      floor.onTick();
      force((v) => v + 1);
    }, Math.max(180, TICK_MS / speed));
    return () => clearInterval(id);
  }, [floor, speed]);

  useEffect(() => {
    floor.paused = paused;
  }, [floor, paused]);

  // save progress periodically so free will + learning survive a reload
  useEffect(() => {
    const id = setInterval(() => floor.save(), 20000);
    const onLeave = () => floor.save();
    window.addEventListener("beforeunload", onLeave);
    return () => {
      clearInterval(id);
      window.removeEventListener("beforeunload", onLeave);
      floor.save();
    };
  }, [floor]);

  const actions = {
    togglePause: () => setPaused((p) => !p),
    setSpeed,
    selectAgent: (id) => setSelectedAgent((cur) => (cur === id ? null : id)),
    setSelectedSymbol,
    callDebate: () => {
      const agent = floor.agents[Math.floor(Math.random() * floor.agents.length)];
      const sym = agent.focusSymbol || selectedSymbol;
      floor.openDebate(sym, agent);
      force((v) => v + 1);
    },
    hire: () => {
      floor.hire("the desk needed another voice");
      force((v) => v + 1);
    },
    setRules: (patch) => {
      Object.assign(floor.houseRules, patch);
      force((v) => v + 1);
    },
    reset: () => {
      floor.resetProgress();
      setSelectedAgent(null);
      force((v) => v + 1);
    },
    reconnect: async () => {
      await floor.connect();
      force((v) => v + 1);
    },
  };

  return {
    floor,
    booted,
    paused,
    speed,
    selectedSymbol,
    selectedAgent,
    actions,
    rules: floor.houseRules,
    leverage: LEVERAGE,
  };
}

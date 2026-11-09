import React, { useEffect, useRef } from "react";
import * as THREE from "three";
import { buildOffice, buildDesk, makeAvatar, animateAvatar } from "../three/office.js";
import { updateScreens } from "../three/screens.js";

// desk layout: 6 around the holo table, 4 more in the annex
export const DESK_SLOTS = [
  { x: -4.6, z: -2.4, rot: 0.55 },
  { x: -1.5, z: -3.4, rot: 0.16 },
  { x: 1.9, z: -3.3, rot: -0.16 },
  { x: 5.0, z: -2.3, rot: -0.55 },
  { x: -5.4, z: 1.6, rot: 1.15 },
  { x: 5.4, z: 1.6, rot: -1.15 },
  { x: 10.0, z: -3.6, rot: 0.4 },
  { x: 13.2, z: -3.4, rot: -0.35 },
  { x: 10.2, z: 1.4, rot: 2.6 },
  { x: 13.3, z: 1.2, rot: -2.7 },
];

// waypoints agents wander between when they get up from their chair
const WAYPOINTS = [
  { x: 0.2, z: 3.2, label: "holo table" },
  { x: -5.9, z: 4.4, label: "whiteboard" },
  { x: -6.3, z: -4.2, label: "coffee" },
  { x: 11.4, z: 0.2, label: "lounge" },
  { x: 13.2, z: 2.4, label: "kitchen" },
  { x: 2.4, z: -1.6, label: "the tape" },
  { x: -2.6, z: 0.8, label: "the floor" },
];

export function useTradingFloor(floor, mountRef) {
  useEffect(() => {
    if (!floor || !mountRef.current) return undefined;
    const mount = mountRef.current;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x04070c);
    scene.fog = new THREE.FogExp2(0x04070c, 0.021);

    const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.2;
    renderer.domElement.style.display = "block";
    mount.appendChild(renderer.domElement);

    const camera = new THREE.PerspectiveCamera(48, 1, 0.1, 140);

    // ---------- lights ----------
    scene.add(new THREE.HemisphereLight(0x9dc0ff, 0x0c1119, 0.5));
    const key = new THREE.DirectionalLight(0xe6f0ff, 1.1);
    key.position.set(7, 11, 6);
    key.castShadow = true;
    key.shadow.mapSize.set(2048, 2048);
    key.shadow.camera.left = -18;
    key.shadow.camera.right = 18;
    key.shadow.camera.top = 16;
    key.shadow.camera.bottom = -16;
    key.shadow.camera.far = 46;
    key.shadow.bias = -0.0009;
    scene.add(key);
    const fill = new THREE.DirectionalLight(0x5f9dff, 0.42);
    fill.position.set(-8, 6, -6);
    scene.add(fill);
    const holoLight = new THREE.PointLight(0x4fd1ff, 16, 11, 2);
    holoLight.position.set(0, 2.1, 0.2);
    scene.add(holoLight);
    const annexLight = new THREE.PointLight(0xffc27a, 7, 10, 2);
    annexLight.position.set(11.4, 3.2, -1.4);
    scene.add(annexLight);

    const office = buildOffice(scene);

    // ---------- camera controls ----------
    const cam = { theta: 0.42, phi: 1.03, radius: 15.5, target: new THREE.Vector3(2.4, 1.15, 0.2) };
    let dragging = false;
    let lastX = 0;
    let lastY = 0;
    let autoRotate = true;
    let spin = 0;
    const onDown = (e) => {
      dragging = true;
      autoRotate = false;
      lastX = e.clientX;
      lastY = e.clientY;
      renderer.domElement.style.cursor = "grabbing";
    };
    const onUp = () => {
      dragging = false;
      renderer.domElement.style.cursor = "grab";
    };
    const onMove = (e) => {
      if (!dragging) return;
      cam.theta -= (e.clientX - lastX) * 0.0055;
      cam.phi = Math.max(0.32, Math.min(1.45, cam.phi - (e.clientY - lastY) * 0.004));
      lastX = e.clientX;
      lastY = e.clientY;
    };
    const onWheel = (e) => {
      cam.radius = Math.max(5, Math.min(30, cam.radius + e.deltaY * 0.008));
      e.preventDefault();
    };
    const onKey = (e) => {
      if (e.key === "r" || e.key === "R") autoRotate = !autoRotate;
      if (e.key === "f" || e.key === "F") {
        cam.theta = 0.42;
        cam.phi = 1.03;
        cam.radius = 15.5;
      }
    };
    const el = renderer.domElement;
    el.style.cursor = "grab";
    el.addEventListener("pointerdown", onDown);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointermove", onMove);
    el.addEventListener("wheel", onWheel, { passive: false });
    window.addEventListener("keydown", onKey);

    const resize = () => {
      const w = mount.clientWidth || 800;
      const h = mount.clientHeight || 600;
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(mount);

    // ---------- desks + avatars ----------
    const desks = new Map(); // agentId -> { deskObj, rig, walk }

    const addAgent = (agent, index) => {
      const slot = DESK_SLOTS[index % DESK_SLOTS.length];
      const deskObj = buildDesk(slot, agent);
      scene.add(deskObj.group);
      const rig = makeAvatar({
        color: agent.color,
        seed: (agent.name || "a").charCodeAt(0) + index,
        seated: true,
        female: index % 2 === 1,
      });
      rig.g.position.set(0, 0, 0.62);
      rig.g.rotation.y = Math.PI;
      deskObj.group.add(rig.g);
      desks.set(agent.id, {
        deskObj,
        rig,
        walk: { active: false, t: 0, from: new THREE.Vector3(slot.x, 0, slot.z + 0.62), to: null, target: null },
        slot,
      });
    };

    floor.agents.forEach(addAgent);

    const syncRoster = () => {
      const ids = new Set(floor.agents.map((a) => a.id));
      // remove desks for people who left
      for (const [id, entry] of [...desks.entries()]) {
        if (!ids.has(id)) {
          scene.remove(entry.deskObj.group);
          entry.deskObj.group.traverse((o) => {
            if (o.geometry) o.geometry.dispose();
            if (o.material) {
              const mats = Array.isArray(o.material) ? o.material : [o.material];
              mats.forEach((m) => {
                if (m.map) m.map.dispose();
                m.dispose();
              });
            }
          });
          desks.delete(id);
        }
      }
      // add desks for new hires
      floor.agents.forEach((a, i) => {
        if (!desks.has(a.id)) addAgent(a, i);
      });
    };

    // ---------- render loop ----------
    let raf = 0;
    let lastScreens = 0;
    const clock = new THREE.Clock();

    const loop = () => {
      raf = requestAnimationFrame(loop);
      const t = clock.getElapsedTime();
      syncRoster();

      if (autoRotate && !dragging) spin += 0.00055;
      const theta = cam.theta + Math.sin(spin) * 0.075;
      camera.position.set(
        cam.target.x + Math.sin(theta) * Math.sin(cam.phi) * cam.radius,
        cam.target.y + Math.cos(cam.phi) * cam.radius,
        cam.target.z + Math.cos(theta) * Math.sin(cam.phi) * cam.radius
      );
      camera.lookAt(cam.target);

      // avatars: seated at their desk, or walking on their own business
      for (const [id, entry] of desks) {
        const agent = floor.get(id);
        if (!agent) continue;
        const speaking = Date.now() - (agent.lastSpokeAt || 0) < 2600;
        const away = agent.lastAction === "stepped away" || agent.lastAction === "getting coffee";
        const wander = away || agent.walkingTo;

        if (wander && !entry.walk.active) {
          const wp = WAYPOINTS[Math.floor(Math.abs(Math.sin(id.charCodeAt(1) || 1)) * WAYPOINTS.length)];
          entry.walk.active = true;
          entry.walk.t = 0;
          entry.walk.to = new THREE.Vector3(wp.x, 0, wp.z);
          entry.rig.g.position.set(0, 0, 0);
          entry.rig.g.rotation.y = 0;
          scene.attach(entry.rig.g);
          entry.rig.g.position.set(entry.slot.x, 0, entry.slot.z + 0.62);
          entry.rig.seated = false;
          // swap seated legs for standing legs is expensive; instead lift & stand
          entry.rig.hips.position.y = 0.5;
        } else if (!wander && entry.walk.active) {
          entry.walk.active = false;
          const d = entry.deskObj.group;
          d.attach(entry.rig.g);
          entry.rig.g.position.set(0, 0, 0.62);
          entry.rig.g.rotation.set(0, Math.PI, 0);
          entry.rig.seated = true;
        }

        if (entry.walk.active && entry.walk.to) {
          const p = entry.rig.g.position;
          const target = entry.walk.to;
          const dir = new THREE.Vector3().subVectors(target, p);
          dir.y = 0;
          const dist = dir.length();
          if (dist > 0.12) {
            dir.normalize();
            p.addScaledVector(dir, 0.022);
            entry.rig.g.rotation.y = Math.atan2(dir.x, dir.z);
          }
        }

        animateAvatar(
          entry.rig,
          t + id.length,
          speaking,
          entry.walk.active ? 1 : 0,
          agent.moodDef?.color
        );

        // mood LED on the desk
        if (entry.deskObj.moodLed) {
          entry.deskObj.moodLed.material.color.set(agent.moodDef?.color || "#8cb4ff");
        }
      }

      // holo table & atmosphere
      office.beam.material.opacity = 0.04 + Math.sin(t * 1.3) * 0.014;
      office.table.rotation.y = Math.sin(t * 0.1) * 0.012;
      if (office.machineLed) office.machineLed.visible = Math.sin(t * 3) > -0.4;

      if (t - lastScreens > 0.25) {
        try {
          updateScreens(office, desks, floor);
        } catch (err) {
          /* a screen failing must never kill the renderer */
        }
        lastScreens = t;
      }
      renderer.render(scene, camera);
    };
    loop();

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      el.removeEventListener("pointerdown", onDown);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointermove", onMove);
      el.removeEventListener("wheel", onWheel);
      window.removeEventListener("keydown", onKey);
      scene.traverse((o) => {
        if (o.geometry) o.geometry.dispose();
        if (o.material) {
          const mats = Array.isArray(o.material) ? o.material : [o.material];
          mats.forEach((m) => {
            if (m.map) m.map.dispose();
            m.dispose();
          });
        }
      });
      renderer.dispose();
      if (el.parentNode) el.parentNode.removeChild(el);
    };
  }, [floor, mountRef]);
}

export default function Scene3D({ floor }) {
  const mountRef = useRef(null);
  useTradingFloor(floor, mountRef);
  return <div className="scene3d" ref={mountRef} />;
}

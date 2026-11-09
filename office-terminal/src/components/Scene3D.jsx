import React, { useEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { buildRoom, updateScreens } from "../three/assets.js";
import { makeAvatar, animateAvatar } from "../three/avatars.js";

function useRenderLoop(floor, mountRef) {
  useEffect(() => {
    if (!floor) return undefined;
    const mount = mountRef.current;
    if (!mount) return undefined;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x05080e);
    scene.fog = new THREE.FogExp2(0x05080e, 0.035);
    const camera = new THREE.PerspectiveCamera(46, 1, 0.1, 120);
    const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.15;
    mount.appendChild(renderer.domElement);
    renderer.domElement.style.display = "block";
    renderer.domElement.style.cursor = "grab";

    // lights
    scene.add(new THREE.HemisphereLight(0x9fc4ff, 0x10151d, 0.55));
    const key = new THREE.DirectionalLight(0xdfeaff, 1.25);
    key.position.set(5, 9, 5);
    key.castShadow = true;
    key.shadow.mapSize.set(2048, 2048);
    key.shadow.camera.near = 1;
    key.shadow.camera.far = 40;
    key.shadow.camera.left = -12;
    key.shadow.camera.right = 12;
    key.shadow.camera.top = 12;
    key.shadow.camera.bottom = -12;
    key.shadow.bias = -0.0008;
    scene.add(key);
    const fill = new THREE.DirectionalLight(0x6ea8ff, 0.5);
    fill.position.set(-7, 5, -4);
    scene.add(fill);
    const tableLight = new THREE.PointLight(0x4fd1ff, 22, 12, 2);
    tableLight.position.set(0, 2.2, 0.4);
    scene.add(tableLight);

    const assets = buildRoom(scene);

    // avatars seated INSIDE their desk group so they inherit the desk transform
    const avatars = {};
    const seats = {
      victor: { seed: 0, accent: "#5ceb8e" },
      maria: { seed: 1, accent: "#f26457" },
      alexei: { seed: 2, accent: "#f5b841" },
      judge: { seed: 3, accent: "#c9a7ff" },
    };
    for (const [id, o] of Object.entries(seats)) {
      const rig = makeAvatar({ seed: o.seed, accent: o.accent, seated: true });
      rig.g.position.set(0, 0, 0.62);
      rig.g.rotation.y = Math.PI; // face the monitors
      const desk = assets.registry[id];
      if (desk) desk.group.add(rig.g);
      else scene.add(rig.g);
      avatars[id] = rig;
    }

    // camera orbit control (hand-rolled, no deps)
    const cam = { theta: 0.05, phi: 1.02, radius: 9.6, target: new THREE.Vector3(0, 1.25, 0.4) };
    let dragging = false;
    let lastX = 0;
    let lastY = 0;
    let idleSpin = 0;
    const onDown = (e) => {
      dragging = true;
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
      cam.theta -= (e.clientX - lastX) * 0.006;
      cam.phi = Math.min(1.42, Math.max(0.42, cam.phi - (e.clientY - lastY) * 0.0045));
      lastX = e.clientX;
      lastY = e.clientY;
    };
    const onWheel = (e) => {
      cam.radius = Math.min(18, Math.max(4.2, cam.radius + e.deltaY * 0.0045));
      e.preventDefault();
    };
    const el = renderer.domElement;
    el.addEventListener("pointerdown", onDown);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointermove", onMove);
    el.addEventListener("wheel", onWheel, { passive: false });

    const resize = () => {
      const w = mount.clientWidth;
      const h = mount.clientHeight;
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(mount);

    let raf = 0;
    let lastScreen = 0;
    const clock = new THREE.Clock();
    const loop = () => {
      raf = requestAnimationFrame(loop);
      const t = clock.getElapsedTime();

      if (!dragging) idleSpin += 0.0009;
      const theta = cam.theta + Math.sin(idleSpin) * 0.055;
      const target = cam.target;
      camera.position.set(
        target.x + Math.sin(theta) * Math.sin(cam.phi) * cam.radius,
        target.y + Math.cos(cam.phi) * cam.radius,
        target.z + Math.cos(theta) * Math.sin(cam.phi) * cam.radius
      );
      camera.lookAt(target);

      // animate traders
      for (const [id, rig] of Object.entries(avatars)) {
        const speaking = floor.agents[id] && Date.now() - floor.agents[id].lastSpokeAt < 2600;
        animateAvatar(rig, t + seats[id].seed, Boolean(speaking));
      }

      // holo table floats
      assets.beam.material.opacity = 0.045 + Math.sin(t * 1.4) * 0.018;
      assets.table.rotation.y = Math.sin(t * 0.12) * 0.02;

      if (t - lastScreen > 0.22) {
        try {
          updateScreens(assets, floor);
        } catch (err) {
          /* non fatal */
        }
        lastScreen = t;
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
      renderer.dispose();
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
      if (el.parentNode) el.parentNode.removeChild(el);
    };
  }, [floor]);
}

export default function Scene3D({ floor }) {
  const mountRef = useRef(null);
  useRenderLoop(floor, mountRef);
  return <div className="scene3d" ref={mountRef} />;
}

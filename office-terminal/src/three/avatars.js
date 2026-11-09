import * as THREE from "three";

const SKIN = [0xd9a06b, 0x8d5524, 0xf0c9a0, 0x5c3b22, 0xe2b48c];
const SHIRT = [0x2b3f57, 0x3d2b3f, 0x27303a, 0x1f3a34, 0x33261f];
const HAIR = [0x1a1512, 0x2b1d12, 0x0f0d0c, 0x492f1c, 0x5a3f28];

function part(geo, mat, x, y, z) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}

// Low-poly office worker. Returns group + joints for animation.
export function makeAvatar({ seed = 0, accent = "#5ceb8e", seated = true } = {}) {
  const g = new THREE.Group();
  const skin = new THREE.MeshStandardMaterial({ color: SKIN[seed % SKIN.length], roughness: 0.75 });
  const shirt = new THREE.MeshStandardMaterial({ color: SHIRT[seed % SHIRT.length], roughness: 0.85 });
  const hair = new THREE.MeshStandardMaterial({ color: HAIR[seed % HAIR.length], roughness: 0.9 });
  const trousers = new THREE.MeshStandardMaterial({ color: 0x1a1f27, roughness: 0.9 });

  // hips
  const hips = new THREE.Group();
  hips.position.y = 0.52;
  g.add(hips);

  // torso
  const torso = part(new THREE.CapsuleGeometry(0.21, 0.32, 6, 12), shirt, 0, 0.32, 0);
  torso.scale.set(1.05, 1, 0.8);
  hips.add(torso);

  // neck + head
  const head = new THREE.Group();
  head.position.y = 0.66;
  hips.add(head);
  const skull = part(new THREE.SphereGeometry(0.155, 20, 16), skin, 0, 0, 0);
  skull.scale.set(0.94, 1.05, 0.94);
  head.add(skull);
  const cap = part(new THREE.SphereGeometry(0.162, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2), hair, 0, 0.01, 0);
  head.add(cap);
  // eyes
  const eyeMat = new THREE.MeshStandardMaterial({ color: 0x0b0f14, roughness: 0.3 });
  for (const ex of [-0.055, 0.055]) {
    head.add(part(new THREE.SphereGeometry(0.019, 8, 8), eyeMat, ex, 0.01, 0.14));
  }
  // headset (traders live on the phone)
  const hsMat = new THREE.MeshStandardMaterial({ color: 0x0d1117, roughness: 0.5, metalness: 0.4 });
  const band = part(new THREE.TorusGeometry(0.16, 0.014, 8, 24, Math.PI), hsMat, 0, 0.02, 0);
  band.rotation.y = Math.PI / 2;
  band.rotation.z = Math.PI / 2;
  head.add(band);
  head.add(part(new THREE.CapsuleGeometry(0.014, 0.07, 4, 8), hsMat, -0.15, -0.03, 0.03));
  const mic = part(new THREE.CapsuleGeometry(0.009, 0.09, 4, 8), hsMat, -0.1, -0.09, 0.1);
  mic.rotation.z = 0.7;
  head.add(mic);
  // accent LED on headset
  const led = new THREE.Mesh(
    new THREE.SphereGeometry(0.017, 8, 8),
    new THREE.MeshBasicMaterial({ color: new THREE.Color(accent) })
  );
  led.position.set(-0.15, -0.02, 0.05);
  head.add(led);

  // arms
  const arms = [];
  for (const side of [-1, 1]) {
    const shoulder = new THREE.Group();
    shoulder.position.set(side * 0.26, 0.5, 0);
    hips.add(shoulder);
    const upper = part(new THREE.CapsuleGeometry(0.065, 0.2, 5, 10), shirt, 0, -0.13, 0);
    shoulder.add(upper);
    const elbow = new THREE.Group();
    elbow.position.y = -0.25;
    shoulder.add(elbow);
    const lower = part(new THREE.CapsuleGeometry(0.055, 0.19, 5, 10), skin, 0, -0.12, 0);
    elbow.add(lower);
    const hand = part(new THREE.SphereGeometry(0.058, 10, 8), skin, 0, -0.24, 0);
    elbow.add(hand);
    arms.push({ shoulder, elbow, side });
    // seated pose: forearms forward over the desk
    shoulder.rotation.x = seated ? -0.95 : -0.15;
    elbow.rotation.x = seated ? -0.85 : -0.25;
    shoulder.rotation.z = side * 0.12;
  }

  // legs
  for (const side of [-1, 1]) {
    const hip = new THREE.Group();
    hip.position.set(side * 0.11, -0.02, 0);
    hips.add(hip);
    if (seated) {
      hip.rotation.x = Math.PI / 2;
      const thigh = part(new THREE.CapsuleGeometry(0.08, 0.24, 5, 10), trousers, 0, -0.16, 0);
      hip.add(thigh);
      const knee = new THREE.Group();
      knee.position.y = -0.33;
      hip.add(knee);
      knee.rotation.x = -Math.PI / 2;
      const shin = part(new THREE.CapsuleGeometry(0.07, 0.3, 5, 10), trousers, 0, -0.2, 0);
      knee.add(shin);
      knee.add(part(new THREE.BoxGeometry(0.13, 0.07, 0.22), new THREE.MeshStandardMaterial({ color: 0x0b0d11, roughness: 0.6 }), 0, -0.4, 0.04));
    } else {
      const thigh = part(new THREE.CapsuleGeometry(0.075, 0.4, 5, 10), trousers, 0, -0.28, 0);
      hip.add(thigh);
      hip.add(part(new THREE.BoxGeometry(0.12, 0.07, 0.2), new THREE.MeshStandardMaterial({ color: 0x0b0d11 }), 0, -0.62, 0.04));
    }
  }

  // office chair
  const chair = new THREE.Group();
  const chairMat = new THREE.MeshStandardMaterial({ color: 0x0e1319, roughness: 0.7, metalness: 0.2 });
  const seat = part(new THREE.BoxGeometry(0.56, 0.09, 0.54), chairMat, 0, 0, 0.02);
  chair.add(seat);
  const backrest = part(new THREE.BoxGeometry(0.56, 0.66, 0.09), chairMat, 0, 0.36, -0.26);
  backrest.rotation.x = -0.12;
  chair.add(backrest);
  chair.position.set(0, 0.47, -0.06);
  g.add(chair);

  // subtle breathing/animation hooks
  const rig = { hips, head, arms, torso, chair, led, g };
  return rig;
}

export function animateAvatar(rig, t, talking = false) {
  const breathe = Math.sin(t * 1.6) * 0.012;
  rig.hips.position.y = 0.52 + breathe;
  rig.head.rotation.y = Math.sin(t * 0.5) * 0.16;
  rig.head.rotation.x = Math.sin(t * 0.73) * 0.05 - 0.04;
  if (talking) {
    rig.head.rotation.z = Math.sin(t * 9) * 0.04;
    rig.arms[0].elbow.rotation.x = -0.85 + Math.sin(t * 5.5) * 0.22;
    rig.arms[1].elbow.rotation.x = -0.85 + Math.sin(t * 4.9 + 1) * 0.16;
  } else {
    rig.head.rotation.z *= 0.9;
    rig.arms[0].elbow.rotation.x += (-0.85 - rig.arms[0].elbow.rotation.x) * 0.1;
    rig.arms[1].elbow.rotation.x += (-0.85 - rig.arms[1].elbow.rotation.x) * 0.1;
  }
  rig.led.material.color.offsetHSL(0, 0, 0);
}

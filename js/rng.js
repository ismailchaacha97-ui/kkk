// Seeded RNG utilities
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function makeRng(seed) {
  const f = mulberry32(seed);
  const rng = {
    random: f,
    // integer in [a, b] inclusive
    int: (a, b) => a + Math.floor(f() * (b - a + 1)),
    pick: (arr) => arr[Math.floor(f() * arr.length)],
    chance: (p) => f() < p,
    // float in [a,b)
    range: (a, b) => a + f() * (b - a),
    shuffle: (arr) => {
      const c = arr.slice();
      for (let i = c.length - 1; i > 0; i--) {
        const j = Math.floor(f() * (i + 1));
        [c[i], c[j]] = [c[j], c[i]];
      }
      return c;
    },
    weighted: (pairs) => { // [[item, weight], ...]
      let total = 0;
      for (const [, w] of pairs) total += w;
      let r = f() * total;
      for (const [item, w] of pairs) { r -= w; if (r <= 0) return item; }
      return pairs[pairs.length - 1][0];
    },
  };
  return rng;
}

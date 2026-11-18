// node tools/export_level.mjs   (serve the repo root on :8770 first: python3 -m http.server 8770)
// Runs the browser build's level generator (web/src/plan.js + world.js) headless and writes what the Godot
// project loads: level/level.json (plan, lamps, props, doors, surface table) and level/level.bin (vertex data).
import { chromium } from '/opt/npm-tools/node_modules/playwright-core/index.mjs';
import fs from 'fs';
const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', headless: false, args: ['--use-gl=angle', '--use-angle=gl', '--ignore-gpu-blocklist', '--enable-gpu', '--no-sandbox', '--window-size=640,400'] });
const pg = await b.newPage({ viewport: { width: 640, height: 400 } });
pg.on('pageerror', (e) => console.log('[page]', e.message.slice(0, 300)));
await pg.goto(`http://localhost:${process.env.PORT || 8770}/index.html?bot=1&q=low&shadows=0&export=1`, { waitUntil: 'load' });
await pg.waitForFunction(() => window.HX && window.HX.ready, null, { timeout: 600000, polling: 500 });
const out = await pg.evaluate(() => {
  const G = window.HX, P = G.P, root = G.world.root;
  const surfaces = [];
  const b64 = (ta) => { const u8 = new Uint8Array(ta.buffer, ta.byteOffset, ta.byteLength); let s = ''; for (let i = 0; i < u8.length; i += 8192) s += String.fromCharCode.apply(null, u8.subarray(i, i + 8192)); return btoa(s); };
  for (const m of root.children) {
    if (!m.isMesh || m.isInstancedMesh || !m.geometry.attributes.bake) continue;
    const g = m.geometry, hx = m.material.userData.hx || { name: 'unknown' };
    const uv = new Float32Array(g.attributes.uv.array); for (let i = 1; i < uv.length; i += 2) uv[i] = -uv[i];
    surfaces.push({ mat: hx, nv: g.attributes.position.count, ni: g.index.count, pos: b64(g.attributes.position.array), nrm: b64(g.attributes.normal.array), uv: b64(uv), idx: b64(new Uint32Array(g.index.array)) });
  }
  const doors = G.world.DOORS.map((r) => ({ id: r.door.id, leaves: r.meshes.map((m) => [m.position.x, m.position.y, m.position.z, m.rotation.y]), lamps: r.lamps.map((m) => [m.position.x, m.position.y, m.position.z, m.rotation.y]) }));
  const plan = { C: P.C, NX: P.NX, NZ: P.NZ, NL: P.NL, LH: P.LH, CEIL: P.CEIL, X0: P.X0, Z0: P.Z0,
    kind: P.KIND.map((a) => Array.from(a)), room: P.ROOM.map((a) => Array.from(a)), ramp: P.RAMP.map((a) => Array.from(a)),
    edges: [...P.EDGE].map(([k, v]) => [k, v]), doors: P.DOORS.map((d) => ({ id: d.id, L: d.L, i: d.i, k: d.k, s: d.s, keys: d.keys, name: d.name })),
    ramps: P.RAMPS.map((r) => ({ ...r })), rooms: P.ROOMS.map((r) => ({ ...r })) };
  return { surfaces, doors, plan, lamps: G.LAMPS, place: G.PLACE, obstacles: G.HXobs };
});
await b.close();
// pack the vertex data into one binary; the JSON keeps offsets
const chunks = []; let off = 0;
const put = (s) => { const buf = Buffer.from(s, 'base64'); chunks.push(buf); const o = off; off += buf.length; return [o, buf.length]; };
for (const s of out.surfaces) { s.pos = put(s.pos); s.nrm = put(s.nrm); s.uv = put(s.uv); s.idx = put(s.idx); }
fs.mkdirSync('level', { recursive: true });
fs.writeFileSync('level/level.bin', Buffer.concat(chunks));
fs.writeFileSync('level/level.json', JSON.stringify(out));
console.log('surfaces', out.surfaces.length, 'verts', out.surfaces.reduce((a, s) => a + s.nv, 0), 'tris', out.surfaces.reduce((a, s) => a + s.ni, 0) / 3, 'lamps', out.lamps.length, 'props', out.place.length, 'doors', out.doors.length, 'bin MB', (off / 1e6).toFixed(1));
console.log(out.surfaces.map((s) => (s.mat.tex || s.mat.name) + (s.mat.color && s.mat.color !== 0xffffff ? '#' + s.mat.color.toString(16) : '')).join(' '));

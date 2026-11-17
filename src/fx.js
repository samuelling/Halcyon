// Feedback for a human player: sound, bullet holes, sparks and plaster dust, hit puffs, hit markers,
// the direction you were shot from, a heartbeat when hurt. The bot runs without any of it.
import * as THREE from 'three';
import { Sound } from './audio.js';

function canvasTex(draw, n = 64) {
  const c = document.createElement('canvas'); c.width = c.height = n; draw(c.getContext('2d'), n);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
export class FX {
  constructor(game, hud) {
    this.g = game; this.hud = hud; this.snd = new Sound();
    const scene = game.scene;
    // bullet holes: a ring of 80 reusable decals
    const holeTex = canvasTex((g, n) => {
      const gr = g.createRadialGradient(n / 2, n / 2, 0, n / 2, n / 2, n / 2);
      gr.addColorStop(0, 'rgba(10,8,6,1)'); gr.addColorStop(0.18, 'rgba(25,20,16,.95)'); gr.addColorStop(0.3, 'rgba(60,50,40,.55)'); gr.addColorStop(1, 'rgba(80,70,60,0)');
      g.fillStyle = gr; g.fillRect(0, 0, n, n);
      g.strokeStyle = 'rgba(20,16,12,.5)'; for (let k = 0; k < 7; k++) { const a = Math.random() * 6.28, r = n * (0.15 + Math.random() * 0.25); g.beginPath(); g.moveTo(n / 2, n / 2); g.lineTo(n / 2 + Math.cos(a) * r, n / 2 + Math.sin(a) * r); g.stroke(); }
    });
    const holeMat = new THREE.MeshStandardMaterial({ map: holeTex, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, roughness: 1 });
    this.holes = []; this.hi = 0;
    for (let k = 0; k < 80; k++) { const m = new THREE.Mesh(new THREE.PlaneGeometry(0.11, 0.11), holeMat); m.visible = false; m.renderOrder = 3; scene.add(m); this.holes.push(m); }
    // sparks and dust: one point cloud of short-lived particles
    this.N = 400; this.pp = new Float32Array(this.N * 3); this.pv = new Float32Array(this.N * 3); this.pl = new Float32Array(this.N); this.pc = new Float32Array(this.N * 3); this.pk = 0;
    // only live particles are drawn (packed into the front of these buffers each frame)
    this.dp = new Float32Array(this.N * 3); this.dc = new Float32Array(this.N * 3);
    const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.BufferAttribute(this.dp, 3)); geo.setAttribute('color', new THREE.BufferAttribute(this.dc, 3)); geo.setDrawRange(0, 0);
    const dot = canvasTex((g, n) => { const gr = g.createRadialGradient(n / 2, n / 2, 0, n / 2, n / 2, n / 2); gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, n, n); }, 32);
    this.points = new THREE.Points(geo, new THREE.PointsMaterial({ size: 0.05, map: dot, vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false }));
    this.points.frustumCulled = false; this.points.visible = false; scene.add(this.points);
    // puffs (dust, and a dark spray on a hit): a few sprites
    const puffTex = canvasTex((g, n) => { const gr = g.createRadialGradient(n / 2, n / 2, 0, n / 2, n / 2, n / 2); gr.addColorStop(0, 'rgba(255,255,255,.9)'); gr.addColorStop(0.5, 'rgba(255,255,255,.35)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, n, n); });
    this.puffs = [];
    for (let k = 0; k < 24; k++) { const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: puffTex, transparent: true, depthWrite: false, opacity: 0 })); s.visible = false; scene.add(s); this.puffs.push({ s, life: 0 }); }
    this.pi = 0; this.heartT = 0; this.hm = 0; this.dmg = [];
  }
  start() { this.snd.start(); }
  spark(pos, n, dir, col, speed = 3, life = 0.35) {
    for (let k = 0; k < n; k++) {
      const q = this.pk = (this.pk + 1) % this.N;
      this.pp[q * 3] = pos.x; this.pp[q * 3 + 1] = pos.y; this.pp[q * 3 + 2] = pos.z;
      const v = new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.3, Math.random() - 0.5).multiplyScalar(1.2).add(dir).normalize().multiplyScalar(speed * (0.4 + Math.random()));
      this.pv[q * 3] = v.x; this.pv[q * 3 + 1] = v.y; this.pv[q * 3 + 2] = v.z; this.pl[q] = life * (0.5 + Math.random());
      this.pc[q * 3] = col[0]; this.pc[q * 3 + 1] = col[1]; this.pc[q * 3 + 2] = col[2];
    }
  }
  puff(pos, color, size, life) {
    const P = this.puffs[this.pi = (this.pi + 1) % this.puffs.length];
    P.s.position.copy(pos); P.s.material.color.set(color); P.s.scale.setScalar(size); P.s.visible = true; P.life = P.life0 = life; P.size = size;
  }
  // ------------------------------------------------ events from the game
  shot(enc) { this.snd.shot(enc); }
  reload() { this.snd.reload(); }
  empty() { this.snd.empty(); }
  step(surface, run) { this.snd.step(surface, run); }
  pickup() { this.snd.pickup(); }
  power(on) { if (on) this.snd.powerUp(); else this.snd.powerDown(); }
  door(d) {
    const p = this.g.player; if (d.L !== p.L) return;
    const P = this.g.G.P, dist = Math.hypot(P.cx(d.i) - p.pos.x, P.cz(d.k) - p.pos.z);
    if (dist < 30) this.snd.door(dist, !d.open);
  }
  impact(res) {
    if (!res) return;
    const m = this.holes[this.hi = (this.hi + 1) % this.holes.length];
    m.position.copy(res.pos); m.lookAt(res.pos.clone().add(res.n)); m.rotateZ(Math.random() * 6.28); m.visible = !res.glass;
    const lit = this.g.power > 0.5 ? 1 : 0.5;
    if (res.metal) { this.spark(res.pos, 14, res.n, [1.0 * lit, 0.75 * lit, 0.35 * lit], 4, 0.3); this.snd.burst({ dur: 0.08, f: 3800, q: 6, gain: 0.12, verb: 0.2 }); }
    else { this.spark(res.pos, 5, res.n, [0.5, 0.42, 0.33], 2, 0.4); this.puff(res.pos.clone().addScaledVector(res.n, 0.08), res.floor ? 0x8a8070 : 0xb8b0a0, 0.25, 0.6); this.snd.burst({ dur: 0.06, f: 1200, q: 2, gain: 0.08, verb: 0.15 }); }
  }
  hitActor(hit, pt) {
    this.puff(pt, 0x3a0d0a, 0.22, 0.35); this.spark(pt, 6, new THREE.Vector3(0, 0.2, 0), [0.25, 0.03, 0.02], 1.5, 0.3);
    this.snd.hit(); this.hm = 0.25; this.hmKill = false;
  }
  kill(a) { this.snd.kill(); this.hm = 0.4; this.hmKill = true; }
  enemyFire(a, hitMe) {
    const p = this.g.player, dx = a.pos.x - p.pos.x, dz = a.pos.z - p.pos.z, d = Math.hypot(dx, dz);
    const ang = Math.atan2(-dx, -dz) - p.yaw, pan = Math.max(-1, Math.min(1, -Math.sin(ang)));
    this.snd.enemyShot(d, pan);
    if (hitMe) { this.snd.hurt(); this.dmg.push({ ang, life: 1.2 }); }
    else if (Math.random() < 0.5) this.snd.whiz(pan);
  }
  update(dt) {
    for (let q = 0; q < this.N; q++) {
      if (this.pl[q] <= 0) continue;
      this.pl[q] -= dt;
      if (this.pl[q] <= 0) continue;
      this.pv[q * 3 + 1] -= 9.8 * dt;
      for (let c = 0; c < 3; c++) this.pp[q * 3 + c] += this.pv[q * 3 + c] * dt;
      for (let c = 0; c < 3; c++) this.pc[q * 3 + c] *= Math.exp(-dt * 3);
    }
    let n = 0;
    for (let q = 0; q < this.N; q++) { if (this.pl[q] <= 0) continue; for (let c = 0; c < 3; c++) { this.dp[n * 3 + c] = this.pp[q * 3 + c]; this.dc[n * 3 + c] = this.pc[q * 3 + c]; } n++; }
    this.points.geometry.setDrawRange(0, n); this.points.visible = n > 0;
    this.points.geometry.attributes.position.needsUpdate = true; this.points.geometry.attributes.color.needsUpdate = true;
    for (const P of this.puffs) {
      if (!P.s.visible) continue;
      P.life -= dt; const k = Math.max(0, P.life / P.life0);
      P.s.material.opacity = 0.7 * k; P.s.scale.setScalar(P.size * (1 + (1 - k) * 2)); P.s.position.y += dt * 0.15;
      if (P.life <= 0) P.s.visible = false;
    }
    this.hm = Math.max(0, this.hm - dt);
    for (const d of this.dmg) d.life -= dt; this.dmg = this.dmg.filter((d) => d.life > 0);
    // heartbeat when badly hurt
    const p = this.g.player;
    if (p.hp < 35 && p.hp > 0) { this.heartT -= dt; if (this.heartT <= 0) { this.snd.heart(0); this.heartT = 0.75; } }
    // the sea when outside
    const P = this.g.G.P, r = P.roomAt(p.L, P.ci(p.pos.x), P.ck(p.pos.z));
    this.snd.setOutdoor(r >= 0 && P.ROOMS[r].outdoor ? 1 : 0);
  }
}

// Halcyon's sound, synthesised with WebAudio (no sample files): pistol shots with a room tail,
// distant gunfire, footsteps by surface, reloads, hit and kill ticks, the security doors, the
// power failing and coming back, the hotel's room tone and the sea outside, a heartbeat when hurt.
export class Sound {
  constructor() { this.ctx = null; this.on = false; }
  start() {
    if (this.ctx) { this.ctx.resume(); return; }
    const C = this.ctx = new (window.AudioContext || window.webkitAudioContext)();
    this.master = C.createGain(); this.master.gain.value = 0.8;
    const comp = C.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 4;
    this.master.connect(comp).connect(C.destination);
    // a hall reverb from a synthesised impulse (decaying filtered noise)
    this.verb = C.createConvolver(); this.verb.buffer = this.impulse(2.4, 2.2);
    this.verbIn = C.createGain(); this.verbIn.gain.value = 0.45;
    this.verbIn.connect(this.verb).connect(this.master);
    this.noise = this.noiseBuf(2);
    // room tone + the sea (filtered noise with a slow swell)
    const tone = C.createBufferSource(); tone.buffer = this.noise; tone.loop = true;
    const lp = C.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 380;
    this.amb = C.createGain(); this.amb.gain.value = 0.05;
    tone.connect(lp).connect(this.amb).connect(this.master); tone.start();
    const sea = C.createBufferSource(); sea.buffer = this.noise; sea.loop = true; sea.playbackRate.value = 0.7;
    const bp = C.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 520; bp.Q.value = 0.4;
    this.seaG = C.createGain(); this.seaG.gain.value = 0.0;
    const lfo = C.createOscillator(), lg = C.createGain(); lfo.frequency.value = 0.09; lg.gain.value = 0.025; lfo.connect(lg).connect(this.seaG.gain); lfo.start();
    sea.connect(bp).connect(this.seaG).connect(this.master); sea.start();
    // mains hum (goes with the power)
    const hum = C.createOscillator(); hum.frequency.value = 50; const hum2 = C.createOscillator(); hum2.frequency.value = 100;
    this.humG = C.createGain(); this.humG.gain.value = 0.012; hum.connect(this.humG); hum2.connect(this.humG); this.humG.connect(this.master); hum.start(); hum2.start();
    this.on = true;
  }
  noiseBuf(sec) {
    const C = this.ctx, b = C.createBuffer(1, C.sampleRate * sec, C.sampleRate), d = b.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    return b;
  }
  impulse(sec, decay) {
    const C = this.ctx, n = C.sampleRate * sec, b = C.createBuffer(2, n, C.sampleRate);
    for (let ch = 0; ch < 2; ch++) { const d = b.getChannelData(ch); let lp = 0; for (let i = 0; i < n; i++) { lp = lp * 0.6 + (Math.random() * 2 - 1) * 0.4; d[i] = lp * Math.pow(1 - i / n, decay); } }
    return b;
  }
  burst({ t = 0, dur = 0.1, f = 1000, q = 1, type = 'bandpass', gain = 0.5, verb = 0.3, attack = 0.001, pan = 0, rate = 1, sweep = 0 }) {
    if (!this.on) return;
    const C = this.ctx, now = C.currentTime + t;
    const s = C.createBufferSource(); s.buffer = this.noise; s.playbackRate.value = rate;
    const fl = C.createBiquadFilter(); fl.type = type; fl.frequency.setValueAtTime(f, now); fl.Q.value = q;
    if (sweep) fl.frequency.exponentialRampToValueAtTime(Math.max(40, f * sweep), now + dur);
    const g = C.createGain(); g.gain.setValueAtTime(0.0001, now); g.gain.exponentialRampToValueAtTime(gain, now + attack); g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
    const pn = C.createStereoPanner ? C.createStereoPanner() : null;
    let out = s.connect(fl).connect(g); if (pn) { pn.pan.value = pan; out = out.connect(pn); }
    out.connect(this.master); if (verb) { const v = C.createGain(); v.gain.value = verb; out.connect(v).connect(this.verbIn); }
    s.start(now, Math.random()); s.stop(now + dur + 0.05);
  }
  thump({ t = 0, f = 120, f2 = 45, dur = 0.18, gain = 0.6, verb = 0.2 }) {
    if (!this.on) return;
    const C = this.ctx, now = C.currentTime + t, o = C.createOscillator(), g = C.createGain();
    o.frequency.setValueAtTime(f, now); o.frequency.exponentialRampToValueAtTime(f2, now + dur);
    g.gain.setValueAtTime(gain, now); g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
    o.connect(g).connect(this.master); if (verb) { const v = C.createGain(); v.gain.value = verb; g.connect(v).connect(this.verbIn); }
    o.start(now); o.stop(now + dur + 0.02);
  }
  shot(enclosed = 1) {   // the player's pistol: crack, body, tail
    this.burst({ dur: 0.05, f: 3200, q: 0.7, gain: 0.9, verb: 0.5 * enclosed, type: 'highpass' });
    this.burst({ dur: 0.22, f: 900, q: 0.9, gain: 0.7, verb: 0.9 * enclosed, sweep: 0.3 });
    this.thump({ f: 150, f2: 40, dur: 0.16, gain: 0.8, verb: 0.4 * enclosed });
    this.burst({ t: 0.09, dur: 0.05, f: 4200, q: 6, gain: 0.05, verb: 0 });   // slide
  }
  enemyShot(dist, pan) {
    const g = Math.min(0.7, 3.5 / (1 + dist * 0.25));
    this.burst({ dur: 0.18, f: 1400 / (1 + dist * 0.04), q: 0.7, gain: g, verb: 0.9, pan, sweep: 0.4 });
    this.thump({ f: 110, f2: 40, dur: 0.14, gain: g * 0.7, verb: 0.5 });
  }
  whiz(pan) { this.burst({ dur: 0.12, f: 2600, q: 8, gain: 0.12, verb: 0, pan, sweep: 0.5 }); }
  step(surface, run) {
    const soft = surface === 'carpet', g = (soft ? 0.05 : 0.12) * (run ? 1.4 : 1);
    this.burst({ dur: soft ? 0.07 : 0.05, f: soft ? 300 : 1800, q: soft ? 0.6 : 1.4, gain: g, verb: soft ? 0.05 : 0.25, type: soft ? 'lowpass' : 'bandpass' });
    if (!soft) this.thump({ f: 90, f2: 50, dur: 0.05, gain: g * 0.6, verb: 0 });
  }
  reload() { this.burst({ dur: 0.04, f: 3000, q: 5, gain: 0.15, verb: 0.1 }); this.burst({ t: 0.55, dur: 0.05, f: 2200, q: 5, gain: 0.2, verb: 0.1 }); this.burst({ t: 1.2, dur: 0.06, f: 3600, q: 4, gain: 0.22, verb: 0.15 }); }
  empty() { this.burst({ dur: 0.03, f: 4500, q: 8, gain: 0.12, verb: 0 }); }
  hit() { this.burst({ dur: 0.04, f: 5200, q: 10, gain: 0.12, verb: 0 }); }
  kill() { this.burst({ dur: 0.06, f: 3800, q: 10, gain: 0.18, verb: 0 }); this.burst({ t: 0.07, dur: 0.08, f: 2600, q: 10, gain: 0.14, verb: 0 }); }
  hurt() { this.thump({ f: 70, f2: 35, dur: 0.25, gain: 0.7, verb: 0 }); }
  door(dist, closing) {   // a steel shutter running down (or up) its guides
    const g = Math.min(0.5, 2.5 / (1 + dist * 0.3));
    this.burst({ dur: 0.7, f: closing ? 700 : 500, q: 2, gain: g * 0.5, verb: 0.6, sweep: closing ? 0.5 : 1.6, attack: 0.05 });
    if (closing) this.thump({ t: 0.65, f: 80, f2: 35, dur: 0.3, gain: g, verb: 0.6 });
  }
  powerDown() { if (!this.on) return; this.thump({ f: 160, f2: 30, dur: 1.2, gain: 0.5, verb: 0.8 }); this.humG.gain.setTargetAtTime(0, this.ctx.currentTime, 0.3); }
  powerUp() { if (!this.on) return; this.burst({ dur: 0.3, f: 120, q: 2, gain: 0.3, verb: 0.4, type: 'lowpass' }); this.humG.gain.setTargetAtTime(0.012, this.ctx.currentTime, 0.4); }
  pickup() { this.burst({ dur: 0.1, f: 1500, q: 3, gain: 0.15, verb: 0.2 }); }
  heart(t) { this.thump({ t, f: 60, f2: 40, dur: 0.12, gain: 0.35, verb: 0 }); this.thump({ t: t + 0.18, f: 55, f2: 38, dur: 0.12, gain: 0.25, verb: 0 }); }
  setOutdoor(k) { if (!this.on) return; this.seaG.gain.setTargetAtTime(0.02 + 0.07 * k, this.ctx.currentTime, 0.5); this.verbIn.gain.setTargetAtTime(0.45 * (1 - 0.7 * k), this.ctx.currentTime, 0.5); }
}

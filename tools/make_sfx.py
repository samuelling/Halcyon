"""Synthesises Halcyon's sound effects to assets/sfx/*.wav (mono, 44.1 kHz, 16 bit). Run: python3 tools/make_sfx.py
Everything is made here from noise and sines, so the sounds are the project's own (CC0)."""
import numpy as np, wave, os
SR = 44100
rng = np.random.default_rng(7)
out = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx'); os.makedirs(out, exist_ok=True)
t_ = lambda d: np.arange(int(SR * d)) / SR
noise = lambda d: rng.standard_normal(int(SR * d))
env = lambda d, a: np.exp(-t_(d) * a)
def lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR); y = np.empty_like(x); z = 0.0
    for i in range(len(x)): z = a * z + (1 - a) * x[i]; y[i] = z
    return y
def hp(x, fc): return x - lp(x, fc)
def bp(x, lo, hi): return lp(hp(x, lo), hi)
def reverb(x, d=0.6, mix=0.3, seed=1):
    r = np.random.default_rng(seed); n = int(SR * d); x = np.asarray(x, dtype=np.float64)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.0 / d)); ir = lp(ir, 5000)
    y = np.convolve(x, ir) * 0.05
    z = np.zeros(len(y)); z[: len(x)] = x
    return z * (1 - mix) + y * mix
def save(name, x, peak=0.9, loop=False):
    x = np.asarray(x, dtype=np.float64)
    if loop:   # crossfade the ends so it loops cleanly
        n = int(SR * 0.5); f = np.linspace(0, 1, n); x[:n] = x[:n] * f + x[-n:] * (1 - f); x = x[:-n]
    x = x / (np.abs(x).max() + 1e-9) * peak
    with wave.open(os.path.join(out, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype('<i2').tobytes())
def shot(seed, tail):
    r = np.random.default_rng(seed); d = 0.5
    crack = hp(r.standard_normal(int(SR * d)), 900) * env(d, 38)
    body = lp(r.standard_normal(int(SR * d)), 420) * env(d, 14) * 2.2
    thump = np.sin(2 * np.pi * (150 * np.exp(-t_(d) * 20) + 45) * t_(d)) * env(d, 16) * 1.6
    mech = bp(r.standard_normal(int(SR * d)), 2500, 6000) * env(d, 60) * np.roll((t_(d) > 0.06) * 1.0, 0) * 0.5
    x = np.tanh((crack + body + thump + mech) * 1.6)
    return reverb(x, tail, 0.34, seed)
save('shot', shot(1, 0.9)); save('shot_out', shot(2, 0.35)); save('shot_enemy', lp(shot(3, 1.1), 3200))
# reload: mag out, mag in, slide
x = np.zeros(int(SR * 1.5))
def click_at(x, t0, f, a, dur=0.05, seed=0):
    r = np.random.default_rng(seed); n = int(SR * dur); c = bp(r.standard_normal(n), f * 0.6, f * 1.6) * np.exp(-np.arange(n) / SR * a)
    c += np.sin(2 * np.pi * f * np.arange(n) / SR) * np.exp(-np.arange(n) / SR * a * 1.5) * 0.4
    i = int(SR * t0); x[i:i + n] += c
click_at(x, 0.12, 1800, 60, 0.06, 1); click_at(x, 0.20, 700, 40, 0.08, 2); click_at(x, 0.78, 900, 45, 0.08, 3); click_at(x, 0.84, 2200, 70, 0.05, 4)
click_at(x, 1.18, 1500, 50, 0.07, 5); click_at(x, 1.27, 2600, 60, 0.07, 6)
save('reload', x, 0.7)
x = np.zeros(int(SR * 0.15)); click_at(x, 0.0, 2400, 90, 0.05, 8); save('empty', x, 0.5)
x = np.zeros(int(SR * 0.1)); click_at(x, 0.0, 3200, 120, 0.04, 9); save('click', x, 0.4)
for i in range(3):
    r = np.random.default_rng(20 + i)
    d = 0.16; save(f'step_hard{i}', (bp(r.standard_normal(int(SR * d)), 300, 2600) * env(d, 55) + np.sin(2 * np.pi * 95 * t_(d)) * env(d, 45) * 0.8), 0.5)
    d = 0.2; save(f'step_carpet{i}', lp(r.standard_normal(int(SR * d)), 500) * env(d, 30), 0.35)
    d = 0.2; save(f'step_wood{i}', (bp(r.standard_normal(int(SR * d)), 150, 1400) * env(d, 40) + np.sin(2 * np.pi * (140 + 20 * i) * t_(d)) * env(d, 30)), 0.5)
d = 0.25; save('hit', lp(noise(d), 700) * env(d, 28) + np.sin(2 * np.pi * 80 * t_(d)) * env(d, 30), 0.7)
d = 0.2; save('impact', reverb(hp(noise(d), 1500) * env(d, 70) + lp(noise(d), 500) * env(d, 40), 0.25, 0.25, 4), 0.6)
d = 0.5; save('glass', sum(np.sin(2 * np.pi * f * t_(d)) * env(d, a) for f, a in [(3100, 18), (4300, 25), (5200, 30), (6900, 40)]) + hp(noise(d), 4000) * env(d, 30) * 2, 0.5)
d = 0.5; save('metal', sum(np.sin(2 * np.pi * f * t_(d)) * env(d, a) for f, a in [(1240, 12), (2710, 16), (3950, 22)]) + hp(noise(d), 2500) * env(d, 80), 0.5)
d = 0.12; save('whiz', bp(noise(d), 1800, 5200) * np.sin(np.pi * t_(d) / d) ** 2, 0.45)
d = 1.1; servo = np.sin(2 * np.pi * np.cumsum(180 + 260 * np.minimum(1, t_(d) / 0.7)) / SR) * (t_(d) < 0.75) * 0.35 + bp(noise(d), 500, 2500) * (t_(d) < 0.75) * 0.15
x = servo.copy(); click_at(x, 0.76, 300, 25, 0.25, 11); save('door', reverb(x, 0.6, 0.3, 5), 0.7)
d = 1.6; save('power_down', reverb(np.sin(2 * np.pi * np.cumsum(220 * np.exp(-t_(d) * 2.2) + 30) / SR) * env(d, 1.5) + lp(noise(d), 200) * env(d, 3) * 0.8, 1.0, 0.4, 6), 0.8)
d = 1.2; save('power_up', reverb(np.sin(2 * np.pi * np.cumsum(60 + 300 * (1 - np.exp(-t_(d) * 3))) / SR) * np.minimum(1, t_(d) * 4) * env(d, 2.2) + (t_(d) > 0.5) * hp(noise(d), 3000) * np.exp(-np.maximum(0, t_(d) - 0.5) * 30) * 0.4, 0.8, 0.35, 7), 0.6)
def chime(fs, d=0.9, gap=0.1):
    x = np.zeros(int(SR * (d + gap * len(fs))))
    for n, f in enumerate(fs):
        i = int(SR * gap * n); m = int(SR * d); x[i:i + m] += (np.sin(2 * np.pi * f * t_(d)) + 0.3 * np.sin(2 * np.pi * 2 * f * t_(d))) * env(d, 5)
    return reverb(x, 0.8, 0.3, 8)
save('pickup', chime([660, 880]), 0.45); save('clear', chime([523, 659, 784]), 0.45); save('rescued', chime([523, 659, 784, 1047], 1.2, 0.13), 0.5)
d = 1.4; save('ambush', reverb((np.sin(2 * np.pi * 73 * t_(d)) + np.sin(2 * np.pi * 77.5 * t_(d)) + 0.6 * np.sign(np.sin(2 * np.pi * 110 * t_(d)))) * np.minimum(1, t_(d) * 30) * env(d, 2.5), 1.0, 0.35, 9), 0.7)
d = 0.35; save('hurt', lp(noise(d), 900) * env(d, 16) + np.sin(2 * np.pi * 110 * t_(d)) * env(d, 14), 0.7)
d = 1.5; save('death', reverb(np.sin(2 * np.pi * np.cumsum(140 * np.exp(-t_(d) * 1.5) + 35) / SR) * env(d, 1.8), 1.0, 0.4, 10), 0.8)
d = 0.5; save('body', lp(noise(d), 300) * env(d, 12) + np.sin(2 * np.pi * 60 * t_(d)) * env(d, 14), 0.6)
d = 0.9; hb = np.zeros(int(SR * d))
for t0 in (0.0, 0.28): 
    n = int(SR * 0.2); i = int(SR * t0); hb[i:i + n] += np.sin(2 * np.pi * 52 * np.arange(n) / SR) * np.exp(-np.arange(n) / SR * 22)
save('heart', hb, 0.8)
# loops
d = 8.0; hum = sum(np.sin(2 * np.pi * f * t_(d)) * a for f, a in [(50, 0.5), (100, 0.25), (150, 0.1), (201, 0.05)]) + lp(noise(d), 300) * 0.6 + bp(noise(d), 800, 3000) * 0.04
save('room', hum, 0.25, loop=True)
d = 12.0; sw = 0.55 + 0.45 * np.sin(2 * np.pi * t_(d) / 6.0 - 1.0) ** 2; sea = lp(noise(d), 900) * sw + bp(noise(d), 1500, 5000) * sw ** 3 * 0.35 + lp(noise(d), 120) * 0.8
save('sea', sea, 0.5, loop=True)
d = 8.0; dr = sum(np.sin(2 * np.pi * f * t_(d) + p) for f, p in [(55, 0), (55.7, 1), (82.4, 2), (110.3, 3)]) * (0.8 + 0.2 * np.sin(2 * np.pi * t_(d) / 4)) + lp(noise(d), 150)
save('drone', dr, 0.5, loop=True)
print(sorted(os.listdir(out)))

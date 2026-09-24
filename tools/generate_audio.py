# Procedural sound generator for the VR survival world (stdlib only).
# Re-run from the project root: python3 tools/generate_audio.py
import wave, struct, math, random, os
SR = 22050
random.seed(7)
OUT = 'assets/audio'
os.makedirs(OUT, exist_ok=True)
def write(name, s, peak_to=0.8):
    peak = max(1e-6, max(abs(x) for x in s)); g = peak_to / peak
    with wave.open(f'{OUT}/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, x * g)) * 32767)) for x in s))
def lp(s, a):
    y = 0.0; o = []
    for x in s:
        y += a * (x - y); o.append(y)
    return o
def noise(n): return [random.uniform(-1, 1) for _ in range(n)]
def loopify(s, fade):
    n = len(s) - fade; out = s[:n]
    for i in range(fade):
        a = i / fade; out[i] = out[i] * a + s[n + i] * (1 - a)
    return out
def silence(sec): return [0.0] * int(sec * SR)
def add(dst, src, at):
    for i, x in enumerate(src):
        j = at + i
        if 0 <= j < len(dst): dst[j] += x
# wind: brown noise + slow gusts + faint whistle
n = 17 * SR; w = noise(n); low = lp(lp(w, 0.02), 0.05); band = [a - b for a, b in zip(lp(w, 0.12), lp(w, 0.04))]
wind = []
for i in range(n):
    t = i / SR; m = 0.55 + 0.25 * math.sin(2 * math.pi * t / 8.5) + 0.2 * math.sin(2 * math.pi * t / 3.1 + 1)
    wind.append(low[i] * 6 * m + band[i] * 0.35 * m * m)
write('wind', loopify(wind, SR))
# river: band noise, low rumble, bubbling blips
n = 11 * SR; w = noise(n); band = [a - b for a, b in zip(lp(w, 0.35), lp(w, 0.06))]; low = lp(w, 0.03)
river = [band[i] * 0.6 + low[i] * 2.2 for i in range(n)]
for _ in range(160):
    at = random.randrange(n); f = random.uniform(280, 750); d = random.uniform(0.02, 0.07); a = random.uniform(0.05, 0.18)
    add(river, [a * math.sin(2 * math.pi * (f + 900 * k / SR) * k / SR) * math.sin(math.pi * k / (d * SR)) for k in range(int(d * SR))], at)
write('river', loopify(river, SR // 2))
# rain: hiss + droplets
n = 10 * SR; w = noise(n); lw = lp(w, 0.2); rain = [(w[i] - lw[i]) * 0.35 + lw[i] * 0.4 for i in range(n)]
for _ in range(900):
    at = random.randrange(n); a = random.uniform(0.1, 0.5)
    add(rain, [a * random.uniform(-1, 1) * math.exp(-k / 40) for k in range(120)], at)
write('rain', loopify(rain, SR // 2))
# birds: short melodic chirp phrases
n = 22 * SR; birds = [0.0] * n
for _ in range(10):
    at = random.randrange(int(n * 0.9)); base = random.uniform(2200, 3800); amp = random.uniform(0.35, 1.0)
    for _ in range(random.randint(2, 5)):
        d = random.uniform(0.06, 0.18); f0 = base * random.uniform(0.85, 1.15); f1 = f0 * random.uniform(0.7, 1.4); ph = 0.0; note = []
        for k in range(int(d * SR)):
            t = k / SR; f = f0 + (f1 - f0) * t / d + 60 * math.sin(2 * math.pi * 32 * t); ph += 2 * math.pi * f / SR
            note.append(amp * math.sin(ph) * math.sin(math.pi * t / d) ** 2)
        add(birds, note, at); at += int((d + random.uniform(0.04, 0.12)) * SR)
write('birds', birds, 0.6)
# crickets: pulse trains of two insects
n = 10 * SR; cr = [0.0] * n
for f, off, amp in [(4600, 0.0, 1.0), (4280, 0.45, 0.6)]:
    t0 = off
    while t0 < 9.6:
        for p in range(3):
            s = int((t0 + p * 0.045) * SR)
            add(cr, [amp * math.sin(2 * math.pi * f * k / SR) * math.sin(math.pi * k / (0.025 * SR)) for k in range(int(0.025 * SR))], s)
        t0 += random.uniform(0.8, 1.3)
write('crickets', loopify(cr, SR // 4), 0.5)
# fire: rumble + hiss + crackles
n = 9 * SR; w = noise(n); rum = lp(w, 0.01); lw = lp(w, 0.3); fire = [rum[i] * 3.5 + (w[i] - lw[i]) * 0.04 for i in range(n)]
for _ in range(110):
    at = random.randrange(n); a = random.uniform(0.15, 0.9); L = random.randint(150, 900)
    add(fire, [a * random.uniform(-1, 1) * math.exp(-k / (L / 5)) for k in range(L)], at)
write('fire', loopify(fire, SR // 2))
# one-shots
def env_sig(sec, fn): return [fn(k / SR) for k in range(int(sec * SR))]
nz = noise(SR * 4); nzl = lp(nz, 0.3); nzvl = lp(nz, 0.08)
write('chop', env_sig(0.45, lambda t: math.sin(2 * math.pi * 95 * t) * math.exp(-t * 18) + nzl[int(t * SR)] * 2.5 * math.exp(-t * 40) + 0.4 * math.sin(2 * math.pi * 420 * t) * math.exp(-t * 30)))
write('pick', env_sig(0.5, lambda t: sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t * d) for f, a, d in [(1850, 1, 9), (2790, .6, 12), (4130, .4, 15), (5400, .25, 20)]) + nz[int(t * SR)] * math.exp(-t * 300)))
write('pickup', env_sig(0.18, lambda t: math.sin(2 * math.pi * (520 * t + 1000 * t * t)) * math.sin(math.pi * t / 0.18)), 0.5)
fall = []; ph = 0.0
for k in range(int(3.2 * SR)):
    t = k / SR; v = 0.0
    if t < 1.45:
        ph += (70 + 30 * math.sin(2 * math.pi * 0.7 * t) + random.uniform(-8, 8)) / SR
        v += ((ph % 1.0) * 2 - 1) * 0.25 * (t / 1.45) ** 1.5
    if 1.35 <= t < 1.6: v += nz[k] * 0.9 * math.exp(-(t - 1.35) * 25)
    if t >= 1.6: v += nzvl[k] * 5.0 * math.exp(-(t - 1.6) * 2.2) + math.sin(2 * math.pi * 55 * t) * math.exp(-(t - 1.6) * 6) + nz[k] * 0.12 * math.exp(-(t - 1.6) * 1.5)
    fall.append(v)
write('tree_fall', lp(fall, 0.5))
print('generated:', sorted(os.listdir(OUT)))


# --- Foley (door, footsteps) and seamless loop crossfades -------------------
def _foley_write(name, data, sr=SR):
    peak = max(1e-6, max(abs(x) for x in data))
    g = 0.85 / peak
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, x * g)) * 32767)) for x in data))

def _lp(data, a):
    out, y = [], 0.0
    for x in data:
        y += a * (x - y)
        out.append(y)
    return out

def _edges(data, sr=SR, fin=0.003, fout=0.02):
    n = len(data)
    a, b = max(1, int(sr * fin)), max(1, int(sr * fout))
    for i in range(min(a, n)):
        data[i] *= i / a
    for i in range(min(b, n)):
        data[n - 1 - i] *= i / b
    return data

def generate_foley():
    rnd = random.Random(7)
    # Door: short latch click, then a slow wooden creak.
    n = int(SR * 0.9)
    noise = _lp([rnd.uniform(-1, 1) for _ in range(n)], 0.3)
    door, phase = [], 0.0
    for i in range(n):
        t = i / SR
        latch = math.exp(-t / 0.008) * noise[i] * 1.2 if t < 0.05 else 0.0
        ct = t - 0.06
        creak = 0.0
        if 0.0 < ct < 0.75:
            f = 150 + 55 * math.sin(2 * math.pi * 1.4 * ct) + rnd.uniform(-8, 8)
            phase += f / SR
            pulse = 1.0 if (phase % 1.0) < 0.07 else 0.0
            env = math.sin(math.pi * ct / 0.75) ** 0.7
            creak = (0.35 * math.sin(2 * math.pi * phase) + 0.65 * pulse) * env * 0.5
        door.append(latch + creak)
    door = _lp(door, 0.35)
    _foley_write('door', _edges(door))
    # Grass step: soft band-limited rustle.
    n = int(SR * 0.24)
    raw = [rnd.uniform(-1, 1) for _ in range(n)]
    hi, lo = _lp(raw, 0.4), _lp(raw, 0.04)
    grass = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.012) * math.exp(-t / 0.06) + 0.4 * math.exp(-max(0.0, t - 0.06) / 0.04) * (t > 0.06)
        grass.append((hi[i] - lo[i]) * env)
    _foley_write('step_grass', _edges(grass))
    # Wood step: dull thump on floor boards.
    n = int(SR * 0.2)
    click = _lp([rnd.uniform(-1, 1) for _ in range(n)], 0.5)
    wood = []
    for i in range(n):
        t = i / SR
        wood.append(math.sin(2 * math.pi * 95 * t) * math.exp(-t / 0.035)
                    + 0.5 * math.sin(2 * math.pi * 210 * t) * math.exp(-t / 0.02)
                    + 0.6 * click[i] * math.exp(-t / 0.006))
    _foley_write('step_wood', _edges(wood))

def make_seamless(name, fade=0.3):
    path = os.path.join(OUT, name + '.wav')
    if not os.path.exists(path):
        return
    with wave.open(path, 'rb') as f:
        ch, sw, fr, n = f.getnchannels(), f.getsampwidth(), f.getframerate(), f.getnframes()
        raw = f.readframes(n)
    if sw != 2:
        return
    s = struct.unpack('<%dh' % (n * ch), raw)
    fl = int(fr * fade)
    if n < fl * 3:
        return
    out = list(s[:(n - fl) * ch])
    for i in range(fl):
        w = i / fl
        a, b = math.sqrt(1.0 - w), math.sqrt(w)
        for c in range(ch):
            v = s[(n - fl + i) * ch + c] * a + s[i * ch + c] * b
            out[i * ch + c] = int(max(-32768, min(32767, v)))
    with wave.open(path, 'wb') as f:
        f.setnchannels(ch)
        f.setsampwidth(2)
        f.setframerate(fr)
        f.writeframes(struct.pack('<%dh' % len(out), *out))

generate_foley()
for _loop in ('wind', 'birds', 'crickets', 'rain', 'river', 'fire'):
    make_seamless(_loop)

extends RefCounted
## Sound synthesis modelled on how the real things make sound.
##   Voices and animal calls: a glottal pulse train (pitch, jitter, breath) shaped by vocal-tract
##   resonances (formants) that glide as the mouth opens and closes - so a cow moos "mm-oo", a
##   sheep bleats with a tremolo, a wolf howls through an "oo".
##   Nature: rain from thousands of individual drops over a hiss, a brook from bubbles over a rush,
##   fire from clustered crackles and snaps over a low roar, birdsong as phrases of gliding notes,
##   crickets as pulsed chirps, waves that wash in, break and fizz out.
## make(name, variant) returns mono samples at RATE, or an empty array for names it doesn't make.

const RATE := 22050
var rng: RandomNumberGenerator


func _init(r: RandomNumberGenerator) -> void:
	rng = r


func make(n: String, v: int) -> PackedFloat32Array:
	match n:
		"swing": return _swing(v)
		"grunt_m", "grunt_f": return _grunt(n == "grunt_f", v)
		"death_m", "death_f": return _death(n == "death_f", v)
		"voice_m", "voice_f": return _babble((112.0 if n == "voice_m" else 205.0) + v * 12.0, 1.1)
		"howl": return _howl(v)
		"growl": return _growl(v, false)
		"roar": return _growl(v, true)
		"bite": return _bite(v)
		"neigh": return _neigh(v)
		"snort": return _snort(v)
		"cow": return _cow(v)
		"sheep": return _sheep(v)
		"pig": return _pig(v)
		"hen": return _hen(v)
		"dog": return _dog(v)
		"donkey": return _donkey(v)
		"alpaca": return _alpaca(v)
		"quack": return _quack(v)
		"honk": return _honk(v)
		"caw": return _caw(v)
		"gull_cry": return _gull(v)
		"screech": return _screech(v)
		"drink": return _drink(v)
		"eat": return _eat(v)
		"step_water": return _splash(v)
		"thunder": return _thunder(v)
		"amb_wind": return _wind()
		"amb_rain": return _rain()
		"amb_forest": return _forest()
		"amb_night": return _night()
		"amb_river": return _river()
		"amb_fire": return _fire()
		"amb_tavern": return _tavern()
		"amb_ocean": return _ocean()
	return PackedFloat32Array()


# ------------------------------------------------------------------ building blocks
func _buf(secs: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(secs * RATE))
	return b


static func _ar(t: float, att: float, rel: float, total: float) -> float:
	return clampf(t / maxf(att, 0.0001), 0.0, 1.0) * clampf((total - t) / maxf(rel, 0.0001), 0.0, 1.0)


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, at: float, gain := 1.0) -> void:
	var s := int(at * RATE)
	for i in b.size():
		var j := s + i
		if j >= a.size():
			break
		if j >= 0:
			a[j] += b[i] * gain


## Wraps a loop's tail onto its head so it repeats without a seam.
func _loop(x: PackedFloat32Array, secs: float) -> void:
	var n := mini(int(secs * RATE), x.size() / 3)
	var L := x.size()
	for i in n:
		var t := float(i) / n
		x[i] = x[i] * t + x[L - n + i] * (1.0 - t)
	x.resize(L - n)


## A voiced call: glottal pulses at pitch f0(t) through formants vowel(t) -> [[Hz, bandwidth, gain]...],
## with breath noise, jitter (roughness) and an amplitude envelope amp(t).
func _voiced(secs: float, f0: Callable, vowel: Callable, amp: Callable, breath := 0.1, jitter := 0.01, open := 0.5) -> PackedFloat32Array:
	var x := _buf(secs)
	var fs: Array = vowel.call(0.0)
	var nf := fs.size()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var g := PackedFloat32Array()
	var x1 := PackedFloat32Array()
	var x2 := PackedFloat32Array()
	var y1 := PackedFloat32Array()
	var y2 := PackedFloat32Array()
	for arr in [c0, c1, c2, g, x1, x2, y1, y2]:
		arr.resize(nf)
	var ph := 0.0
	var prev := 0.0
	var jit := 0.0
	var f := 100.0
	var a := 0.0
	var da := 0.0
	var df := 0.0
	for i in x.size():
		if i % 32 == 0:
			var t := float(i) / RATE
			var f_next := float(f0.call(t + 32.0 / RATE))
			var a_next := float(amp.call(t + 32.0 / RATE))
			if i == 0:
				f = float(f0.call(0.0))
				a = float(amp.call(0.0))
			df = (f_next - f) / 32.0
			da = (a_next - a) / 32.0
			jit = jit * 0.6 + rng.randf_range(-1.0, 1.0) * jitter
			fs = vowel.call(t)
			for k in nf:
				var w0 := TAU * clampf(float(fs[k][0]), 40.0, RATE * 0.45) / RATE
				var alpha := sin(w0) / (2.0 * maxf(float(fs[k][0]) / float(fs[k][1]), 0.4))
				var a0 := 1.0 + alpha
				c0[k] = alpha / a0
				c1[k] = -2.0 * cos(w0) / a0
				c2[k] = (1.0 - alpha) / a0
				g[k] = float(fs[k][2])
		f += df
		a += da
		ph += f * (1.0 + jit) / RATE
		if ph >= 1.0:
			ph -= 1.0
		var pulse := 0.0
		if ph < open:
			var s := sin(PI * ph / open)
			pulse = s * s
		var src := (pulse - prev) * 6.0 + rng.randf_range(-1.0, 1.0) * breath
		prev = pulse
		var out := 0.0
		for k in nf:
			var y := c0[k] * (src - x2[k]) - c1[k] * y1[k] - c2[k] * y2[k]
			x2[k] = x1[k]
			x1[k] = src
			y2[k] = y1[k]
			y1[k] = y
			out += y * g[k]
		x[i] = out * a
	return x


## Noise through a band-pass whose centre follows fc(t) (Hz) and level amp(t).
func _swept_noise(secs: float, fc: Callable, q: float, amp: Callable) -> PackedFloat32Array:
	var x := _buf(secs)
	var c0 := 0.0
	var c1 := 0.0
	var c2 := 0.0
	var a := 0.0
	var xa := 0.0
	var xb := 0.0
	var ya := 0.0
	var yb := 0.0
	for i in x.size():
		if i % 32 == 0:
			var t := float(i) / RATE
			var w0 := TAU * clampf(float(fc.call(t)), 30.0, RATE * 0.45) / RATE
			var alpha := sin(w0) / (2.0 * q)
			var a0 := 1.0 + alpha
			c0 = alpha / a0
			c1 = -2.0 * cos(w0) / a0
			c2 = (1.0 - alpha) / a0
			a = float(amp.call(t))
		var s := rng.randf_range(-1.0, 1.0)
		var y := c0 * (s - xb) - c1 * ya - c2 * yb
		xb = xa
		xa = s
		yb = ya
		ya = y
		x[i] = y * a
	return x


func _lowpass(x: PackedFloat32Array, f: float) -> void:
	var k := 1.0 - exp(-TAU * f / RATE)
	var y := 0.0
	for i in x.size():
		y += (x[i] - y) * k
		x[i] = y


func _brown(secs: float, f: float) -> PackedFloat32Array:
	var x := _buf(secs)
	var b := 0.0
	for i in x.size():
		b = b * 0.995 + rng.randf_range(-1.0, 1.0) * 0.08
		x[i] = b
	_lowpass(x, f)
	return x


## A slow random level between lo and hi (gusts, swells), one value per sample.
func _drift(secs: float, rate: float, lo: float, hi: float) -> PackedFloat32Array:
	var x := _buf(secs)
	var v := 0.5
	var target := rng.randf()
	for i in x.size():
		if i % int(RATE / rate) == 0:
			target = rng.randf()
		v += (target - v) * (rate * 2.0 / RATE)
		x[i] = lerpf(lo, hi, v)
	return x


## A whistled note gliding fa -> fb (with optional vibrato), softly shaped.
func _note(x: PackedFloat32Array, at: float, dur: float, fa: float, fb: float, amp: float, vib := 0.0, vib_rate := 0.0) -> void:
	var s := int(at * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var j := s + i
		if j >= x.size():
			break
		var k := float(i) / n
		var fr := lerpf(fa, fb, k) * (1.0 + vib * sin(TAU * vib_rate * float(i) / RATE))
		ph += TAU * fr / RATE
		var e := sin(PI * k)
		x[j] += (sin(ph) + 0.12 * sin(ph * 2.0)) * e * e * amp


## A short damped tone (drops, bubbles: the pitch rises as a bubble rings).
func _ping(x: PackedFloat32Array, at: float, f: float, decay: float, amp: float, rise := 1.0) -> void:
	var s := int(at * RATE)
	var n := int(decay * 6.0 * RATE)
	var ph := 0.0
	for i in n:
		var j := s + i
		if j >= x.size():
			break
		var t := float(i) / RATE
		ph += TAU * f * (1.0 + (rise - 1.0) * minf(t / (decay * 3.0), 1.0)) / RATE
		x[j] += sin(ph) * exp(-t / decay) * amp


## A click of noise (crackles, twigs), optionally ringing at `ring` Hz.
func _click(x: PackedFloat32Array, at: float, dur: float, amp: float, ring := 0.0) -> void:
	var s := int(at * RATE)
	var n := maxi(int(dur * RATE), 2)
	for i in n:
		var j := s + i
		if j >= x.size():
			break
		var t := float(i) / RATE
		var e := exp(-t / (dur * 0.3))
		x[j] += (rng.randf_range(-1.0, 1.0) + (sin(TAU * ring * t) * 1.5 if ring > 0.0 else 0.0)) * e * amp


# ------------------------------------------------------------------ people
func _swing(v: int) -> PackedFloat32Array:
	# a blade cutting air: a band of turbulence that rises and falls as the edge passes
	var dur := 0.34 + v * 0.04
	var lo := 420.0 - v * 40.0
	var hi := 1900.0 - v * 200.0
	var body := _swept_noise(dur, func(t): return lo + (hi - lo) * pow(sin(PI * clampf(t / dur, 0.0, 1.0)), 1.6), 2.2,
		func(t): return pow(sin(PI * clampf(t / dur, 0.0, 1.0) * 0.95 + 0.05), 3.0))
	var edge := _swept_noise(dur, func(t): return (hi * 2.3) * (0.7 + 0.3 * sin(PI * clampf(t / dur, 0.0, 1.0))), 6.0,
		func(t): return pow(sin(PI * clampf(t / dur, 0.0, 1.0)), 6.0) * 0.35)
	_mix(body, edge, 0.0)
	return body


const VOWELS := {
	"uh": [[640.0, 90.0, 1.0], [1190.0, 110.0, 0.6], [2390.0, 170.0, 0.25]],
	"ah": [[730.0, 90.0, 1.0], [1090.0, 110.0, 0.65], [2440.0, 170.0, 0.25]],
	"oo": [[330.0, 70.0, 1.0], [870.0, 100.0, 0.35], [2240.0, 170.0, 0.12]],
	"eh": [[530.0, 80.0, 1.0], [1840.0, 120.0, 0.5], [2480.0, 170.0, 0.22]],
	"ee": [[280.0, 70.0, 0.8], [2250.0, 140.0, 0.6], [2900.0, 200.0, 0.3]],
	"oh": [[500.0, 80.0, 1.0], [900.0, 100.0, 0.5], [2400.0, 170.0, 0.15]],
}


func _vowel(name: String, scale: float) -> Array:
	var out := []
	for f in VOWELS[name]:
		out.append([f[0] * scale, f[1] * scale, f[2]])
	return out


func _grunt(female: bool, v: int) -> PackedFloat32Array:
	# pain: a sharp, breathy "uh!" from the chest
	var dur := 0.26 + (v % 3) * 0.06
	var p := (215.0 if female else 118.0) * (1.0 + v * 0.04)
	var vw := _vowel(["uh", "ah", "oh", "eh"][v % 4], 1.16 if female else 1.0)
	var x := _voiced(dur, func(t): return p * (1.12 - 0.3 * t / dur), func(_t): return vw,
		func(t): return _ar(t, 0.012, dur * 0.55, dur), 0.32, 0.035, 0.45)
	var huff := _swept_noise(0.09, func(_t): return 1400.0, 0.8, func(t): return exp(-t / 0.03) * 0.5)
	_mix(x, huff, 0.0)
	return x


func _death(female: bool, v: int) -> PackedFloat32Array:
	var dur := 0.95 + v * 0.1
	var p := (205.0 if female else 108.0)
	var s := 1.16 if female else 1.0
	var a := _vowel("ah", s)
	var u := _vowel("uh", s)
	return _voiced(dur, func(t): return p * (1.05 - 0.4 * t / dur), func(t): return _lerp_vowel(a, u, t / dur),
		func(t): return _ar(t, 0.03, dur * 0.7, dur), 0.4, 0.05, 0.4)


func _lerp_vowel(a: Array, b: Array, k: float) -> Array:
	var out := []
	k = clampf(k, 0.0, 1.0)
	for i in a.size():
		out.append([lerpf(a[i][0], b[i][0], k), lerpf(a[i][1], b[i][1], k), lerpf(a[i][2], b[i][2], k)])
	return out


## Murmured speech: syllables with consonant onsets, varied vowels and a falling phrase melody.
func _babble(pitch: float, secs: float) -> PackedFloat32Array:
	var x := _buf(secs)
	var t := 0.04
	var names := ["ah", "eh", "oh", "uh", "ee", "oo"]
	var scale := 1.0 if pitch < 160.0 else 1.16
	while t < secs - 0.2:
		var dur := rng.randf_range(0.09, 0.17)
		var vw := _vowel(names[rng.randi() % names.size()], scale)
		var p0 := pitch * (1.08 - 0.25 * t / secs) * rng.randf_range(0.95, 1.08)
		var syl := _voiced(dur, func(tt): return p0 * (1.0 - 0.06 * tt / dur), func(_tt): return vw,
			func(tt): return _ar(tt, 0.02, 0.04, dur), 0.08, 0.012, 0.5)
		_mix(x, syl, t, 0.8)
		if rng.randf() < 0.55:      # a consonant: "s", "t", "k" bursts of breath
			var c := _swept_noise(0.03, func(_tt): return rng.randf_range(2500.0, 5000.0), 1.5, func(tt): return exp(-tt / 0.012) * 0.3)
			_mix(x, c, t - 0.02)
		t += dur + rng.randf_range(0.01, 0.06) + (0.15 if rng.randf() < 0.12 else 0.0)
	return x


# ------------------------------------------------------------------ beasts
func _howl(v: int) -> PackedFloat32Array:
	var dur := 2.7 + v * 0.3
	var base := 330.0 + v * 30.0
	return _voiced(dur,
		func(t): return base * (1.0 + 0.5 * smoothstep(0.0, 0.5, t) - 0.3 * smoothstep(dur * 0.6, dur, t)) * (1.0 + 0.012 * sin(t * TAU * 5.5)),
		func(t): return [[lerpf(360.0, 560.0, smoothstep(0.0, 0.6, t)), 140.0, 1.0], [lerpf(880.0, 1150.0, smoothstep(0.0, 0.8, t)), 220.0, 0.32], [2600.0, 400.0, 0.06]],
		func(t): return _ar(t, 0.3, 0.8, dur), 0.05, 0.004, 0.45)


func _growl(v: int, bear: bool) -> PackedFloat32Array:
	var dur := (1.8 if bear else 1.2) + v * 0.15
	var p := (48.0 if bear else 74.0) + v * 6.0
	var vw := [[380.0, 260.0, 1.0], [850.0, 320.0, 0.6], [2200.0, 500.0, 0.25]] if bear else [[480.0, 240.0, 1.0], [1100.0, 300.0, 0.55], [2500.0, 500.0, 0.2]]
	var x := _voiced(dur, func(t): return p * (1.0 + 0.25 * sin(t * 2.2) + (0.2 * smoothstep(0.0, 0.3, t) if bear else 0.0)), func(_t): return vw,
		func(t): return _ar(t, 0.12, dur * 0.4, dur) * (0.75 + 0.25 * sin(t * TAU * (19.0 if bear else 26.0))), 1.1 if bear else 0.85, 0.16, 0.3)
	return x


func _bite(_v: int) -> PackedFloat32Array:
	var x := _buf(0.4)
	_click(x, 0.0, 0.012, 1.0, 2600.0)          # the snap of the jaws
	var snarl := _voiced(0.32, func(t): return 165.0 + 40.0 * sin(t * 30.0), func(_t): return [[700.0, 300.0, 1.0], [1600.0, 400.0, 0.5]],
		func(t): return _ar(t, 0.01, 0.16, 0.32), 0.9, 0.14, 0.3)
	_mix(x, snarl, 0.015, 0.7)
	return x


func _neigh(v: int) -> PackedFloat32Array:
	# a whinny: a sharp rise, a long quavering fall, and a low nicker to finish
	var dur := 1.55 + v * 0.1
	var top := 1120.0 + v * 70.0
	var vw := [[950.0, 260.0, 1.0], [1750.0, 300.0, 0.6], [2900.0, 400.0, 0.25]]
	var f0 := func(t: float) -> float:
		if t < 0.14:
			return lerpf(650.0, top, t / 0.14)
		if t < dur - 0.4:
			var k := (t - 0.14) / (dur - 0.54)
			return top * (1.0 - 0.5 * k) * (1.0 + 0.13 * sin(TAU * 9.5 * t))
		return lerpf(top * 0.5, 260.0, (t - dur + 0.4) / 0.4) * (1.0 + 0.2 * sin(TAU * 14.0 * t))
	return _voiced(dur, f0, func(_t): return vw,
		func(t): return _ar(t, 0.04, 0.3, dur) * (0.72 + 0.28 * sin(TAU * 9.5 * t)), 0.38, 0.025, 0.42)


func _snort(v: int) -> PackedFloat32Array:
	var dur := 0.55 + v * 0.1
	var x := _swept_noise(dur, func(t): return 420.0 + 300.0 * t, 1.6,
		func(t): return _ar(t, 0.015, dur * 0.7, dur) * (0.55 + 0.45 * sin(t * TAU * 38.0)))
	var nose := _swept_noise(dur, func(_t): return 950.0, 3.0, func(t): return _ar(t, 0.02, dur * 0.6, dur) * 0.5)
	_mix(x, nose, 0.0)
	return x


func _cow(v: int) -> PackedFloat32Array:
	# "mm-oo-oo": lips closed, the jaw drops to an "oo", closes again
	var dur := 1.7 + v * 0.2
	var p := 98.0 + v * 9.0
	var mm := [[260.0, 60.0, 1.0], [900.0, 150.0, 0.12], [2300.0, 300.0, 0.04]]
	var oo := [[480.0, 100.0, 1.0], [900.0, 120.0, 0.6], [2400.0, 220.0, 0.12]]
	return _voiced(dur,
		func(t): return p * (1.0 + 0.28 * smoothstep(0.0, 0.35, t) - 0.18 * smoothstep(dur * 0.6, dur, t)),
		func(t): return _lerp_vowel(mm, oo, smoothstep(0.05, 0.3, t) * (1.0 - smoothstep(dur - 0.35, dur, t))),
		func(t): return _ar(t, 0.12, 0.45, dur), 0.12, 0.012, 0.55)


func _sheep(v: int) -> PackedFloat32Array:
	var dur := 0.85 + v * 0.1
	var p := 265.0 + v * 30.0
	var b := [[300.0, 90.0, 1.0], [900.0, 140.0, 0.3], [2400.0, 200.0, 0.1]]
	var aa := [[760.0, 130.0, 1.0], [1260.0, 150.0, 0.7], [2500.0, 220.0, 0.3]]
	return _voiced(dur, func(t): return p * (1.0 + 0.035 * sin(TAU * 7.5 * t)),
		func(t): return _lerp_vowel(b, aa, smoothstep(0.0, 0.08, t)),
		func(t): return _ar(t, 0.03, 0.25, dur) * (0.62 + 0.38 * sin(TAU * 7.5 * t)), 0.2, 0.02, 0.45)


func _pig(v: int) -> PackedFloat32Array:
	var x := _buf(0.9)
	var at := 0.0
	for k in 3:
		var d := rng.randf_range(0.12, 0.2)
		var p := rng.randf_range(105.0, 140.0) + v * 8.0
		var g := _voiced(d, func(t): return p * (1.0 - 0.2 * t / d), func(_t): return [[320.0, 130.0, 1.0], [1050.0, 220.0, 0.45], [2300.0, 300.0, 0.15]],
			func(t): return _ar(t, 0.01, d * 0.6, d), 0.65, 0.09, 0.35)
		_mix(x, g, at)
		at += d + rng.randf_range(0.04, 0.12)
	return x


func _hen(v: int) -> PackedFloat32Array:
	var x := _buf(1.1)
	var at := 0.0
	var vw := [[900.0, 220.0, 1.0], [1750.0, 260.0, 0.5], [3000.0, 400.0, 0.2]]
	for k in 4 + v % 2:
		var d := 0.065
		var p := rng.randf_range(430.0, 520.0)
		_mix(x, _voiced(d, func(_t): return p, func(_t): return vw, func(t): return _ar(t, 0.005, 0.04, d), 0.3, 0.03, 0.4), at)
		at += rng.randf_range(0.11, 0.17)
	var bawk := 0.26          # the drawn-out "ba-KAWK"
	_mix(x, _voiced(bawk, func(t): return lerpf(480.0, 760.0, t / bawk), func(_t): return vw, func(t): return _ar(t, 0.02, 0.1, bawk), 0.35, 0.03, 0.4), at + 0.05)
	return x


func _dog(v: int) -> PackedFloat32Array:
	var x := _buf(0.8)
	for k in 2:
		var d := 0.15
		var p := 410.0 - v * 30.0
		_mix(x, _voiced(d, func(t): return p * (1.0 - 0.25 * t / d), func(_t): return [[650.0, 150.0, 1.0], [1350.0, 200.0, 0.6], [2600.0, 300.0, 0.2]],
			func(t): return _ar(t, 0.006, 0.09, d), 0.38, 0.03, 0.4), k * 0.27)
	return x


func _donkey(_v: int) -> PackedFloat32Array:
	var x := _buf(2.0)
	var at := 0.0
	for k in 2:
		var hee := 0.42
		_mix(x, _voiced(hee, func(t): return 930.0 * (1.0 + 0.04 * sin(t * 40.0)), func(_t): return [[300.0, 100.0, 0.6], [2300.0, 220.0, 1.0], [3000.0, 300.0, 0.4]],
			func(t): return _ar(t, 0.04, 0.12, hee), 0.65, 0.05, 0.35), at)
		var haw := 0.5
		_mix(x, _voiced(haw, func(t): return 310.0 * (1.0 - 0.15 * t / haw), func(_t): return [[700.0, 130.0, 1.0], [1100.0, 150.0, 0.7], [2500.0, 220.0, 0.2]],
			func(t): return _ar(t, 0.03, 0.2, haw), 0.35, 0.04, 0.4), at + hee)
		at += hee + haw + 0.05
	return x


func _alpaca(v: int) -> PackedFloat32Array:
	var dur := 0.9
	var p := 215.0 + v * 15.0
	return _voiced(dur, func(t): return p * (1.0 + 0.08 * sin(PI * t / dur)), func(_t): return [[280.0, 80.0, 1.0], [1000.0, 200.0, 0.1]],
		func(t): return _ar(t, 0.12, 0.35, dur), 0.05, 0.008, 0.6)


func _quack(v: int) -> PackedFloat32Array:
	var x := _buf(0.8)
	for k in 2 + v % 2:
		var d := 0.14
		_mix(x, _voiced(d, func(t): return 270.0 * (1.0 - 0.18 * t / d), func(_t): return [[1050.0, 300.0, 1.0], [2200.0, 350.0, 0.7], [3300.0, 400.0, 0.3]],
			func(t): return _ar(t, 0.008, 0.07, d), 0.3, 0.035, 0.22), k * 0.2)
	return x


func _honk(v: int) -> PackedFloat32Array:
	var x := _buf(0.9)
	for k in 2:
		var d := 0.28
		_mix(x, _voiced(d, func(t): return (420.0 + v * 20.0) * (1.0 - 0.1 * t / d), func(_t): return [[820.0, 180.0, 1.0], [1600.0, 220.0, 0.6], [2800.0, 300.0, 0.25]],
			func(t): return _ar(t, 0.02, 0.1, d), 0.15, 0.015, 0.32), k * 0.36)
	return x


func _caw(v: int) -> PackedFloat32Array:
	var x := _buf(1.4)
	for k in 2 + v % 2:
		var d := 0.32
		_mix(x, _voiced(d, func(t): return 610.0 * (1.0 - 0.12 * t / d), func(_t): return [[1100.0, 300.0, 1.0], [1700.0, 350.0, 0.7], [2900.0, 400.0, 0.2]],
			func(t): return _ar(t, 0.02, 0.15, d), 0.75, 0.09, 0.3), k * 0.42)
	return x


func _gull(_v: int) -> PackedFloat32Array:
	var x := _buf(1.6)
	var d := 0.7
	_mix(x, _voiced(d, func(t): return lerpf(1300.0, 800.0, t / d), func(_t): return [[1500.0, 300.0, 1.0], [2900.0, 400.0, 0.5]],
		func(t): return _ar(t, 0.03, 0.25, d), 0.2, 0.02, 0.35), 0.0)
	for k in 3:
		var dk := 0.12
		_mix(x, _voiced(dk, func(_t): return 1150.0, func(_t): return [[1500.0, 300.0, 1.0], [2900.0, 400.0, 0.5]],
			func(t): return _ar(t, 0.01, 0.06, dk), 0.2, 0.02, 0.35), 0.85 + k * 0.17)
	return x


func _screech(_v: int) -> PackedFloat32Array:
	var d := 1.2
	return _voiced(d, func(t): return lerpf(2250.0, 1800.0, t / d) * (1.0 + 0.02 * sin(t * TAU * 6.0)), func(_t): return [[2500.0, 400.0, 1.0], [3400.0, 500.0, 0.5]],
		func(t): return _ar(t, 0.05, 0.5, d), 0.45, 0.03, 0.35)


# ------------------------------------------------------------------ eating, drinking, water
func _drink(_v: int) -> PackedFloat32Array:
	var x := _buf(1.0)
	for k in 3:
		var at := 0.08 + k * 0.28
		_ping(x, at, 320.0, 0.025, 0.8, 0.55)          # a gulp: the throat's resonance dropping
		_click(x, at + 0.05, 0.02, 0.25)
	_lowpass(x, 1800.0)
	return x


func _eat(_v: int) -> PackedFloat32Array:
	var x := _buf(1.1)
	for k in 3:
		var at := 0.05 + k * 0.32
		for c in 26:                               # a crunch: a burst of tiny fractures
			_click(x, at + rng.randf_range(0.0, 0.11), 0.004, rng.randf_range(0.2, 0.7))
	_lowpass(x, 4200.0)
	return x


func _splash(v: int) -> PackedFloat32Array:
	var x := _swept_noise(0.35, func(t): return 1500.0 - 900.0 * t, 0.8, func(t): return exp(-t / 0.07) * (1.0 + v * 0.1))
	for b in 6:
		_ping(x, rng.randf_range(0.03, 0.25), rng.randf_range(700.0, 1800.0), rng.randf_range(0.008, 0.02), 0.25, 1.7)
	return x


func _thunder(v: int) -> PackedFloat32Array:
	var dur := 5.5
	var x := _brown(dur, 140.0)
	var rolls := []
	for k in 5:
		rolls.append([rng.randf_range(0.2, 3.5), rng.randf_range(0.4, 1.0)])
	for i in x.size():
		var t := float(i) / RATE
		var e := exp(-t / 1.8)
		for r in rolls:
			e += r[1] * exp(-pow((t - r[0]) / 0.45, 2.0)) * 0.6
		x[i] *= e
	if v != 2:          # near strikes crack before they roll
		var crack := _swept_noise(0.25, func(t): return 3000.0 - 2000.0 * t, 0.5, func(t): return exp(-t / 0.05) * 3.0)
		_mix(x, crack, 0.0)
	return x


# ------------------------------------------------------------------ ambience beds (looping)
func _wind() -> PackedFloat32Array:
	var secs := 22.0
	var gust := _drift(secs, 0.25, 0.25, 1.0)
	var x := _brown(secs, 220.0)
	for i in x.size():
		x[i] *= 0.4 + 0.6 * gust[i]
	var mid := _swept_noise(secs, func(t): return 380.0 + 700.0 * gust[mini(int(t * RATE), gust.size() - 1)], 1.2,
		func(t): return pow(gust[mini(int(t * RATE), gust.size() - 1)], 1.5) * 0.35)
	_mix(x, mid, 0.0)
	var leaves := _swept_noise(secs, func(_t): return 4200.0, 0.7, func(t): return pow(gust[mini(int(t * RATE), gust.size() - 1)], 2.5) * 0.12)
	for i in leaves.size():
		if rng.randf() < 0.002:
			leaves[i] *= 6.0
	_mix(x, leaves, 0.0)
	_loop(x, 3.0)
	return x


func _rain() -> PackedFloat32Array:
	var secs := 10.0
	var x := _swept_noise(secs, func(_t): return 3600.0, 0.6, func(_t): return 0.5)
	var low := _brown(secs, 700.0)
	_mix(x, low, 0.0, 0.8)
	for k in 4200:              # drops on leaves and puddles
		_ping(x, rng.randf_range(0.0, secs), rng.randf_range(1800.0, 6200.0), rng.randf_range(0.0015, 0.005), rng.randf_range(0.04, 0.22))
	for k in 260:               # fatter drops
		_ping(x, rng.randf_range(0.0, secs), rng.randf_range(900.0, 2000.0), rng.randf_range(0.006, 0.014), rng.randf_range(0.15, 0.32), 1.4)
	_loop(x, 1.0)
	return x


func _forest() -> PackedFloat32Array:
	var secs := 18.0
	var gust := _drift(secs, 0.3, 0.3, 1.0)
	var x := _swept_noise(secs, func(_t): return 3800.0, 0.6, func(t): return gust[mini(int(t * RATE), gust.size() - 1)] * 0.035)
	var hush := _brown(secs, 300.0)
	_mix(x, hush, 0.0, 0.25)
	var t := 0.3
	while t < secs - 1.2:
		var kind := rng.randi() % 10
		var amp := rng.randf_range(0.12, 0.4)
		if kind < 4:            # a warbler's phrase of gliding notes
			var notes := rng.randi_range(5, 9)
			var base := rng.randf_range(2600.0, 4200.0)
			var at := t
			for m in notes:
				var d := rng.randf_range(0.05, 0.11)
				var f := base * rng.randf_range(0.82, 1.25)
				_note(x, at, d, f, f * rng.randf_range(0.85, 1.2), amp)
				at += d + rng.randf_range(0.01, 0.04)
		elif kind < 6:          # a two-note whistle, "fee-bee"
			_note(x, t, 0.32, 3950.0, 3900.0, amp * 0.8)
			_note(x, t + 0.36, 0.34, 3300.0, 3250.0, amp * 0.8)
		elif kind < 8:          # a trill
			var f := rng.randf_range(4600.0, 5600.0)
			for m in 14:
				_note(x, t + m * 0.052, 0.035, f, f * 0.94, amp * 0.6)
		elif kind < 9:          # a wood pigeon, far off
			for m in 3:
				_note(x, t + m * 0.55, 0.35 if m != 1 else 0.5, 530.0, 500.0, amp * 0.45)
		else:                   # a woodpecker drumming
			for m in 16:
				_click(x, t + m * 0.055, 0.008, 0.5 * (1.0 - m / 20.0), 1200.0)
		t += rng.randf_range(0.6, 2.2)
	_loop(x, 1.2)
	return x


func _night() -> PackedFloat32Array:
	var secs := 14.0
	var x := _brown(secs, 180.0)
	for i in x.size():
		x[i] *= 0.15
	for c in 4:                 # crickets: chirps of three pulses
		var f := rng.randf_range(3700.0, 4700.0)
		var period := rng.randf_range(0.32, 0.45)
		var amp := rng.randf_range(0.06, 0.16)
		var t := rng.randf_range(0.0, period)
		while t < secs:
			for p in 3:
				_note(x, t + p * 0.028, 0.014, f, f, amp)
			t += period * rng.randf_range(0.97, 1.03)
	for o in 2:                 # an owl: "hoo, hoo-hoo"
		var at := rng.randf_range(1.0, secs - 3.0)
		for k in 3:
			var d := 0.42 if k == 0 else 0.26
			var g := _voiced(d, func(_t): return 360.0, func(_t): return [[360.0, 50.0, 1.0], [720.0, 100.0, 0.08]],
				func(tt): return _ar(tt, 0.06, 0.12, d), 0.02, 0.003, 0.6)
			_mix(x, g, at + [0.0, 0.62, 0.95][k], 0.35)
	_loop(x, 1.0)
	return x


func _river() -> PackedFloat32Array:
	var secs := 12.0
	var swell := _drift(secs, 0.5, 0.6, 1.0)
	var x := _swept_noise(secs, func(_t): return 650.0, 0.7, func(t): return swell[mini(int(t * RATE), swell.size() - 1)] * 0.6)
	var hi := _swept_noise(secs, func(_t): return 2000.0, 1.0, func(t): return swell[mini(int(t * RATE), swell.size() - 1)] * 0.25)
	_mix(x, hi, 0.0)
	for b in 1400:              # the babble: countless small bubbles ringing as they form
		_ping(x, rng.randf_range(0.0, secs), rng.randf_range(450.0, 2400.0), rng.randf_range(0.004, 0.012), rng.randf_range(0.04, 0.16), rng.randf_range(1.3, 2.0))
	_loop(x, 1.5)
	return x


func _fire() -> PackedFloat32Array:
	var secs := 10.0
	var x := _brown(secs, 160.0)
	var surge := _drift(secs, 0.7, 0.5, 1.0)
	for i in x.size():
		x[i] *= surge[i] * 0.8
	var t := 0.0
	while t < secs - 0.1:       # crackles come in bursts
		var burst := rng.randi_range(2, 9)
		for m in burst:
			_click(x, t + rng.randf_range(0.0, 0.12), rng.randf_range(0.0008, 0.003), rng.randf_range(0.2, 0.7))
		t += rng.randf_range(0.04, 0.35)
	for s in 22:                # the occasional snap of a knot of sap
		_click(x, rng.randf_range(0.0, secs - 0.1), 0.012, rng.randf_range(0.6, 1.0), rng.randf_range(1800.0, 3200.0))
	var hiss := _swept_noise(secs, func(_t): return 4200.0, 2.0, func(tt): return 0.04 * (0.5 + 0.5 * sin(tt * 0.9)))
	_mix(x, hiss, 0.0)
	_loop(x, 1.0)
	return x


func _tavern() -> PackedFloat32Array:
	var secs := 16.0
	var x := _buf(secs)
	for k in 26:                # a room full of talk
		var b := _babble(rng.randf_range(100.0, 230.0), rng.randf_range(1.2, 2.6))
		_mix(x, b, rng.randf_range(0.0, secs - 2.6), rng.randf_range(0.25, 0.6))
	for k in 3:                 # laughter
		var at := rng.randf_range(1.0, secs - 2.0)
		var p := rng.randf_range(140.0, 250.0)
		for m in rng.randi_range(4, 7):
			var d := 0.1
			_mix(x, _voiced(d, func(_t): return p * (1.0 - m * 0.03), func(_t): return _vowel("ah", 1.0 if p < 180.0 else 1.16),
				func(tt): return _ar(tt, 0.01, 0.05, d), 0.45, 0.03, 0.45), at + m * 0.15, 0.7)
	_lowpass(x, 2200.0)
	_loop(x, 1.5)
	return x


func _ocean() -> PackedFloat32Array:
	var secs := 22.0
	var x := _brown(secs, 260.0)
	for i in x.size():
		x[i] *= 0.35
	var t := 0.0
	while t < secs - 6.0:       # a wave washes in, breaks and fizzes back out
		var wash := _swept_noise(3.0, func(tt): return 300.0 + 900.0 * tt / 3.0, 0.7, func(tt): return pow(tt / 3.0, 2.0) * 0.6)
		_mix(x, wash, t)
		var crash := _swept_noise(0.9, func(_tt): return 1200.0, 0.4, func(tt): return exp(-tt / 0.25) * 1.2)
		_mix(x, crash, t + 3.0)
		var fizz := _swept_noise(3.5, func(_tt): return 3800.0, 0.8, func(tt): return exp(-tt / 1.4) * 0.35)
		for b in 120:
			_click(fizz, rng.randf_range(0.0, 3.0), 0.002, rng.randf_range(0.05, 0.2))
		_mix(x, fizz, t + 3.3)
		t += rng.randf_range(5.5, 7.5)
	_loop(x, 2.0)
	return x

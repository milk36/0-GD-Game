extends RefCounted
class_name SfxSynth
## 程序化音效合成器 —— 风 / 雨 / 雷电道具音效与碎片格提示音。
##
## 设计约束：项目零音频资源。所有音色在首次播放时用 GDScript 实时合成 PCM，
## 封装成 AudioStreamWAV 交给 AudioStreamPlayer。音色参数集中在各 build_* 顶部，
## 改一个数字就能调音，无需重新导入任何素材。
##
## 统一风格：赛博朋克 / synthwave —— 短促、干净、数字感，带一点延迟混响的空间尾。

const SR := 44100

enum W { SINE, TRI, SAW, SQR, NOISE }

## 雨滴参数（13 滴）：起始时间(s) / 起始频率(Hz) / 音量 / 声像。
## 手工排布：时间上疏密交替，音高高低错落，声像左右散开 —— 听感是"一阵雨点打散在棋盘上"。
const RAIN_T0: Array[float] = [
	0.000, 0.035, 0.062, 0.098, 0.131, 0.170, 0.198,
	0.235, 0.268, 0.305, 0.337, 0.372, 0.408,
]
const RAIN_F0: Array[float] = [
	2650.0, 1410.0, 2280.0, 1730.0, 1320.0, 2560.0, 1890.0,
	1490.0, 2380.0, 1650.0, 2030.0, 2750.0, 1560.0,
]
const RAIN_AMP: Array[float] = [
	0.34, 0.22, 0.42, 0.26, 0.48, 0.30, 0.38,
	0.24, 0.45, 0.28, 0.36, 0.50, 0.32,
]
const RAIN_PAN: Array[float] = [
	-0.62, 0.38, -0.18, 0.70, -0.75, 0.12, 0.55,
	-0.45, 0.25, -0.30, 0.66, 0.05, -0.58,
]

# ================================================================
# 基础 DSP 原语
# ================================================================

static func _frac(x: float) -> float:
	return x - floor(x)


## 振荡器。phase 为「周期数」(不是弧度)，便于音高扫描时直接累加 f/SR。
static func osc(w: int, phase: float) -> float:
	var m := _frac(phase)
	match w:
		W.SINE:
			return sin(phase * TAU)
		W.TRI:
			if m < 0.25:
				return m * 4.0
			if m < 0.75:
				return 2.0 - m * 4.0
			return m * 4.0 - 4.0
		W.SAW:
			return m * 2.0 - 1.0
		W.SQR:
			return 1.0 if m < 0.5 else -1.0
	return randf() * 2.0 - 1.0  # NOISE


## 指数音高扫描：t∈[0,1] 从 f0 滑到 f1（听感上比线性自然）。
static func glide(f0: float, f1: float, t: float) -> float:
	return f0 * pow(f1 / f0, clampf(t, 0.0, 1.0))


## AD 包络：线性起音 atk，随后 (1-x)^curve 指数衰减。
## 整数曲线走乘法快路径 —— 包络是每采样调用的，pow() 在这里是主要热点。
static func env(t: float, dur: float, atk: float, curve: float = 2.0) -> float:
	if t < 0.0 or t >= dur:
		return 0.0
	if t < atk:
		return t / maxf(atk, 1e-6)
	var u: float = 1.0 - (t - atk) / maxf(dur - atk, 1e-6)
	if curve == 2.0:
		return u * u
	if curve == 3.0:
		return u * u * u
	if curve == 4.0:
		return u * u * u * u
	return pow(u, curve)


## 一阶低通系数（fc 为截止频率）。
static func k_lp(fc: float) -> float:
	return 1.0 - exp(-TAU * clampf(fc, 20.0, SR * 0.45) / SR)


## 反馈延迟（简易空间感）：在 buf 上叠加若干延迟抽头。
static func delay(buf: PackedFloat32Array, time: float, feedback: float, mix: float) -> PackedFloat32Array:
	var n := buf.size()
	var d := maxi(1, int(time * SR))
	var out := PackedFloat32Array(buf)
	out.resize(n)
	var i := d
	while i < n:
		out[i] += out[i - d] * feedback
		i += 1
	i = 0
	while i < n:
		buf[i] = buf[i] * (1.0 - mix * 0.5) + out[i] * mix
		i += 1
	return buf


## 收尾：首尾去爆音淡变 + tanh 软饱和（防止叠加削波）。
static func _finalize(buf: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var n := buf.size()
	var fi := maxi(1, int(0.002 * SR))
	var fo := maxi(1, int(0.010 * SR))
	for i in n:
		var g := gain
		if i < fi:
			g *= float(i) / float(fi)
		elif i > n - fo:
			g *= float(n - i) / float(fo)
		buf[i] = tanh(buf[i] * g) * 0.92
	return buf


## 立体声等功率声像：pan ∈ [-1, 1]。
static func _pan_gain(pan: float) -> Vector2:
	var ang: float = (clampf(pan, -1.0, 1.0) + 1.0) * 0.5 * PI * 0.5
	return Vector2(cos(ang), sin(ang))


# ================================================================
# 1. 碎片格出现 —— 「数据碎片到达」
# ================================================================
## 三角波纯五度上行 + 两声数字 blip + 一撮数据噪声。
## 听感：终端弹出一条新数据，清亮但不抢戏。
static func shard_spawn() -> PackedFloat32Array:
	var dur := 0.22
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var blips: Array[float] = [0.0, 0.05]
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var td := t / dur
		ph += glide(660.0, 1320.0, td) / SR
		var v := osc(W.TRI, ph) * env(t, dur, 0.004, 2.2) * 0.55
		# 数字 blip：两声极短方波点缀
		for b in blips:
			var tb := t - b
			if tb >= 0.0 and tb < 0.015:
				v += osc(W.SQR, tb * 2400.0) * (1.0 - tb / 0.015) * 0.16
		# 数据噪声
		if t < 0.03:
			v += (randf() * 2.0 - 1.0) * (1.0 - t / 0.03) * 0.08
		lp += k_lp(6500.0) * (v - lp)
		out[i] = lp
	return _finalize(out, 0.72)


# ================================================================
# 2. 碎片格倒计时滴答（最后 3 秒）
# ================================================================
## step: 0=剩3s 1=剩2s 2=剩1s —— 音高与音量递增，制造紧迫感。
static func shard_tick(step: int = 0) -> PackedFloat32Array:
	var s := clampi(step, 0, 2)
	var freqs: Array[float] = [1568.0, 1760.0, 2093.0]
	var amps: Array[float] = [0.30, 0.38, 0.48]
	var f: float = freqs[s]
	var a: float = amps[s]
	var dur := 0.065
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var v := (osc(W.SINE, t * f) * 0.75 + osc(W.SQR, t * f) * 0.25) \
				* env(t, dur, 0.001, 3.0) * a
		if t < 0.004:  # 起音的一点点"咔"
			v += (randf() * 2.0 - 1.0) * 0.15
		lp += k_lp(7000.0) * (v - lp)
		out[i] = lp
	return _finalize(out, 0.75)


# ================================================================
# 3. 碎片格超时熄灭 —— 「信号丢失」
# ================================================================
## 锯齿波下扫 + 低通同步关闭（信号被掐断）+ 低频下沉。
static func shard_expire() -> PackedFloat32Array:
	var dur := 0.42
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph_s := 0.0
	var ph_b := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var td := t / dur
		var fs := glide(420.0, 130.0, td)
		var fb := glide(210.0, 65.0, td)
		ph_s += fs / SR
		ph_b += fb / SR
		var v := osc(W.SAW, ph_s) * env(t, dur, 0.006, 1.6) * 0.50
		v += osc(W.SINE, ph_b) * env(t, dur, 0.006, 1.6) * 0.25
		if t < 0.05:
			v += (randf() * 2.0 - 1.0) * (1.0 - t / 0.05) * 0.10
		lp += k_lp(glide(3000.0, 260.0, td)) * (v - lp)
		out[i] = lp
	return _finalize(out, 0.85)


# ================================================================
# 4. 捕获到道具 —— 成功反馈
# ================================================================
## 三音上行琶音(C5-E5-G5) + FM 亮铃 + 延迟空间尾。
static func item_get() -> PackedFloat32Array:
	var dur := 0.50
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var arp: Array[float] = [523.25, 659.25, 783.99]
	var offs: Array[float] = [0.0, 0.055, 0.11]
	var ph_fm := 0.0
	var ph_md := 0.0
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		# 琶音
		for k in 3:
			var ta := t - offs[k]
			if ta >= 0.0:
				var p := ta
				v += (osc(W.TRI, p * arp[k]) * 0.7 + osc(W.SINE, p * arp[k] * 2.0) * 0.3) \
						* env(ta, 0.16, 0.002, 3.0) * 0.42
		# FM 亮铃：载波 1568Hz，调制比 3.5，调制指数随时间衰减
		var fc := 1567.98
		var fm := fc * 3.5
		var idx: float = 5.0 * pow(maxf(0.0, 1.0 - t / 0.40), 2.0)
		ph_fm += fc / SR
		ph_md += fm / SR
		v += sin(TAU * ph_fm + idx * sin(TAU * ph_md)) * env(t, 0.42, 0.002, 2.5) * 0.22
		out[i] = v
	out = delay(out, 0.13, 0.30, 0.35)
	return _finalize(out, 0.80)


# ================================================================
# 5. 风 WIND —— 横向扫过，带立体声 L→R
# ================================================================
## 带通噪声中心频率 320→5200→650Hz 扫动 + 11Hz 呼啸 AM + 低频体感垫音。
## 声像从最左扫到最右，对应"两行被横扫带走"。
static func wind_cast() -> Dictionary:
	var dur := 0.62
	var n := int(dur * SR)
	var L := PackedFloat32Array()
	var R := PackedFloat32Array()
	L.resize(n)
	R.resize(n)
	var hp := 0.0
	var lp := 0.0
	var lp_prev := 0.0
	var ph_sub := 0.0
	for i in n:
		var t := float(i) / SR
		var td := t / dur
		# 带通中心频率：先上扫后回落
		var fc: float
		if td < 0.42:
			fc = glide(320.0, 5200.0, td / 0.42)
		else:
			fc = glide(5200.0, 650.0, (td - 0.42) / 0.58)
		var nz := randf() * 2.0 - 1.0
		# 高通(一阶)→低通(一阶) 逼近带通
		hp = nz - lp_prev
		lp_prev += k_lp(fc * 0.55) * (nz - lp_prev)
		lp += k_lp(fc * 1.8) * (hp - lp)
		# 呼啸感：低频 AM
		var am := 1.0 + 0.30 * sin(TAU * 10.5 * t) * (1.0 if t < 0.45 else 0.0)
		var v := lp * env(t, dur, 0.05, 1.7) * 0.75 * am
		# 低频体感
		ph_sub += glide(240.0, 430.0, minf(td / 0.35, 1.0)) / SR
		var sub := osc(W.SINE, ph_sub) * env(t, 0.50, 0.03, 2.0) * 0.22
		var mono := v + sub
		var pan := clampf(td / 0.34, 0.0, 1.0) * 1.8 - 0.9
		var g := _pan_gain(pan)
		L[i] = mono * g.x
		R[i] = mono * g.y
	return {"l": _finalize(L, 0.82), "r": _finalize(R, 0.82)}


# ================================================================
# 6. 雨 RAIN —— 散点坠落
# ================================================================
## 13 滴不同音高的"水滴"(正弦快速下滑) + 一层低通噪声雨幕。
## 雨滴参数硬编码为常量（见下方 RAIN_*）：不依赖随机数，任何平台合成结果一致，
## 浏览器试听页复用同一组常量 —— 听到的就是游戏里的声音。
static func rain_cast() -> Dictionary:
	var dur := 0.60
	var n := int(dur * SR)
	var L := PackedFloat32Array()
	var R := PackedFloat32Array()
	L.resize(n)
	R.resize(n)
	# ① 雨幕：低通噪声，全时长铺底
	var lp_c := 0.0
	for i in n:
		var t := float(i) / SR
		lp_c += k_lp(900.0) * ((randf() * 2.0 - 1.0) - lp_c)
		var curtain := lp_c * env(t, dur, 0.08, 1.4) * 0.13
		L[i] = curtain
		R[i] = curtain
	# ② 雨滴：每滴只写自己的区间(避免全量扫描)
	for k in RAIN_T0.size():
		var s0 := int(RAIN_T0[k] * SR)
		var s1 := mini(n, s0 + int(0.035 * SR))
		var ph := 0.0
		var g := _pan_gain(RAIN_PAN[k])
		for i in range(s0, s1):
			var tb := float(i - s0) / SR
			# 音高在 16ms 内下滑到 0.42 倍 —— 水滴"叮咚"感的来源
			ph += glide(RAIN_F0[k], RAIN_F0[k] * 0.42, clampf(tb / 0.016, 0.0, 1.0)) / SR
			var v := sin(TAU * ph) * env(tb, 0.03, 0.0008, 2.5) * RAIN_AMP[k]
			L[i] += v * g.x
			R[i] += v * g.y
	return {"l": _finalize(L, 1.05), "r": _finalize(R, 1.05)}


# ================================================================
# 7. 雷电 BOLT —— 爆裂 + 撕裂 + 轰鸣
# ================================================================
## 三段式：高频爆裂(噪声) → 锯齿撕裂下扫(带抖动 AM) → 低频轰鸣。
## 尾部加短延迟回响；右声道延迟 9 采样做 Haas 加宽。
static func bolt_cast() -> Dictionary:
	var dur := 0.50
	var n := int(dur * SR)
	var L := PackedFloat32Array()
	var R := PackedFloat32Array()
	L.resize(n)
	R.resize(n)
	var ph_tear := 0.0
	var ph_boom := 0.0
	var hp := 0.0
	var lp_prev := 0.0
	var lp := 0.0
	var jitter := 1.0
	for i in n:
		var t := float(i) / SR
		if i % 32 == 0:
			jitter = 0.7 + randf() * 0.6  # 电弧不稳定
		var v := 0.0
		# ① 爆裂
		var nz := randf() * 2.0 - 1.0
		hp = nz - lp_prev
		lp_prev += k_lp(2600.0) * (nz - lp_prev)
		v += hp * env(t, 0.09, 0.0008, 4.0) * 0.85
		# ② 撕裂：锯齿下扫 + 噪声混合 + 抖动
		var tt := t - 0.02
		if tt >= 0.0 and tt < 0.22:
			ph_tear += glide(1900.0, 280.0, tt / 0.20) / SR
			var tear := osc(W.SAW, ph_tear) * 0.65 + nz * 0.35
			lp += k_lp(glide(6000.0, 1200.0, tt / 0.22)) * (tear - lp)
			v += lp * env(tt, 0.22, 0.002, 2.2) * 0.50 * jitter
		# ③ 轰鸣
		var tb := t - 0.03
		if tb >= 0.0:
			ph_boom += glide(95.0, 42.0, clampf(tb / 0.36, 0.0, 1.0)) / SR
			v += osc(W.SINE, ph_boom) * env(tb, 0.38, 0.006, 1.8) * 0.50
		L[i] = v
	var mono := delay(L, 0.085, 0.32, 0.30)
	var haas := 9  # 采样
	for i in n:
		L[i] = mono[i]
		R[i] = mono[maxi(0, i - haas)]
	return {"l": _finalize(L, 0.62), "r": _finalize(R, 0.62)}


# ================================================================
# 8. 道具作废 —— 「数据丢失」
# ================================================================
## 方波八度下行 + 4bit 量化(数字劣化) + 闷响低频，短促干瘪。
static func item_fizzle() -> PackedFloat32Array:
	var dur := 0.26
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var ph_b := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var td := t / dur
		ph += glide(340.0, 150.0, td) / SR
		ph_b += glide(120.0, 70.0, minf(t / 0.12, 1.0)) / SR
		var v := osc(W.SQR, ph) * env(t, 0.24, 0.002, 2.0) * 0.50
		v = round(v * 4.0) / 4.0  # bitcrush：量化到 5 级
		v += osc(W.SINE, ph_b) * env(t, 0.14, 0.002, 2.0) * 0.30
		if t < 0.04:
			v += (randf() * 2.0 - 1.0) * (1.0 - t / 0.04) * 0.12
		lp += k_lp(1500.0) * (v - lp)
		out[i] = lp
	return _finalize(out, 0.65)


# ================================================================
# 9. 道具消除结算 —— 轻脆落点音
# ================================================================
## 两声上行 ping + 一点高频碎光。音量刻意压低，避免盖过道具主音。
static func item_clear() -> PackedFloat32Array:
	var dur := 0.34
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		var v := osc(W.SINE, t * 1046.5) * env(t, 0.18, 0.003, 2.6) * 0.30
		v += osc(W.SINE, (t - 0.05) * 1568.0) * env(t - 0.05, 0.24, 0.003, 2.6) * 0.26
		if t < 0.05:
			v += (randf() * 2.0 - 1.0) * (1.0 - t / 0.05) * 0.10
		out[i] = v
	out = delay(out, 0.07, 0.22, 0.25)
	return _finalize(out, 0.75)


# ================================================================
# 出口：id → AudioStreamWAV
# ================================================================

static func build(id: String) -> AudioStreamWAV:
	match id:
		"shard_spawn":
			return _to_mono(shard_spawn())
		"shard_tick0":
			return _to_mono(shard_tick(0))
		"shard_tick1":
			return _to_mono(shard_tick(1))
		"shard_tick2":
			return _to_mono(shard_tick(2))
		"shard_expire":
			return _to_mono(shard_expire())
		"item_get":
			return _to_mono(item_get())
		"wind_cast":
			var a: Dictionary = wind_cast()
			return _to_stereo(a.l, a.r)
		"rain_cast":
			var b: Dictionary = rain_cast()
			return _to_stereo(b.l, b.r)
		"bolt_cast":
			var c: Dictionary = bolt_cast()
			return _to_stereo(c.l, c.r)
		"item_fizzle":
			return _to_mono(item_fizzle())
		"item_clear":
			return _to_mono(item_clear())
		"eagle_star":
			return _to_mono(eagle_star())
		"eagle_boom":
			return _to_mono(eagle_boom())
		"eagle_hurt":
			return _to_mono(eagle_hurt())
		"eagle_bomb":
			return _to_mono(eagle_bomb())
		"eagle_rescue":
			return _to_mono(eagle_rescue())
		"eagle_laser":
			return _to_mono(eagle_laser())
		"eagle_boss_phase":
			return _to_mono(eagle_boss_phase())
		"eagle_win":
			return _to_mono(eagle_win())
		"eagle_lose":
			return _to_mono(eagle_lose())
	return null


static func _to_mono(buf: PackedFloat32Array) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(buf.size() * 2)
	for i in buf.size():
		b.encode_s16(i * 2, clampi(int(round(buf[i] * 32767.0)), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = b
	return s


static func _to_stereo(l: PackedFloat32Array, r: PackedFloat32Array) -> AudioStreamWAV:
	var n := mini(l.size(), r.size())
	var b := PackedByteArray()
	b.resize(n * 4)
	for i in n:
		b.encode_s16(i * 4, clampi(int(round(l[i] * 32767.0)), -32768, 32767))
		b.encode_s16(i * 4 + 2, clampi(int(round(r[i] * 32767.0)), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = true
	s.data = b
	return s


# ================================================================
# 方块雄鹰（eagle_*）—— M3 接入，全部单声道短音色
# ================================================================

## 拾星：高频短啾（6→9 半音上行），刻意轻，连拾不吵
static func eagle_star() -> PackedFloat32Array:
	var dur := 0.09
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		ph += glide(1318.0, 1976.0, t / dur) / SR
		out[i] = osc(W.TRI, ph) * env(t, dur, 0.002, 3.0) * 0.42
	return _finalize(out, 0.55)


## 敌机爆炸：噪声爆裂 + 低频下沉
static func eagle_boom() -> PackedFloat32Array:
	var dur := 0.38
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph_b := 0.0
	for i in n:
		var t := float(i) / SR
		var td := t / dur
		var nz := randf() * 2.0 - 1.0
		lp += k_lp(glide(1400.0, 150.0, td)) * (nz - lp)
		ph_b += glide(210.0, 48.0, td) / SR
		var v := lp * env(t, dur, 0.002, 2.2) * 0.85
		v += osc(W.SINE, ph_b) * env(t, dur, 0.004, 1.8) * 0.55
		out[i] = v
	return _finalize(out, 0.85)


## 玩家受击：双音警报（E6→B4 交替两声）
static func eagle_hurt() -> PackedFloat32Array:
	var dur := 0.30
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 830.0 if fmod(t, 0.15) < 0.075 else 587.0
		ph += f / SR
		var v := osc(W.SQR, ph) * 0.30 + osc(W.SINE, ph) * 0.45
		out[i] = v * env(t, dur, 0.002, 2.4) * 0.55
	return _finalize(out, 0.70)


## 炸弹：深轰鸣 + 高频碎裂
static func eagle_bomb() -> PackedFloat32Array:
	var dur := 0.55
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		ph += glide(150.0, 34.0, clampf(t / 0.40, 0.0, 1.0)) / SR
		var v := osc(W.SINE, ph) * env(t, 0.50, 0.004, 1.7) * 0.95
		if t < 0.10:
			var nz := randf() * 2.0 - 1.0
			lp += k_lp(3200.0) * (nz - lp)
			v += lp * (1.0 - t / 0.10) * 0.60
		out[i] = v
	return _finalize(out, 0.90)


## 救援成功：四音大调琶音 + 亮尾
static func eagle_rescue() -> PackedFloat32Array:
	var dur := 0.60
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		for k in 4:
			var ta := t - 0.07 * float(k)
			if ta >= 0.0:
				v += osc(W.TRI, ta * notes[k]) * env(ta, 0.22, 0.002, 2.6) * 0.40
		out[i] = v
	out = delay(out, 0.10, 0.26, 0.30)
	return _finalize(out, 0.80)


## 激光：锯齿下扫 + 电弧抖动
static func eagle_laser() -> PackedFloat32Array:
	var dur := 0.45
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var jitter := 1.0
	for i in n:
		var t := float(i) / SR
		if i % 40 == 0:
			jitter = 0.65 + randf() * 0.5
		ph += glide(1500.0, 240.0, clampf(t / 0.38, 0.0, 1.0)) / SR
		var v := osc(W.SAW, ph) * 0.55 + (randf() * 2.0 - 1.0) * 0.20
		out[i] = v * env(t, dur, 0.01, 1.9) * 0.60 * jitter
	return _finalize(out, 0.70)


## Boss 阶段切换：低音双簧管感（根音+五度持续）
static func eagle_boss_phase() -> PackedFloat32Array:
	var dur := 0.65
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / SR
		p1 += 98.0 / SR
		p2 += 147.0 / SR
		var v := osc(W.SAW, p1) * 0.40 + osc(W.SAW, p2) * 0.28
		out[i] = v * env(t, dur, 0.02, 1.6) * 0.70
	return _finalize(out, 0.75)


## 通关：四音上行号角
static func eagle_win() -> PackedFloat32Array:
	var dur := 0.95
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes: Array[float] = [392.0, 523.25, 659.25, 783.99]
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		for k in 4:
			var ta := t - 0.14 * float(k)
			if ta >= 0.0:
				var d2 := 0.55 if k == 3 else 0.18
				v += (osc(W.TRI, ta * notes[k]) * 0.7 + osc(W.SINE, ta * notes[k] * 2.0) * 0.3) \
						* env(ta, d2, 0.008, 1.8) * 0.42
		out[i] = v
	out = delay(out, 0.12, 0.28, 0.32)
	return _finalize(out, 0.85)


## 坠机：小调下行四音
static func eagle_lose() -> PackedFloat32Array:
	var dur := 0.95
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes: Array[float] = [392.0, 329.63, 261.63, 196.0]
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		for k in 4:
			var ta := t - 0.15 * float(k)
			if ta >= 0.0:
				var d2 := 0.50 if k == 3 else 0.16
				v += osc(W.TRI, ta * notes[k]) * env(ta, d2, 0.006, 2.0) * 0.42
		out[i] = v
	out = delay(out, 0.12, 0.26, 0.30)
	return _finalize(out, 0.78)

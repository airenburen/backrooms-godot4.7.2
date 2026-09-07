class_name SoundGenerator
extends RefCounted

const SAMPLE_RATE := 44100

static func create_footstep() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false

	var duration := 0.08
	var sample_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var envelope: float
		if progress < 0.1:
			envelope = progress / 0.1
		else:
			envelope = 1.0 - (progress - 0.1) / 0.9
		envelope = pow(envelope, 2.0)

		var thud := sin(TAU * 60.0 * t) * 0.55
		var crunch := (randf() * 2.0 - 1.0) * 0.12
		var sample := clampf((thud + crunch) * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))

	wav.data = data
	return wav

static func create_ambient_hum() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false

	var duration := 1.0
	var freq := 100.0
	var sample_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		var sample := 0.0
		sample += sin(TAU * freq * t) * 0.08
		sample += sin(TAU * freq * 2.0 * t) * 0.04
		sample += sin(TAU * freq * 3.0 * t) * 0.02
		sample += (randf() * 2.0 - 1.0) * 0.008
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = sample_count
	wav.data = data
	return wav

static func create_click() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false

	var duration := 0.02
	var sample_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		var envelope := 1.0 - (t / duration)
		envelope = pow(envelope, 3.0)
		var sample := (randf() * 2.0 - 1.0) * envelope * 0.3
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	wav.data = data
	return wav

# 蒸汽嘶嘶声：窄带噪声（3~6kHz 为主）+ 慢幅度调制循环（Level 2 管道漏气）
static func create_hiss() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false

	var duration := 2.0
	var sample_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var phase := 0.0
	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		# 慢幅度起伏：像气流一阵一阵地喷
		var breathing := 0.6 + 0.4 * sin(TAU * 0.35 * t + sin(TAU * 0.13 * t) * 1.5)
		# 窄带噪声：白噪声过一个简单的一阶带通（差分叠加近似）
		var noise := (randf() * 2.0 - 1.0)
		phase += noise * 0.35
		phase = clampf(phase, -1.0, 1.0) * 0.7 + noise * 0.3
		var sample := clampf(phase * breathing * 0.35, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))

	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = sample_count
	wav.data = data
	return wav

# 水滴声：高频 ping + 长衰减 + 轻微"噗"的落水起振（潮湿环境的听觉注脚）
static func create_drip() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false

	var duration := 0.5
	var sample_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var f := 2100.0
	var phase := 0.0
	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		var envelope := exp(-t * 14.0)
		if t < 0.004:
			envelope *= t / 0.004  # 起振
		# 频率轻微下滑：水滴的物理感
		phase += TAU * (f * (1.0 - t * 0.35)) / SAMPLE_RATE
		var sample := sin(phase) * envelope * 0.5
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	wav.data = data
	return wav

# 实体低吼：低频噪声 + 低于听觉的压感 + 缓慢振幅包络循环（Level ! 追逐音）
static func create_entity_growl() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false

	var duration := 3.0
	var sample_count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var rumble := 0.0
	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		# 缓慢的呼吸式包络：像什么东西在身后喘气
		var breath := 0.45 + 0.55 * pow(maxf(sin(TAU * 0.22 * t), 0.0), 1.5)
		# 低频隆隆 + 不和谐双音 + 少量噪声"沙"
		rumble = rumble * 0.985 + (randf() * 2.0 - 1.0) * 0.05
		var sample := sin(TAU * 38.0 * t) * 0.45
		sample += sin(TAU * 57.0 * t + sin(TAU * 3.0 * t)) * 0.22
		sample += rumble * 0.9
		sample *= breath * 0.8
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = sample_count
	wav.data = data
	return wav


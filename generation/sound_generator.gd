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


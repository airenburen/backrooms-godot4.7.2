extends CharacterBody3D

const SoundGen = preload("res://generation/sound_generator.gd")

signal flashlight_toggled(is_on: bool)

const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 1.8
const ACCELERATION := 10.0
const DECELERATION := 12.0
const GRAVITY := 9.8
const AIR_GRAVITY_MULTIPLIER := 1.6
const HEAD_BOB_FREQUENCY := 2.2
const HEAD_BOB_AMPLITUDE := 0.05
const CROUCH_HEIGHT := 0.9
const STANDING_HEIGHT := 1.8
const EYE_HEIGHT_RATIO := 0.55
const EXHAUSTION_RECOVERY := 0.3
const JUMP_VELOCITY := 5.0

# ── 彩蛋：起源引擎式连跳（Bunny Hop）──────────────────────────────
# 空中保留动量（无地面阻尼），转向沿速度切向加速（strafe 同步），
# 按住跳跃即落地自动续跳；速度有上限，防止无限加速穿墙。
const BHOP_AIR_ACCEL := 30.0
const BHOP_MAX_SPEED := 11.0

var stamina: float = 100.0
var max_stamina: float = 100.0
var stamina_drain_rate: float = 20.0
var stamina_regen_rate: float = 10.0
var is_crouching: bool = false
var is_stamina_exhausted: bool = false
var head_bob_time: float = 0.0
var last_step_count: int = 0
var flashlight_battery: float = 100.0
var flashlight_drain_rate: float = 2.0

@onready var camera: Camera3D = $Camera3D
@onready var flashlight: SpotLight3D = $Camera3D/Flashlight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio

var click_audio: AudioStreamPlayer

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flashlight.visible = false
	camera.fov = GameState.fov
	GameState.settings_changed.connect(_on_settings_changed)
	footstep_audio.stream = SoundGen.create_footstep()
	click_audio = AudioStreamPlayer.new()
	click_audio.stream = SoundGen.create_click()
	click_audio.volume_db = -10.0
	add_child(click_audio)

func _on_settings_changed() -> void:
	camera.fov = GameState.fov

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * GameState.mouse_sensitivity)
		camera.rotate_x(-event.relative.y * GameState.mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -PI / 2.0, PI / 2.0)
	if event.is_action_pressed("toggle_flashlight"):
		_toggle_flashlight()

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var bhop: bool = GameState.bhop_enabled

	if not is_on_floor():
		var gravity := GRAVITY * (AIR_GRAVITY_MULTIPLIER if velocity.y > 0.0 else 1.0)
		velocity.y -= gravity * delta
	elif Input.is_action_pressed("crouch"):
		pass
	elif bhop and Input.is_action_pressed("jump"):
		# 连跳：按住空格即落地自动续跳，无需重新点击
		velocity.y = JUMP_VELOCITY
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var current_speed := WALK_SPEED
	if Input.is_action_pressed("crouch"):
		is_crouching = true
		current_speed = CROUCH_SPEED
		_crouch()
	else:
		is_crouching = false
		_stand_up()

	if is_stamina_exhausted and stamina >= max_stamina * EXHAUSTION_RECOVERY:
		is_stamina_exhausted = false

	var can_sprint: bool = Input.is_action_pressed("sprint") and not is_crouching \
		and direction.length() > 0.5 and (bhop or not is_stamina_exhausted)

	if bhop:
		# 彩蛋模式关闭体力系统：体力锁定满值（体力条自动隐藏），冲刺无消耗
		stamina = max_stamina
		is_stamina_exhausted = false
		if can_sprint:
			current_speed = SPRINT_SPEED
	elif can_sprint:
		current_speed = SPRINT_SPEED
		stamina -= stamina_drain_rate * delta
		if stamina <= 0.0:
			stamina = 0.0
			is_stamina_exhausted = true
	else:
		stamina = minf(stamina + stamina_regen_rate * delta, max_stamina)

	stamina = clampf(stamina, 0.0, max_stamina)
	GameState.set_stamina(stamina)

	# 空中 + 起跳瞬间的那一帧都不吃地面阻尼，动量完整带进下一次跳跃
	if bhop and (not is_on_floor() or velocity.y > 0.0):
		# 空中不受地面阻尼影响，保留动量，仅按输入做切向加速（strafe）
		if direction:
			_air_accelerate(direction.normalized(), BHOP_AIR_ACCEL * delta)
		# 连跳也累计步伐节奏：否则 head_bob_time 停走，落地帧触发不了脚步声（无声疾行）
		head_bob_time += delta * HEAD_BOB_FREQUENCY * (Vector2(velocity.x, velocity.z).length() / WALK_SPEED)
	elif direction:
		velocity.x = lerpf(velocity.x, direction.x * current_speed, ACCELERATION * delta)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, ACCELERATION * delta)
		head_bob_time += delta * HEAD_BOB_FREQUENCY * (current_speed / WALK_SPEED)
	else:
		velocity.x = lerpf(velocity.x, 0.0, DECELERATION * delta)
		velocity.z = lerpf(velocity.z, 0.0, DECELERATION * delta)

	_trigger_footstep()
	_update_head_bob(delta)
	_update_flashlight(delta)
	move_and_slide()

# Source / Quake 的 AirAccelerate：只沿 wishdir 加速，速度在 wishdir
# 垂直方向的分量完整保留；wishdir 上的投影封顶 BHOP_MAX_SPEED。
# 空中转动 wishdir（strafe 同步）时，旧垂直分量 + 新方向增量矢量合成，
# 总速随跳跃逐步叠加——这正是连跳越跳越快的来源。
func _air_accelerate(wishdir: Vector3, accel: float) -> void:
	var hs := Vector3(velocity.x, 0.0, velocity.z)
	var proj := clampf(wishdir.dot(hs), 0.0, BHOP_MAX_SPEED)
	var addspeed: float = BHOP_MAX_SPEED - proj
	if addspeed <= 0.0:
		return
	# 单帧增量受 accel（= BHOP_AIR_ACCEL * delta）限幅，不能一步拉满
	hs += wishdir * minf(accel, addspeed)
	var cur := hs.length()
	if cur > BHOP_MAX_SPEED:
		hs *= BHOP_MAX_SPEED / cur
	velocity.x = hs.x
	velocity.z = hs.z

func _toggle_flashlight() -> void:
	if click_audio:
		click_audio.play()
	if flashlight_battery <= 0.0:
		flashlight.visible = false
		return
	flashlight.visible = not flashlight.visible
	GameState.set_flashlight(flashlight.visible)
	flashlight_toggled.emit(flashlight.visible)

func _trigger_footstep() -> void:
	if not is_on_floor() or velocity.length() < 1.0:
		return
	var step_count := int(head_bob_time * 2.0)
	if step_count != last_step_count:
		footstep_audio.pitch_scale = randf_range(0.85, 1.15)
		footstep_audio.play()
		last_step_count = step_count

func _update_head_bob(delta: float) -> void:
	var eye_height: float = CROUCH_HEIGHT * EYE_HEIGHT_RATIO if is_crouching else STANDING_HEIGHT * EYE_HEIGHT_RATIO
	if not is_on_floor():
		camera.position.y = lerpf(camera.position.y, eye_height, 10.0 * delta)
		return
	var bob_offset := sin(head_bob_time * PI * 2.0) * HEAD_BOB_AMPLITUDE
	camera.position.y = eye_height + bob_offset

func _crouch() -> void:
	if collision_shape.shape is CapsuleShape3D:
		collision_shape.shape.height = CROUCH_HEIGHT
		collision_shape.position.y = CROUCH_HEIGHT / 2.0

func _stand_up() -> void:
	if collision_shape.shape is CapsuleShape3D:
		collision_shape.shape.height = STANDING_HEIGHT
		collision_shape.position.y = STANDING_HEIGHT / 2.0

func _update_flashlight(delta: float) -> void:
	if flashlight.visible and flashlight_battery > 0.0:
		flashlight_battery -= flashlight_drain_rate * delta
		flashlight_battery = maxf(flashlight_battery, 0.0)
		GameState.set_flashlight_battery(flashlight_battery)
		if flashlight_battery <= 0.0:
			flashlight.visible = false
			GameState.set_flashlight(false)

func add_battery(amount: float) -> void:
	flashlight_battery = minf(flashlight_battery + amount, 100.0)
	GameState.set_flashlight_battery(flashlight_battery)

func restore_stamina(amount: float) -> void:
	stamina = minf(stamina + amount, max_stamina)
	GameState.set_stamina(stamina)

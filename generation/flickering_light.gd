extends OmniLight3D

var _base_energy: float
var _base_fog_energy: float
var _timer: Timer
# 可选：与灯光同步闪烁的自发光材质（如仓库荧光灯管）——灯灭管也灭。
# 赋值时机不限：基线亮度在首次闪烁时惰性捕获
var sync_material: StandardMaterial3D
var _sync_base := -1.0

func _ready() -> void:
	_base_energy = light_energy
	_base_fog_energy = light_volumetric_fog_energy
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_do_flicker)
	add_child(_timer)
	_timer.wait_time = randf_range(2.0, 8.0)
	_timer.start()

# 灯灭时体积光束同步熄灭，否则雾里的光柱会残留闪烁间隙
func _apply_energy(e: float) -> void:
	light_energy = e
	var ratio := 0.0 if _base_energy <= 0.0 else e / _base_energy
	light_volumetric_fog_energy = _base_fog_energy * ratio
	if sync_material:
		if _sync_base < 0.0:
			_sync_base = sync_material.emission_energy_multiplier
		sync_material.emission_energy_multiplier = _sync_base * ratio

func _do_flicker() -> void:
	var count := randi_range(2, 5)
	_flicker_step(count)

func _flicker_step(remaining: int) -> void:
	_apply_energy(0.0)
	var t1 := get_tree().create_timer(randf_range(0.03, 0.08))
	t1.timeout.connect(func():
		if not is_instance_valid(self):
			return
		_apply_energy(_base_energy)
		if remaining > 1:
			var t2 := get_tree().create_timer(randf_range(0.03, 0.08))
			t2.timeout.connect(func():
				if is_instance_valid(self):
					_flicker_step(remaining - 1)
			)
		else:
			_timer.wait_time = randf_range(3.0, 10.0)
			_timer.start()
	)

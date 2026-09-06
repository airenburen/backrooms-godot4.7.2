extends Node3D
# 环境浮尘：单个跟随玩家的 GPU 粒子场。
# local_coords=false → 粒子留在世界空间，发射盒随玩家平移，
# 全地图只需要这一个节点，开销与关卡大小无关（性能优化核心）。
# 粒子是受光的小面片（非自发光），只有灯光附近才可见，黑暗角落自动隐形。

var _target: Node3D
var _follow_height := 1.1

func setup(target: Node3D, amount: int, extents: Vector3) -> void:
	_target = target

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = extents
	proc.direction = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 0.01
	proc.initial_velocity_max = 0.08
	proc.gravity = Vector3(0, -0.015, 0)
	proc.scale_min = 0.4
	proc.scale_max = 1.8
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 0.04
	proc.turbulence_noise_scale = 4.0

	var quad := QuadMesh.new()
	quad.size = Vector2(0.032, 0.032)
	quad.material = _dust_material()

	var particles := GPUParticles3D.new()
	particles.name = "Dust"
	particles.amount = amount
	particles.lifetime = 14.0
	particles.preprocess = 14.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)
	particles.process_material = proc
	particles.draw_pass_1 = quad
	add_child(particles)

static func _dust_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.97, 0.86, 0.22)
	mat.roughness = 1.0
	mat.specular = 0.0
	return mat

func _process(_delta: float) -> void:
	if _target and is_instance_valid(_target):
		global_position = _target.global_position + Vector3(0, _follow_height, 0)

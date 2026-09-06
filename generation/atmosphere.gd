class_name Atmosphere
extends RefCounted
# 体积光（体积雾）统一配置。性能要点：
# - density 极低（0.02）：暗处几乎透明，雾只在灯光周围可见，不抬高黑位对比
# - length 40m（默认 64）：froxel 缓冲集中在室内距离，等效提高单位精度
# - gi_inject / ambient_inject = 0：室内没有 VoxelGI/SDFGI 可注入，省掉两路采样
# - sky_affect = 0：全封闭地图，跳过天空与雾的混合
# - 开关来自 GameState.volumetric_light；关闭时 froxel pass 整体不执行

static func configure(env: Environment) -> void:
	if env == null:
		return
	env.volumetric_fog_enabled = GameState.volumetric_light
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.9, 0.85, 0.68)
	env.volumetric_fog_emission = Color(0.045, 0.04, 0.025)
	env.volumetric_fog_emission_energy = 0.4
	env.volumetric_fog_anisotropy = 0.3
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.75
	_configure_ssao(env)

# SSAO 环境光遮蔽：让墙脚/柱基/地标背后有接触阴影，空间层次感↑
# Forward+ 专属；三档质量（低/中/高），低档半径小、强度弱，高档细节更多
static func _configure_ssao(env: Environment) -> void:
	env.ssao_enabled = GameState.ssao_enabled
	match GameState.ssao_quality:
		0:  # 低
			env.ssao_radius = 0.7
			env.ssao_intensity = 1.4
			env.ssao_power = 1.4
			env.ssao_detail = 0.3
		2:  # 高
			env.ssao_radius = 1.5
			env.ssao_intensity = 2.4
			env.ssao_power = 1.6
			env.ssao_detail = 0.8
		_:  # 中
			env.ssao_radius = 1.0
			env.ssao_intensity = 1.8
			env.ssao_power = 1.5
			env.ssao_detail = 0.5
	# 灯光直射区也保留一点遮蔽，避免灯下墙角完全平
	env.ssao_light_affect = 0.15

# 让一盏灯对体积雾的贡献强度（0 = 该灯不参与体积计算，最省）
static func set_fog_energy(light: Light3D, energy: float) -> void:
	light.light_volumetric_fog_energy = energy

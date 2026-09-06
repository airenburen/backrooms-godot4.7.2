class_name MaterialLib
extends RefCounted
# 材质库：优先加载 assets/textures 下的 ambientCG CC0 真实贴图，
# 缺失时回退到 FastNoiseLite 程序化纹理。
# 贴图来源: https://ambientcg.com (CC0)，见各目录 LICENSE.txt

const WALL_DIR := "res://assets/textures/Plaster001/"
const FLOOR_DIR := "res://assets/textures/Carpet001/"
const CEIL_DIR := "res://assets/textures/Fabric001/"
const PILLAR_DIR := "res://assets/textures/Concrete030/"

# ambientCG 材质物理尺寸约 2m，取倒数作为每米平铺数
const WALL_TILES_PER_M := 0.5
const FLOOR_TILES_PER_M := 0.55
const CEIL_TILES_PER_M := 0.4

static func wall_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	var loaded := _apply_pbr(m, WALL_DIR, "Plaster001_1K-JPG", WALL_TILES_PER_M)
	# 后室经典泛黄壁纸色调（贴图提供细节，色调提供氛围）
	m.albedo_color = Color(0.86, 0.79, 0.52) if loaded else Color(1, 1, 1)
	if not loaded:
		_procedural(m, 0.06, 0.12,
			Color(0.75, 0.70, 0.44), Color(0.90, 0.86, 0.60), 0.15)
	return m

static func floor_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	var loaded := _apply_pbr(m, FLOOR_DIR, "Carpet001_1K-JPG", FLOOR_TILES_PER_M)
	m.albedo_color = Color(0.60, 0.53, 0.36) if loaded else Color(1, 1, 1)
	if not loaded:
		_procedural(m, 0.45, 0.5,
			Color(0.44, 0.38, 0.28), Color(0.62, 0.54, 0.42), 0.3)
	return m

static func ceiling_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.85
	var loaded := _apply_pbr(m, CEIL_DIR, "Fabric001_1K-JPG", CEIL_TILES_PER_M)
	m.albedo_color = Color(0.80, 0.77, 0.62) if loaded else Color(1, 1, 1)
	if not loaded:
		_procedural(m, 0.15, 0.0,
			Color(0.80, 0.78, 0.72), Color(0.92, 0.90, 0.85), 0.0)
	return m

# 开阔区柱体：冷灰混凝土，与泛黄壁纸墙体形成地标对比
static func pillar_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	var loaded := _apply_pbr(m, PILLAR_DIR, "Concrete030_1K-JPG", 0.45)
	m.albedo_color = Color(0.62, 0.60, 0.55) if loaded else Color(1, 1, 1)
	if not loaded:
		_procedural(m, 0.25, 0.3,
			Color(0.42, 0.42, 0.44), Color(0.66, 0.66, 0.68), 0.25)
	return m

# 加载 Color/Normal/Roughness 贴图并启用世界三向投影（CSG 盒体无需手动调 UV）
static func _apply_pbr(m: StandardMaterial3D, dir: String, base: String, tiles_per_m: float) -> bool:
	var color := _load_tex(dir, base + "_Color.jpg")
	if color == null:
		return false
	m.albedo_texture = color
	var normal := _load_tex(dir, base + "_NormalGL.jpg")
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
	var rough := _load_tex(dir, base + "_Roughness.jpg")
	if rough:
		m.roughness = 1.0
		m.roughness_texture = rough
		m.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(tiles_per_m, tiles_per_m, tiles_per_m)
	return true

static func _load_tex(dir: String, file: String) -> Texture2D:
	var path := dir + file
	if ResourceLoader.exists(path):
		return load(path)
	return null

# —— 程序化回退 ——

static func _procedural(m: StandardMaterial3D, freq: float, nfreq: float,
		col_dark: Color, col_light: Color, bump: float) -> void:
	m.albedo_texture = _make_noise_texture(freq, col_dark, col_light)
	if bump > 0.0 and nfreq > 0.0:
		m.normal_enabled = true
		m.normal_texture = _make_normal_texture(nfreq, bump)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.35, 0.35, 0.35)

static func _make_noise_texture(freq: float, col_dark: Color, col_light: Color) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = freq
	noise.seed = randi()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([col_dark, col_light])
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256
	tex.height = 256
	tex.color_ramp = gradient
	tex.seamless = true
	return tex

static func _make_normal_texture(freq: float, bump: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = freq
	noise.seed = randi()
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256
	tex.height = 256
	tex.as_normal_map = true
	tex.bump_strength = bump
	tex.seamless = true
	return tex

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

# ── Level 0 经典重做（docs/level0_design.md）─────────────────

# 掉格吊顶：60cm 矿棉板格栅，程序化直绘（零素材依赖）
static func ceiling_grid_mat() -> StandardMaterial3D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var fn := FastNoiseLite.new()
	fn.seed = 42
	fn.frequency = 0.35
	fn.noise_type = FastNoiseLite.TYPE_VALUE
	for y in 256:
		for x in 256:
			var n: float = fn.get_noise_2d(x, y) * 0.5 + 0.5
			# 板面细噪点（矿棉颗粒）
			var c := Color(0.86, 0.85, 0.80).lerp(Color(0.79, 0.78, 0.73), n)
			# 板边 2cm 深灰格线 + 缓冲阴影带
			if x < 5 or y < 5 or x > 250 or y > 250:
				c = Color(0.30, 0.29, 0.27)
			elif x < 10 or y < 10 or x > 245 or y > 245:
				c = c.lerp(Color(0.48, 0.47, 0.45), 0.55)
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	# 一块板 60cm 见方 → 1/0.6 平铺
	m.uv1_scale = Vector3(1.0 / 0.6, 1.0 / 0.6, 1.0)
	m.roughness = 0.9
	return m

# mono-yellow 三色带：同一壁纸贴图、三种 tint 分区（黄/偏绿黄/偏土黄）
static func wall_zone_mats() -> Array[StandardMaterial3D]:
	var tints: Array[Color] = [
		Color(0.86, 0.79, 0.52),
		Color(0.78, 0.78, 0.50),
		Color(0.82, 0.74, 0.48),
	]
	var mats: Array[StandardMaterial3D] = []
	for tint in tints:
		mats.append(make_mat(WALL_DIR, "Plaster001_1K-JPG", WALL_TILES_PER_M, tint,
			Color(0.75, 0.70, 0.44), Color(0.90, 0.86, 0.60), 0.06, 0.15))
	return mats

# ── 通用材质构造（新关卡用）──────────────────────────────────
# 优先加载 ambientCG 贴图（目录约定 res://assets/textures/<ID>/），
# 缺失时回退程序化噪声。tint 仅在贴图加载成功时生效（贴图提供细节、tint 提供色调）。
static func make_mat(tex_dir: String, base: String, tiles_per_m: float, tint: Color,
		fb_dark: Color, fb_light: Color, fb_freq := 0.08, fb_bump := 0.2,
		roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = roughness
	m.metallic = metallic
	var loaded := _apply_pbr(m, tex_dir, base, tiles_per_m)
	m.albedo_color = tint if loaded else Color(1, 1, 1)
	if not loaded:
		_procedural(m, fb_freq, fb_freq * 1.5, fb_dark, fb_light, fb_bump)
	return m

# ── Level 1 仓库（混凝土 + 金属顶棚）────────────────────────
const L1_WALL_DIR := "res://assets/textures/Concrete034/"
const L1_FLOOR_DIR := "res://assets/textures/Concrete033/"
const L1_CEIL_DIR := "res://assets/textures/MetalPlates001/"
const L1_PILLAR_DIR := "res://assets/textures/Concrete031/"

static func l1_wall_mat() -> StandardMaterial3D:
	return make_mat(L1_WALL_DIR, "Concrete034_1K-JPG", 0.5, Color(0.85, 0.83, 0.78),
		Color(0.30, 0.29, 0.27), Color(0.55, 0.54, 0.52), 0.06, 0.25)

static func l1_floor_mat() -> StandardMaterial3D:
	return make_mat(L1_FLOOR_DIR, "Concrete033_1K-JPG", 0.5, Color(0.55, 0.55, 0.52),
		Color(0.22, 0.22, 0.21), Color(0.42, 0.42, 0.40), 0.05, 0.3, 0.95)

static func l1_ceiling_mat() -> StandardMaterial3D:
	# 仓库顶棚压暗：灯管周围亮、远处隐入黑暗（见 docs/level1_design.md）
	return make_mat(L1_CEIL_DIR, "MetalPlates001_1K-JPG", 0.6, Color(0.30, 0.31, 0.33),
		Color(0.08, 0.08, 0.09), Color(0.20, 0.21, 0.22), 0.1, 0.35, 0.6, 0.5)

static func l1_pillar_mat() -> StandardMaterial3D:
	return make_mat(L1_PILLAR_DIR, "Concrete031_1K-JPG", 0.45, Color(0.72, 0.71, 0.68),
		Color(0.35, 0.35, 0.34), Color(0.62, 0.62, 0.60), 0.08, 0.2)

# ── Level 2 管道层（斑驳石膏墙 + 喷涂金属顶）────────────────
# 墙面换 Plaster001：维护隧道的掉灰剥落感（见 docs/level2_design.md §2.5）
const L2_WALL_DIR := "res://assets/textures/Plaster001/"
const L2_FLOOR_DIR := "res://assets/textures/Concrete037/"
const L2_CEIL_DIR := "res://assets/textures/PaintedMetal006/"

static func l2_wall_mat() -> StandardMaterial3D:
	return make_mat(L2_WALL_DIR, "Plaster001_1K-JPG", 0.55, Color(0.52, 0.50, 0.48),
		Color(0.18, 0.17, 0.16), Color(0.36, 0.34, 0.32), 0.07, 0.3)

static func l2_floor_mat() -> StandardMaterial3D:
	return make_mat(L2_FLOOR_DIR, "Concrete037_1K-JPG", 0.55, Color(0.40, 0.42, 0.40),
		Color(0.13, 0.14, 0.13), Color(0.30, 0.32, 0.30), 0.06, 0.35, 0.95)

# 绿漆锈蚀金属板：贴图本身就是绿漆色，tint 调亮让它显色而非压灰
static func l2_ceiling_mat() -> StandardMaterial3D:
	return make_mat(L2_CEIL_DIR, "PaintedMetal006_1K-JPG", 0.6, Color(0.78, 0.82, 0.78),
		Color(0.12, 0.13, 0.12), Color(0.30, 0.32, 0.30), 0.1, 0.3, 0.6, 0.4)

# ── Poolrooms 泳室（白瓷砖墙面 + 浅蓝砖地面，釉面低粗糙）─────
const POOL_WALL_DIR := "res://assets/textures/Tiles018/"
const POOL_FLOOR_DIR := "res://assets/textures/Tiles008/"

static func pool_wall_mat() -> StandardMaterial3D:
	return make_mat(POOL_WALL_DIR, "Tiles018_1K-JPG", 0.8, Color(0.94, 0.91, 0.82),
		Color(0.78, 0.74, 0.62), Color(0.95, 0.92, 0.83), 0.02, 0.05, 0.2)

static func pool_floor_mat() -> StandardMaterial3D:
	# 经典 Level 37：全域暖奶油瓷砖，地面比墙面略深略毛
	return make_mat(POOL_WALL_DIR, "Tiles018_1K-JPG", 0.8, Color(0.88, 0.84, 0.72),
		Color(0.62, 0.58, 0.46), Color(0.86, 0.82, 0.71), 0.03, 0.08, 0.3)

# 防水格栅吊顶：冷白方格板（复用 L0 ceiling_grid_mat 思路，更亮格线更细）
static func pool_ceiling_grid_mat() -> StandardMaterial3D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var fn := FastNoiseLite.new()
	fn.seed = 7
	fn.frequency = 0.5
	fn.noise_type = FastNoiseLite.TYPE_VALUE
	for y in 256:
		for x in 256:
			var n: float = fn.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0.93, 0.94, 0.93).lerp(Color(0.86, 0.87, 0.86), n)
			# 细格线（1.5cm）+ 轻微接缝阴影
			if x < 3 or y < 3 or x > 252 or y > 252:
				c = Color(0.55, 0.56, 0.55)
			elif x < 7 or y < 7 or x > 248 or y > 248:
				c = c.lerp(Color(0.72, 0.73, 0.72), 0.5)
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(1.0 / 0.5, 1.0 / 0.5, 1.0 / 0.5)  # 50cm 见方格
	m.roughness = 0.55
	return m

# 水下焦散：世界 XZ 三层网纹随时间游动，叠在瓷砖色上（纯 shader 零贴图依赖，
# 缺瓷砖贴图时用纯色兜底）。见 docs/level_poolrooms_design.md §3.2
const CAUSTICS_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float meters_per_tile = 1.25;
uniform float caustics_strength = 0.85;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 经典焦散近似：迭代旋转坐标 + 距离场，得到游动的亮网
float caustic(vec2 p, float t) {
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 3; n++) {
		float tt = t * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
	}
	c /= 3.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 7.0), 0.0, 2.5);
}

void fragment() {
	vec2 uv = world_pos.xz / meters_per_tile;
	vec3 base = texture(albedo_tex, uv).rgb;
	float ca = caustic(world_pos.xz * 0.55, TIME * 0.5) * caustics_strength;
	// 亮网处提亮 + 青绿 tint + 降低粗糙度（像被水波聚焦的光）
	ALBEDO = base * (1.0 + ca * vec3(0.75, 1.0, 0.92));
	ROUGHNESS = clamp(0.3 - ca * 0.25, 0.03, 1.0);
}
"""

static func caustics_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CAUSTICS_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var dir := "res://assets/textures/Tiles018/"
	var albedo: Texture2D = null
	if ResourceLoader.exists(dir + "Tiles018_1K-JPG_Color.jpg"):
		albedo = load(dir + "Tiles018_1K-JPG_Color.jpg")
	else:
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.88, 0.84, 0.72))
		albedo = ImageTexture.create_from_image(img)
	m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("meters_per_tile", 1.25)
	return m

# ── Level ! 红色狂奔（锈蚀金属板，复用 L1 顶棚贴图）──────────
static func run_wall_mat() -> StandardMaterial3D:
	return make_mat(L1_CEIL_DIR, "MetalPlates001_1K-JPG", 0.6, Color(0.42, 0.20, 0.17),
		Color(0.20, 0.08, 0.07), Color(0.45, 0.22, 0.18), 0.1, 0.35, 0.6, 0.4)

static func run_floor_mat() -> StandardMaterial3D:
	return make_mat(L1_FLOOR_DIR, "Concrete033_1K-JPG", 0.5, Color(0.35, 0.18, 0.16),
		Color(0.14, 0.07, 0.06), Color(0.30, 0.16, 0.14), 0.05, 0.3, 0.85)

static func run_ceiling_mat() -> StandardMaterial3D:
	return make_mat(L1_CEIL_DIR, "MetalPlates001_1K-JPG", 0.6, Color(0.30, 0.15, 0.13),
		Color(0.10, 0.05, 0.05), Color(0.26, 0.13, 0.11), 0.1, 0.35, 0.55, 0.4)

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

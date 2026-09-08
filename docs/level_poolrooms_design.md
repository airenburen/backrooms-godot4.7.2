# Poolrooms「泳池房 / Level 37」v3 设计文档 —— 下沉泳池 · 开阔舱室 · 明亮暖阳

> 目标观感：白瓷砖砌成的无尽泳池殿，阳光从高窗斜射进来，水面晃眼；
> 每个开阔池舱中央是下沉的泳池盆（齐腰深），池缘环绕干爽瓷砖走道，
> 罗马阶梯下水，池底游走焦散光网，盆顶天花板投着游动的光斑网；
> 池中柱列从水里直通天花，宽桥洞口立着圆角大拱门，最大舱有一圈二层回廊。

## 1. 设计目标（v3 拍板结论）

v2 及更早版本的三大病根与 v3 对策：

| 病根 | v3 对策 |
|---|---|
| 全局水面 -0.12m 盖满全图 → 满地齐踝积水，没有"真泳池" | **水只存在于池盆里**：每舱内缩 2 格是干走道，中间下沉池盆；水面 -0.18 只铺在盆内 |
| 垂直关系做反（抬升干台地） | **下沉池盆**是垂直主角：浅台 -0.35 → 深水 -1.2；垂直向上只留最大舱一座二层回廊（+2.2m） |
| 大厅间 2 格窄通道 → 迷宫感 | **4~6 格宽直通桥**连接开阔池舱，长视线、无窄廊 |

基调：**明亮暖阳**（用户拍板）——白瓷砖高反光、拱窗斜射阳光、水面晃眼、焦散打天花板。

## 2. 常量速查（level_poolrooms.gd `_init` + 常量区）

```
cell_size 4.5 · wall_height 7.0 · maze_size 19（39×39 格）
DECK_TOP 0.0    干走道面（全域基准）
WATER_Y -0.18   水面（只铺在盆内）
SHELF_Y -0.35   浅台面（盆缘一圈，水面下 0.17m）
BASIN_BOTTOM -1.2  池底（水深 ~1.02m ≈ 齐腰）
GALLERY_H 2.2   二层回廊台面（仅最大舱）
light_color (1.0,0.97,0.88) · energy (2.0,2.6) · range 13 · shadow 关
暖阳 DirectionalLight (1.0,0.94,0.80) energy 1.4 rot(-35°,28°) shadow 开（全关唯一带影主光）
fill (0.60,0.64,0.62) energy 0.35 · volumetric_fog_density 0.004 · dust 150
光柱 SpotLight ≤6 束：(1.0,0.9,0.72) energy 3.0 angle 18° range 18 fog_energy 1.2
杏仁水 3（其中 1 瓶泡水）· 电池 4
```

## 3. 生成算法（poolrooms_generator.gd，舱室图 + 深度图层）

Grid 仍为 WALL/FLOOR 二值，完全兼容 MazeGenerator 接口（BFS/距离场/贴墙判定零改动）；
池盆/柱/桥作为 **grid 之上的图层**输出：

```
generate(size=19, seed)
① 撒舱：矩形 10~16 格见方、间隙 ≥3 格，目标 6~9 个（放不下逐级缩，保底 2 个）
   —— 实测 39×39 地图自然密度为 3~4 个大舱（10~16 格 ≈ 45~72m），足够开阔
② 舱内凿 FLOOR
③ 连接：中心距 Prim MST + 1~2 条随机环路；每条边沿重叠轴带凿 4~6 格宽直开口
   （对角舱退化为宽 L 形桥）；失败兜底全桥接
④ 池盆：每舱内缩 2 格（四面 2 格宽干走道）得 basin（≥5×5 才成盆，否则旱厅）；
   盆缘 1 格环 depth=1(-0.35)，盆心 depth=2(-1.2)
⑤ 池中柱：3×3 格间距柱网撒在深水区（ring≥1，避开盆缘浅台）→ col_cells
   （8×8 盆 4 根、12×12 盆 16 根，神庙式柱林）
```

输出图层：`halls / basins / bridges / col_cells / depth: PackedInt32Array`。
关键性质：池盆距舱墙 ≥2 格 → `find_farthest_floor`/`find_nearest_floor` 天然倾向走道，
落位层再做 BFS 走道校验兜底（见 §7）。

## 4. 几何装配（level_poolrooms.gd `_build_floor`）

分区域大 CSG，不逐格铺：

- **厚地板 slab**：全图一张（顶 0 / 底 -1.4），走道面即其顶面
- **每盆**（`_build_basin`）：
  1. SUBTRACT 盒凿到 -1.2（slab 底 -1.4，留 0.2 底板）
  2. 浅台：盆缘一圈 1 格宽 ADD 盒补回 -0.35（四面各一根通长盒 ×4）
  3. 池底焦散衬板：MeshInstance PlaneMesh @ -1.18（`caustics_mat`，不占 CSG 预算）
  4. 水面：**每盆一张独立 PlaneMesh quad** @ -0.18（`WATER_SHADER`，
     foam 用 UV 边缘距离 → 自动贴池缘；`mesh_size`=盆世界尺寸，foam 0.7 / wave 0.02）
  5. 盆顶焦散光网：天花下 0.05m 朝下 additive quad（`caustics_glow_mat`，纯 emission）
  6. **罗马阶梯** ×2（南北各一条）：6 级 ADD 盒，踏高 1.2/7≈0.171（玩家胶囊可攀），
     踏深 0.5、宽 2.4，最后一级落差由池底补齐
- **池中柱网**：col_cells 每格一根 CSGCylinder（r 0.45，池底直通天花）
- **二层回廊**（`_build_gallery`，仅最大舱 ≥12 格）：沿北墙 +2.2m 台面 + 临池栏墙
  + 支撑柱 + 12 级直跑楼梯（0.183m 踏高，收在段内西端，不出舱不插墙）；
  **北边界按"外侧是墙且非桥带格"分段建板**——桥口上方不停板（v3.1 修复：整行铺板
  会横跨拱门洞、水平桥带贴舱北行横穿时也会被压），段长 ≥6 格才成段；投影格并入禁放表

v3.1 修复备忘：凿盆 SUBTRACT 盒是 slab 的子节点，**必须用 slab 局部坐标**
（世界坐标会把盒子甩到地图外，坑凿不出来、地面全平）；焦散 shader 的 `caustic()`
输入须先 `mod(p, TAU) - 250.0` 折回原版魔数窗口（大坐标直接迭代发散 → 天花"水板"全白）；
回廊板格范围判定注意浮点整格线（ceil 前先扣 0.005m 容差）

CSG 实测预算 286~363（< 500）✓

## 5. 光照与材质

- **暖阳**：DirectionalLight3D（色 1.0/0.94/0.80，energy 1.4，rot -35°/28°，唯一开影灯）
- **主灯**：方灯板（嵌顶暖白）/ 吊球灯（细线 + 乳白球）50/50，energy 2.0~2.6，不开影
- **光柱**：高窗暖白 emission 板（5.0m 高）+ SpotLight 从窗口斜射厅心，≤6 束
- **白瓷砖**（material_lib）：墙 tint (0.97,0.95,0.90) roughness 0.18；
  地 tint (0.90,0.89,0.85) roughness 0.28；均基于 Tiles018 贴图 + 世界三向投影
- **焦散**（material_lib）：
  - `caustics_mat()`：世界 XZ 三层网纹 shader，叠在池底瓷砖上
  - `caustics_glow_mat()`：additive emission 光斑网，投在盆顶天花上
- **雾/尘**：fog 0.004（薄，光柱可见不糊）、dust 150

## 6. 装修件

- **圆角大拱门**（桥口签名）：桥口（4~8 格宽开口、两端有墙夹）立一块通高瓷砖板，
  SUBTRACT 大矩形洞（洞顶 5.2m - 角半径）+ 两角半圆柱 → 圆角大门洞，两侧自然留 0.9m 门垛
- **高窗光柱**：每舱随机一侧贴 3 块暖白 emission 窗板（5.0m），60% 配斜射 SpotLight
- **墙上黑洞口**（≤3 处）：`_emit_wall` 钩子，长墙凿 0.9×1.35 黑洞 + 黑背板封死
- **格栅吊顶**：`pool_ceiling_grid_mat()` 冷白 50cm 方格

## 7. 落位规则

- `_is_walkway(cell)`：`depth_at == 0` 且非柱格
- 出生/出口：`find_nearest_floor`/`find_farthest_floor` 结果过 `_nearest_walkway` BFS 校验
- 地标/拾取物禁放：非走道格 + 回廊/楼梯投影格（`_gallery_cells`）
- **泡水杏仁水**（设计亮点）：`_spawn_pickups` 覆盖——走道放 2 杏仁水 + 4 电池
  （间距规则沿用基类），第 3 瓶放最大盆中心深水格、y = WATER_Y + 0.08 浮在水面，
  玩家得下水捞
- `_landmark_y_offset` 恒 0（全域单层走道，回廊不放东西）

## 8. 钩子映射

| 内容 | 位置 |
|---|---|
| 舱室图 + 深度图层 | poolrooms_generator.gd（覆盖 generate，其余继承） |
| 厚地板 + 凿盆 + 浅台 + 阶梯 + 水面 + 顶焦散 | level_poolrooms.gd `_build_floor` / `_build_basin` |
| 池中柱列 / 二层回廊 | `_build_floor` / `_build_gallery` |
| 暖阳 + 方灯板/吊球灯 | `_place_lights` 覆盖 |
| 黑洞口 | `_emit_wall` 覆盖 |
| 高窗光柱 / 大拱门 | `_custom_build` |
| 出生/出口走道校验 | `_position_player` / `_pick_exit_cell` / `_nearest_walkway` |
| 泡水杏仁水 | `_spawn_pickups` / `_submerged_cell` 覆盖 |
| 白瓷砖 / 焦散 glow | material_lib.gd `pool_*` 调参 + `caustics_glow_mat()` |

## 9. 验证清单

已做（diag_poolrooms.gd，5 种子 + 1 重放，DIAG ALL PASS，验完即删）：

- 舱数 ≥2、盆数 ≥1；spawn/exit 落走道且不在柱格
- 水面 quad / 顶焦散 quad == 盆数；罗马阶梯 12/盆、浅台盒 4/盆、池中柱 == col_cells
- CSG ≤ 500（实测 286~363）；平行光 2（暖阳 + fill）；光柱 ≤6；Omni ≥1
- 拾取物 3 杏仁（含 1 瓶泡水 y≈-0.10）+ 4 电池；同种子重放生成层一致
- 全程零 SCRIPT ERROR

人工试玩清单：亮度和水面观感、蹚水入池、罗马阶梯上下、泡水杏仁水可拾取、
出口在走道、拱门与光柱氛围、二层回廊楼梯可上、池缘泡沫贴边。

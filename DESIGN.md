# Backrooms Prototype - 设计文档

> Godot 4.7.2 | Forward+ 渲染器 | 第一人称恐怖探索游戏

---

## 项目概述

基于「后室」（Backrooms）世界观的第一人称恐怖探索游戏原型。
玩家被随机切入 **Level 0**（黄色迷宫房间），需要收集杏仁水、找到出口，逐层深入五个风格各异的阈限空间：

`Level 0 黄色迷宫 → Level 1 无尽仓库 → Level 2 管道之梦 → Poolrooms 泳室 → Level ! 红色狂奔`

每关出口需要先集齐 **3 瓶杏仁水**（靠近按 E 拾取）才会放行；手电筒电池散落在地图上，碰到即自动充能。

---

## 文件结构

```
res://
├── project.godot                    # 项目配置（输入映射、自动加载、渲染器）
├── icon.svg                         # 项目图标
├── assets/
│   └── textures/                    # ambientCG CC0 真实贴图（墙/地板/天花板/柱）
├── autoload/
│   ├── game_state.gd                # 全局状态（关卡进度/体力/手电/杏仁水/设置信号）
│   └── loader.gd                    # 场景切换加载遮罩（掩盖程序化生成卡顿帧）
├── generation/
│   ├── maze_generator.gd            # 迷宫生成（回溯+环路+房间+死端编织+柱体+距离场）
│   ├── material_lib.gd              # 材质库（真实贴图优先，程序化纹理回退，五关套装）
│   ├── landmark_breadcrumb.gd       # 弱引导地标（黑碑/门框/信标，8 形态贴墙/落地）
│   ├── pickup_item.gd               # 拾取物（杏仁水 E 拾取 / 电池自动拾取）
│   ├── atmosphere.gd                # 体积雾（体积光）+ SSAO 统一配置
│   ├── dust_field.gd                # 跟随玩家的 GPU 浮尘粒子场
│   ├── flickering_light.gd          # 闪烁日光灯脚本
│   └── sound_generator.gd           # 程序化音效（脚步/嗡鸣/点击/嘶嘶/滴水/低吼）
├── levels/
│   ├── level_base.gd                # 关卡基类（全部装配流程 + 可覆盖钩子）
│   ├── level_0.gd / level_0.tscn    # Level 0 黄色迷宫
│   ├── level_1.gd / level_1.tscn    # Level 1 无尽仓库
│   ├── level_2.gd / level_2.tscn    # Level 2 管道之梦
│   ├── level_poolrooms.gd / .tscn   # Poolrooms 泳室
│   ├── level_run.gd / level_run.tscn# Level ! 红色狂奔
│   ├── level0_generator.gd          # L0 房间簇生成器
│   ├── poolrooms_generator.gd       # 泳室大厅生成器（互不重叠）
│   └── warehouse_generator.gd       # L1 仓库网格生成器
├── main/
│   ├── main.tscn / main.gd          # 游戏主场景（按 current_level 装配关卡）
│   ├── main_menu.tscn / main_menu.gd# 开始菜单（含科乐美秘技彩蛋）
│   └── level_select.tscn / .gd      # 关卡选择界面（自选/继续/重开）
├── player/
│   ├── player.tscn                  # 玩家场景（CharacterBody3D + Camera + Flashlight）
│   └── player.gd                    # 第一人称控制器
├── ui/
│   ├── hud.tscn / hud.gd            # HUD（准星/体力/电量/提示/任务面板/红脉冲暗角）
│   ├── pause_menu.tscn              # 暂停菜单（半透明遮罩 + 按钮组）
│   ├── settings_menu.tscn / .gd     # 设置面板
└── docs/                            # 各关卡独立设计文档
    ├── level0_design.md / level1_design.md / level2_design.md
    ├── level_poolrooms_design.md / level_run_design.md
```

---

## 已实现系统

### 1. 玩家控制（player/player.gd）

| 功能 | 按键 | 说明 |
|------|------|------|
| 移动 | W / A / S / D | 3.5 m/s |
| 冲刺 | Shift | 6.5 m/s，消耗体力 |
| 蹲伏 | Ctrl | 1.8 m/s，降低碰撞体高度 |
| 手电筒 | F | SpotLight3D，消耗电量 |
| 跳跃 | Space | 5.0 m/s 起跳速度，短滞空，蹲伏时不可跳 |
| 暂停 | Esc | 打开暂停菜单 |
| 交互 | E | 拾取杏仁水（2.6m 内出现提示） |

**详细参数：**

| 参数 | 值 |
|------|-----|
| 行走速度 | 3.5 m/s |
| 冲刺速度 | 6.5 m/s |
| 蹲伏速度 | 1.8 m/s |
| 加速度 | 10.0 |
| 减速度 | 12.0 |
| 重力 | 9.8 |
| 鼠标灵敏度 | 0.002（可调） |
| 头部晃动频率 | 2.2 |
| 头部晃动幅度 | 0.05 |
| 体力上限 | 100 |
| 体力消耗 | 20/s（冲刺时） |
| 体力恢复 | 10/s |
| 手电筒电量上限 | 100 |
| 电量消耗 | 2/s（开启时） |
| 视野角 | 75°（可调） |
| 手电筒射程 | 20m |
| 手电筒角度 | 35° |
| 碰撞体 | CapsuleShape3D r=0.4 h=1.8 |
| 跳跃初速 | 5.0 m/s |
| 空中重力倍率 | 1.6x（仅上升阶段） |
| 滞空时间 | ~0.72s |
| 力竭恢复阈值 | 30% 最大体力 |

**头部晃动：** 基于移动速度的正弦波，站立时眼睛高度 0.99m，蹲伏时 0.495m。

**体力力竭机制：** 体力降为 0 后进入力竭状态，无法冲刺。需恢复到 30%（约 3 秒）后才能再次冲刺。防止了体力在 0 附近振荡导致的无限冲刺 bug。

**手电电池：** `add_battery(amount)` 被拾取物调用，电池 +35% 电量。

---

### 2. 多关卡系统（autoload/game_state.gd）

- **关卡表** `LEVEL_SCENES`：五关线性推进（见顶部流程图），每关配 `LEVEL_TITLES` / `LEVEL_DESCS` 供菜单展示
- **进度持久化**：`current_level` 存于 `user://settings.cfg` 的 `[progress]` 节，退出游戏后继续游玩仍回到当前关
- **布局种子持久化**：每关首次进入时生成 `seed_N` 存 `[progress]` 节，之后同关一律复用 → 「继续游戏」回到一模一样的布局；「重新开始」才换新种子（新的一局新布局）
- **`start_level(i)`**：关卡选择界面直接跳到任意关（自用项目全开放，不锁关）
- **`advance_level()`**：出口触发后推进；末关通关回主菜单并归零（继续游戏 = 从头再来）
- **`reset()`**：只重置局内状态（体力/电量/杏仁水），不动关卡进度

**场景切换（autoload/loader.gd）：** 关卡程序化生成有卡顿帧，`Loader.go_to(path)` 用全屏遮罩（"正在进入下一层…"）盖住切场景帧：遮罩秒显 → 等 2 帧 → 切场景 → 等 2 帧 → 淡出。autoload 常驻，暂停态也能切场景。

---

### 3. 关卡基类与装配（levels/level_base.gd）

全部迷宫类关卡共享一条装配流水线，在 `_ready()` 顺序执行：

```
创建材质 → 配置氛围 → 生成迷宫 → 地板/天花板 → 薄墙 → 布灯 → 补光
→ 定位玩家 → 放置出口 → 放置地标 → 刷拾取物 → 浮尘 → 附加装修 → 环境嗡鸣
```

**子类定制三件套：** 子类只配 `var` 覆盖观感参数（格子尺寸/层高/灯色/雾浓等），通过钩子改行为：

| 钩子 | 默认行为 | 覆盖示例 |
|------|----------|----------|
| `_generate_maze(m)` | `MazeGenerator` | L0 房间簇 / L1 仓库网格 / 泳室大厅 / Run 手填直道 |
| `_create_materials()` | Level 0 黄墙套装 | 各关独立材质套装 |
| `_emit_wall(...)` | 合并墙段（返回 `CSGBox3D`） | L2 挂管线 / 泳室凿拱洞黑洞口 |
| `_place_lights()` | 贪心覆盖顶灯 | Run 侧壁红灯 + 熄灭序列 |
| `_custom_build()` | 无 | 仓库货箱 / 泳室水面台地 / Run 路障 |
| `_pick_exit_cell()` | 最远地板格 | 泳室强制下层（台地上不去会 3D 死局） |
| `_landmark_y_offset()` | 0 | 泳室按格查层（台面/干岛/地面） |
| `_landmark_blocked()` / `_pickup_blocked()` | 全放行 | 泳室排除泳池/柱/台地 |

**薄墙算法（`_build_thin_walls` / `_build_pillars`）：** 收集每个 WALL 格面向 FLOOR 的边，同一条网格线上连续边合并成整段隔墙（CSGBox3D，厚 `WALL_THICK=0.28m`），转角端头各外扩半厚闭合缝隙；开阔区柱体（`pillar_cells`）跳过薄墙，在格中心立 1.2m 居中方柱。

**出口闸门（`_on_exit_door_entered`）：** 只认 `CharacterBody3D`（检测盒与墙体重叠，早返回防 StaticBody3D 触发无限重载）；杏仁水没集齐时出口纹丝不动并提示「似乎还差 N 瓶」；集齐后 2 秒延迟 `advance_level()` → `Loader.go_to` 切关。

---

### 4. 五个关卡

每关有独立设计文档（`docs/`），此处只给纲领：

| 关卡 | 场景 | 观感关键词 | 结构 | 签名景观 |
|------|------|------------|------|----------|
| **Level 0** | 黄色迷宫 | mono-yellow 三色区、吊顶格栅灯、踢脚线 | 房间簇迷宫（12×12 格） | 靠墙装饰梯、墙皮撕裂露水泥、黑暗洞口出口 |
| **Level 1** | 无尽仓库 | 积水镜面、闪烁荧光灯、薄雾、货架 | 29×29 开放网格 + 规则柱网 + 隔墙 | 墙上水管、湿地面 shader、仓库指示牌贴墙 |
| **Level 2** | 管道之梦 | 狭窄低顶、巨管、蒸汽嘶声、隧道混响 | 13×13 迷宫、3.4m 窄廊 | 红手轮阀喷蒸汽、三态老荧光灯、顶部干线管 |
| **Poolrooms** | 泳室 | 无尽白瓷砖、齐踝静水、水下焦散 | 17×17 大厅群（互不重叠） | 圆拱门套、上层台地 + 大楼梯、高窗光柱、水中干岛 |
| **Level !** | 红色狂奔 | 湿黑镜面、暗红应急灯、客房门 | 4×49 直道 ≈ 165m | 翻倒文件柜/长桌路障、灯一盏盏熄灭、尽头绿 EXIT |

**Level ! 追逐机制（方案 A 纯氛围）：** 没有实体、没有寻路，靠「看不见的追逐」制造压迫：
- **灯光熄灭**：玩家身后 7m 外的灯逐盏灭掉，黑暗追着脚步蔓延
- **低吼**：`SoundGen.create_entity_growl()` 循环，音量随进度 -38→-7dB、音高 0.9→1.18（它追上来了）
- **屏幕红脉冲**：HUD 边缘暗角 shader，越接近出口越红、心跳越快（见 §11）

---

### 5. 程序化迷宫生成（generation/maze_generator.gd + 各关生成器）

**基础算法（MazeGenerator）：** 递归回溯（DFS）+ 随机环路 + 矩形房间 + 死端编织 + 假分支 + 开阔区柱体 + BFS 距离场

| 参数 | 值 | 说明 |
|------|-----|------|
| 环路概率 | 14% | 打破完美迷宫 |
| 柱体移除概率 | 6% | 产生开阔区域 |
| 房间数量 | 3-5 个 | 2~5 格矩形 |
| 死端编织率 | 60% | 消除死胡同 |
| 假分支 | ≤6 条×50% 概率 | 点缀式迷惑死岔路 |
| 柱体散布概率 | 4% | 开阔区地标柱 |

**关键方法：** `is_floor/is_wall`、`find_nearest_floor`（BFS）、`find_farthest_floor`（最短路最远且可贴门）、`get_all_floor_cells`、`compute_distance_field(exit)`（出口 BFS 距离场）、`get_guidance_dir(cell)`（梯度指向出口）、`dist_at(cell)`。

**专用生成器（均继承同一网格接口）：**
- `level0_generator.gd`：房间簇（4~6 个矩形房间 + 连通走廊），L0 的「迷宫办公室」感
- `warehouse_generator.gd`：29×29 开放网格，规则柱网 + 横向/纵向隔墙段（货架感）
- `poolrooms_generator.gd`：互不重叠的大厅群，L 形/方形，天然通道开口——泳室「无限大厅」感

---

### 6. 收集系统（generation/pickup_item.gd）

| 物品 | 拾取方式 | 作用 | 约束 |
|------|----------|------|------|
| **杏仁水** | 靠近按 E（2.6m 提示） | 出口前提（每关 3 瓶） | 离出生 ≥3 格、离出口 ≥2 格、互相 ≥4 格、避开阻挡格 |
| **电池** | 碰到自动拾取 | 手电 +35% 电量 | 每关 4 个，同上约束 |

杏仁水外观：半透明白玻璃瓶 + 蓝盖 + 内液 + 微光，缓慢旋转浮动。`GameState.reset_almond_progress()` 进关清零并设定本关需求；`add_almond_water()` 计数并广播 HUD 任务面板。

---

### 7. 弱引导地标（_place_landmarks + landmark_breadcrumb.gd）

沿通往出口的路（梯度追踪最短路）在**关键决策点**放与环境反差的小结构，靠形态/颜色/微光把人自然往前带，不指路只吸引：

- **时机**：三岔/四岔路口必放（`_opening_count≥3`，相邻至少隔 3 格）；直行段每 `guide_step` 格兜底
- **形态**：黑碑 / 门框 / 信标三大类 × 贴墙/落地多状态（共 8 形态），随机轮换避免规律感
- **弱化手段**：点光能量仅 0.5/射程 3m；起点 2 格内与出口前一格不放

**贴墙坐标规则：** 梯子/地标这类贴墙装饰，旋转后局部 X = 墙法线（厚度方向）、局部 Z = 墙切线（展开方向），立柱间距和横档/展开长度必须摆在局部 Z 上——摆错会整件戳进墙里（lv0 梯子嵌墙 bug 的教训，见 `_build_ladder` 注释）。

---

### 8. 材质库（generation/material_lib.gd）

**优先加载 ambientCG CC0 真实贴图**（Color + NormalGL + Roughness 1K-JPG 三件套），**缺失时自动回退**程序化纹理。各关独立套装：

| 套装 | 入口 | 贴图 | 观感 |
|------|------|------|------|
| Level 0 | `wall_mat/floor_mat/...` | Plaster001/Carpet001/Fabric001/Concrete030 | 经典黄墙 |
| Level 0 分区 | `wall_zone_mats()` | Plaster001 三色 tint | mono-yellow 分区 |
| Level 1 | `l1_*` | Concrete033 系 + 深色湿润 | 仓库灰 |
| Level 2 | `l2_*` | Plaster001 压暗 + 霉斑色带 | 斑驳石膏 |
| Poolrooms | `pool_*` | Tiles018 白瓷砖 + 格栅顶 | 泳室 |
| Level ! | `run_*` | Concrete033 近黑红 | 血色酒店 |

- 全部启用 `uv1_world_triplanar` 世界三向投影
- **泳室水面/焦散**：`pool_floor_mat` 用焦散 shader（`caustics_mat()`，水下光网）+ 独立水面 shader（波动法线 + 菲涅尔 + 岸边泡沫）
- **Level ! 湿黑地面**：`RUN_WET_SHADER`——近黑红基色 + 全湿镜面（roughness 0.03），红灯拉成长条反光
- **Level 1 积水**：水面掩码 shader，斑驳水洼 + 反射

---

### 9. 程序化音效（generation/sound_generator.gd）

`AudioStreamWAV` + 数学波形运行时生成（16-bit PCM, 44100Hz, 单声道）：

| 音效 | 波形组成 | 用途 |
|------|----------|------|
| 脚步声 | 60Hz 正弦 + 白噪，指数衰减 | 移动，音调随机 ±15% |
| 环境嗡鸣 | 100/200/300Hz 叠加 + 微噪 | 各关常驻背景 |
| 手电筒点击 | 白噪，三次方衰减 | 开关/拾取反馈 |
| **嘶嘶声** | 白噪 + 带通，长尾 | L2 蒸汽阀门 |
| **滴水声** | 短正弦 + 高频噪 | L2 随机 4~8s 一滴 |
| **实体低吼** | 低频方波 + 颤音 | Level ! 追逐（音量/音高随进度） |

**L2 隧道混响：** `AudioEffectReverb`（room_size 0.9 / wet 0.15）挂在 Master bus，`tree_exiting` 时自动摘除，场景重载不叠加。

---

### 10. 后室氛围（WorldEnvironment + generation/atmosphere.gd）

| 参数 | 值 |
|------|-----|
| 环境光颜色 | (0.2, 0.18, 0.12) 暗黄 |
| 环境光能量 | 0.4 |
| 色调映射 | Filmic |
| 辉光 | 强度 0.3，泛光 0.1 |
| 亮度/对比度/饱和度 | 0.9 / 1.1 / 0.8 |

**体积光（体积雾）：** density 极低（0.01~0.035 随关卡）、length 40m、gi_inject/ambient_inject/sky_affect = 0；顶灯 `light_volumetric_fog_energy=0.8` 在雾中成光柱，补光设 0 避免整体发灰。项目体积 96×64（省 GPU）。设置面板可开关。

**环境浮尘：** 全场景单个 `GPUParticles3D`，`local_coords=false` 跟随玩家平移（开销与地图大小无关）；700 粒（菜单 250），受光小面片暗角自动隐形；闪烁灯同步熄灭浮尘亮度。

**SSAO：** 三档（低/中/高）映射 radius/intensity/power/detail，`light_affect=0.15` 保留灯下细节，墙脚/柱基接触阴影。

**抗锯齿（11 挡）：** FXAA / SMAA / MSAA 2-8× / TAA / MSAA+TAA / FSR2 / SSAA 2.25-4×，全为根视口属性实时切换。默认 MSAA 4×。

---

### 11. HUD 界面（ui/hud.tscn + hud.gd）

| 元素 | 类型 | 说明 |
|------|------|------|
| 十字准星 | ColorRect | 4×4px 半透明白，屏幕居中 |
| 体力条 | ProgressBar | 200×12px，体力满时隐藏 |
| 手电筒标签 | Label | 开关状态 + 电量百分比 |
| 提示标签 | Label | 居中，4 秒后淡出 |
| **任务面板** | VBoxContainer | 屏幕右侧：「杏仁水 x/3」，集齐变绿带 ✓，需求 0 时整块隐藏 |
| **拾取提示** | Label | 靠近杏仁水时「按 [E] 拾取」，离开即清 |
| **红脉冲暗角** | ColorRect + shader | Level ! 专用：边缘暗角红闪（心跳感），越接近出口越红越快；非追逐关隐藏 |

---

### 12. 暂停 / 设置 / 关卡选择 / 主菜单

**暂停菜单：** Esc 暂停（`get_tree().paused = true`）；继续/设置/重新开始/返回主界面/退出。设置面板打开时 Esc 先关面板并保存（分层）。`process_mode = ALWAYS`，layer 10（设置 11）。

**设置面板：** 灵敏度 / FOV / 主音量 / 全屏 / 体积光 / 浮尘 / 抗锯齿 11 挡 / SSAO 开关 + 三档，全部实时生效 + 即时保存到 `user://settings.cfg`。

**主菜单（main_menu.gd）：** 程序化构建 Level 0 走廊背景（真实贴图 + 闪烁灯 + 嗡鸣）+ 相机呼吸晃动；按钮组 + 关卡选择。含科乐美秘技彩蛋「上上下下左右左右 BABA」解锁连跳（带试错宽容、失败提示、弹窗反馈）。

**关卡选择（level_select.gd）：** 左侧「继续游戏（当前进度）/ 重新开始 / 返回」，右侧五张关卡卡片（标题 + 一句话描述），点击即从该关开始。全开放不锁关。

---

### 13. 输入映射（project.godot）

| 动作 | 键 | 物理键码 |
|------|-----|----------|
| move_forward | W | 87 |
| move_back | S | 83 |
| move_left | A | 65 |
| move_right | D | 68 |
| sprint | Shift | 4194325 |
| crouch | Ctrl | 4194326 |
| toggle_flashlight | F | 70 |
| jump | Space | 32 |
| interact | E | 69（拾取杏仁水） |
| pause | Esc | 4194305 |

---

## 场景层级

```
Main (main.tscn)
├── Level (Node3D)               # main.gd 按 GameState.current_level 动态实例化关卡
├── Player (player.tscn)
│   ├── CollisionShape3D (CapsuleShape3D)
│   ├── Camera3D └── Flashlight (SpotLight3D)
│   └── FootstepAudio
├── HUD (hud.tscn)
│   ├── Vignette (ColorRect + shader, 追逐暗角)
│   ├── Crosshair (ColorRect)
│   ├── MarginContainer → 体力条 / 电量 / 提示
│   ├── TaskPanel → 目标 / 杏仁水进度
│   └── PickupPrompt
└── PauseMenu (pause_menu.tscn)

关卡实例（level_*.tscn 动态生成，以 level_0 为例）
└── level_0 (level_0.gd)
    ├── WorldEnvironment
    ├── Floor / Ceiling (CSGBox3D)
    ├── Walls (Node3D) → [合并薄墙 × N] + [柱体 × M]
    ├── Lights (Node3D) → [OmniLight3D + 自发光面板]
    ├── AmbientFill (DirectionalLight3D)
    ├── Pickups (Node3D) → [杏仁水/电池 Area3D]
    ├── Landmarks (Node3D) → [地标 × N]
    ├── DustField (GPUParticles3D)
    ├── ExitDoor (Area3D) → Portal + EXIT 标签
    └── Decor (Node3D) → [梯子等附加装修]
```

---

## 运行方式

1. 打开 `C:\Users\Lenovo\Documents\godothub\engine\4.7.2-stable\godot.exe`
2. 导入项目 `D:\杂类\后室-godot4.7.2\project.godot`
3. 按 **F5** 运行（主场景 `main/main_menu.tscn`）

**命令行运行：**
```
C:\Users\Lenovo\Documents\godothub\engine\4.7.2-stable\godot.exe --path "D:\杂类\后室-godot4.7.2"
```

**Headless 验证（六场景扫描）：**
```
godot.exe --headless --path . --quit-after 90 res://main/main.tscn
godot.exe --headless --path . --quit-after 90 res://levels/level_2.tscn
```

---

## 开发路线图

### Phase 1：原型验证 ✅ 已完成
- [x] 项目搭建，Godot 4.7.2 配置
- [x] 第一人称玩家控制（移动/冲刺/蹲伏/跳跃/头部晃动/体力力竭）
- [x] 程序化迷宫生成（回溯+环路+房间+死端编织+假分支+柱体+距离场）
- [x] 灯光覆盖系统（零死角 + 闪烁灯 + 自发光面板）
- [x] 手电筒系统（电量消耗 / 开关 / 聚光灯 / 电池充能）
- [x] 后室氛围（体积光 / 浮尘 / SSAO / 抗锯齿 11 挡）
- [x] 材质库（ambientCG 真实贴图 + 程序化回退）
- [x] HUD / 暂停 / 设置 / 开始菜单 / 场景切换遮罩

### Phase 2：核心玩法 ✅ 大部分完成
- [x] **五关线性推进**（L0 迷宫 / L1 仓库 / L2 管道 / Poolrooms 泳室 / Level ! 狂奔）
- [x] **关卡基类 + 钩子系统**（子类只配参数与覆盖行为）
- [x] **收集系统**（杏仁水 E 拾取为出口前提 + 电池自动充能 + 任务面板）
- [x] **关卡选择界面**（自选/继续/重开）+ 进度持久化
- [x] **Level ! 追逐氛围**（灯光熄灭 + 低吼渐强 + 屏幕红脉冲）
- [x] **程序化环境音**（嘶嘶 / 滴水 / 低吼 / 隧道混响）
- [ ] 实体 AI（至少 1 种：巡逻型 / 追猎型）
- [ ] NavigationServer3D 导航网格
- [ ] VHS 后处理 Shader（扫描线 / 噪点 / 色差）
- [ ] 死亡 / 重生系统

### Phase 3：内容与打磨 ⬜ 未开始
- [ ] 3 种以上实体
- [ ] 完整音频体系（环境音乐、更多音效）
- [ ] 难度分级 / 成就系统

### Phase 4：扩展 ⬜ 未开始
- [ ] 联机合作（ENet / Steam）
- [ ] Steam 页面上架

---

## 已知限制

- VHS 后处理 Shader 未添加
- 实体 AI 未实现（Level ! 的追逐是纯氛围，没有实际追猎者）
- CSGBox3D 用于所有几何体，大型关卡（泳室 17×17、仓库 29×29）构建耗时随格数上升；如需进一步扩图建议换 MeshInstance3D + StaticBody3D
- Level ! 的「灯灭」是每盏灯整体隐藏，无单独的光线渐隐过渡
- 关卡内唯一入口是出口闸门，未做「跌落深池/被追到」等失败状态

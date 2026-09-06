# Backrooms Prototype - 设计文档

> Godot 4.7.2 | Forward+ 渲染器 | 第一人称恐怖探索游戏

---

## 项目概述

基于「后室」（Backrooms）世界观的第一人称恐怖探索游戏原型。
玩家被随机切入 Level 0（黄色迷宫房间），需要找到发光的 EXIT 出口逃脱。

---

## 文件结构

```
res://
├── project.godot                    # 项目配置（输入映射、自动加载、渲染器）
├── icon.svg                         # 项目图标
├── assets/
│   └── textures/                    # ambientCG CC0 真实贴图（墙/地板/天花板/柱）
├── autoload/
│   └── game_state.gd                # 全局状态管理器（体力/手电/提示/设置信号）
├── generation/
│   ├── maze_generator.gd            # 迷宫生成（回溯+环路+房间+死端编织+柱体+距离场）
│   ├── material_lib.gd              # 材质库（真实贴图优先，程序化纹理回退）
│   ├── landmark_breadcrumb.gd      # 弱引导地标（黑碑/门框/信标，沿途吸引前进）
│   ├── atmosphere.gd                # 体积雾（体积光）统一配置
│   ├── dust_field.gd                # 跟随玩家的 GPU 浮尘粒子场
│   ├── flickering_light.gd          # 闪烁日光灯脚本
│   └── sound_generator.gd           # 程序化音效生成器
├── levels/
│   ├── level_0.tscn                 # Level 0 场景（仅 WorldEnvironment）
│   └── level_0.gd                   # 程序化关卡构建器
├── main/
│   ├── main.tscn                    # 游戏主场景（Level + Player + HUD + PauseMenu）
│   └── main.gd                      # 游戏主入口脚本
│   ├── main_menu.tscn               # 开始菜单场景
│   └── main_menu.gd                 # 开始菜单逻辑
├── player/
│   ├── player.tscn                  # 玩家场景（CharacterBody3D + Camera + Flashlight）
│   └── player.gd                    # 第一人称控制器
└── ui/
    ├── hud.tscn                     # HUD 界面（准星、体力条、电量、提示）
    ├── hud.gd                       # HUD 更新逻辑
    ├── pause_menu.tscn              # 暂停菜单（半透明遮罩 + 按钮组）
    ├── settings_menu.tscn           # 设置面板
    └── settings_menu.gd             # 设置逻辑
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
| 跳跃 | Space | 5.0 m/s 起跳速度，短滞空，蹲伏时不可跳
| 暂停 | Esc | 打开暂停菜单 |
| 交互（预留） | E | 射线检测，目前未使用 |

**详细参数：**

| 参数 | 值 |
|------|-----|
| 行走速度 | 3.5 m/s |
| 冲刺速度 | 6.5 m/s |
| 蹲伏速度 | 1.8 m/s |
| 加速度 | 10.0 |
| 减速度 | 12.0 |
| 重力 | 9.8 |
| 鼠标灵敏度 | 0.002 |
| 头部晃动频率 | 2.2 |
| 头部晃动幅度 | 0.05 |
| 体力上限 | 100 |
| 体力消耗 | 20/s（冲刺时） |
| 体力恢复 | 10/s |
| 手电筒电量上限 | 100 |
| 电量消耗 | 2/s（开启时） |
| 视野角 | 75° |
| 手电筒射程 | 20m |
| 手电筒角度 | 35° |
| 碰撞体 | CapsuleShape3D r=0.4 h=1.8 |
| 跳跃初速 | 5.0 m/s
| 空中重力倍率 | 1.6x（仅上升阶段） |
| 滞空时间 | ~0.72s | |
| 力竭恢复阈值 | 30% 最大体力 |

**头部晃动：** 基于移动速度的正弦波，站立时眼睛高度 0.99m，蹲伏时 0.495m。

**空中头部表现： 滞空时头部晃动暂停，相机平滑回归眼高，落地后恢复晃动。

**体力力竭机制：** 体力降为 0 后进入力竭状态，无法冲刺。需恢复到 30%（约 3 秒）后才能再次冲刺。防止了体力在 0 附近振荡导致的无限冲刺 bug。

---

### 2. 程序化迷宫生成（generation/maze_generator.gd）

**算法：** 递归回溯（DFS）+ 随机环路 + 矩形房间 + 死端编织 + 假分支 + 开阔区柱体 + BFS 距离场

**生成流程：**
1. 初始化 (2N+1)×(2N+1) 网格，全部填充为 WALL
2. 从 (1,1) 开始 DFS，随机探索相邻的未访问单元格（间隔 2 格），移除中间墙壁
3. 追加环路：以 14% 概率移除水平/垂直墙壁；以 6% 概率移除柱体（偶数坐标交叉点）
4. 开凿房间：3-5 个 2~5 格矩形大厅，打破单一走廊结构
5. 死端编织：约 60% 的死胡同尽头打通到相邻通道，形成「无限回廊」循环感
6. 假分支：在走廊侧壁开出 1-2 格短岔路（看得见、走进去是死路），**全图最多 6 条且逐条 50% 概率**，只作点缀迷惑不压垮可解性
7. 散布柱体：在四面通透的开阔格放 1×1 独立柱（记录到 `pillar_cells`）；撒完后做全图连通性校验，若切断通路则全部撤销
8. 出口确定后 `compute_distance_field()` 做 BFS 距离场，供地标引导沿路放置

**参数：**

| 参数 | 值 | 说明 |
|------|-----|------|
| MAZE_SIZE | 11 | 逻辑迷宫大小 |
| 网格尺寸 | 23×23 | (2×11+1) |
| 实际面积 | 92×92 米 | 23×4m |
| 单元格尺寸 | 4×4 米 | 走廊宽度 |
| 环路概率 | 14% | 打破完美迷宫 |
| 柱体移除概率 | 6% | 产生开阔区域 |
| 房间数量 | 3-5 个 | 2~5 格矩形 |
| 死端编织率 | 60% | 消除死胡同 |
| 假分支 | ≤6 条×50% 概率 | 点缀式迷惑死岔路（旧版无上限导致上百条，迷路主因） |
| 柱体散布概率 | 4% | 开阔区地标柱 |

**关键方法：**

| 方法 | 说明 |
|------|------|
| `generate(size, seed)` | 生成迷宫，seed=-1 使用全局随机 |
| `is_floor(x, y)` / `is_wall(x, y)` | 判断格子属性 |
| `find_nearest_floor(target)` | BFS 查找最近的 FLOOR 格 |
| `find_farthest_floor(from)` | BFS 返回距 from 最远且可贴门（有墙邻接）的 FLOOR 格，用于把出口放到头 |
| `get_all_floor_cells()` | 返回所有 FLOOR 格坐标列表 |
| `compute_distance_field(exit)` | 从出口 BFS，填充 `dist` 距离场 |
| `get_guidance_dir(cell)` | 返回该格指向出口的下一步方向（梯度下降） |
| `dist_at(cell)` | 查询某格到出口的步数，-1 不可达 |
| `pillar_cells` | 开阔区柱体格索引集合（渲染层套独立材质） |

---

### 3. 关卡构建器（levels/level_0.gd）

在 `_ready()` 中按顺序执行：

1. **创建材质** — `MaterialLib` 贴图优先（墙/地板/天花板/柱体四套 PBR 材质）+ 灯管面板（自发光）、出口传送门（绿色发光）
2. **配置氛围** — `Atmosphere.configure()` 开启体积雾；订阅 `settings_changed` 以便体积光/浮尘开关即时生效
3. **生成迷宫** — `MazeGenerator.generate(11)`
4. **构建地板和天花板** — 单个 CSGBox3D 覆盖全区域，use_collision=true
5. **构建墙壁（薄墙）** — 见下文「薄墙算法」，替代旧版逐格 4m 实心块
6. **布置灯光** — 贪心覆盖算法（见下文）；每盏顶灯 `light_volumetric_fog_energy=0.8`，在雾中形成光柱
7. **添加补光** — DirectionalLight3D 能量 0.18（体积雾能量 0，避免整体发灰），确保无纯黑区域
8. **定位玩家** — 近角落 FLOOR 格（记录 `spawn_cell`）
9. **放置出口** — `find_farthest_floor(spawn_cell)` 选距玩家**最短路最远**且可贴门的格（不再是固定远角落，出口真正被“藏”在迷宫深处）；传送门贴墙定向 + EXIT 标签 + Area3D；构建 BFS 距离场
10. **放置弱引导地标** — 沿出生点→出口最短路间隔放吸引性地标（见下文）
11. **浮尘粒子场** — `DustField` 跟随玩家，见下文「氛围：体积光与浮尘」
12. **环境嗡鸣** + 提示文字

**薄墙算法（`_build_thin_walls` / `_build_pillars`）：**

- 不再每格堆 4×4m 实心块，而是收集每个 WALL 格**面向 FLOOR 的边**
- 同一条网格线上连续的边**合并成整段隔墙**（CSGBox3D，厚 `WALL_THICK=0.28m`，高 3.2m），转角端头各外扩半厚闭合缝隙
- 墙身向墙侧内缩半厚，坐落格边界偏墙侧，不侵占走廊
- 开阔区柱体（`pillar_cells`）跳过薄墙，在格中心立 1.2m 居中方柱（混凝土材质），作空间地标

**弱引导地标（`_place_landmarks` + `landmark_breadcrumb.gd`）：**

不用箭头指路，而是沿通往出口的路（`_trace_path` 梯度追踪）在**关键决策点**放**与环境反差的小结构**，靠形态/颜色/微光把人自然地往前带：

**放置时机（对准「犹豫点」而非盲计时）：**
- 三岔/四岔**路口必放**（`_opening_count≥3`，人最容易迷路的地方），但相邻两次至少隔 3 格
- 直行段每 `GUIDE_STEP=7` 格兜底放一个

| 地标 | 形态 | 心理钩子 |
|------|------|----------|
| 黑碑 | 1.2m×2.1m 孤独黑色碑体，内嵌琥珀色发光接缝 | 「这里不该有这个东西」的好奇 |
| 门框 | 独立混凝土拱门，门楣一条暖光带 | 暗示「前方还有路」 |
| 信标 | 低矮黑杆顶一颗青绿应急灯球 | 黑暗里一盏不该亮着的灯 |

**弱化手段**（引导存在但不显眼）：路口才加密、直行大间隔（旧箭头每 4 格）、三种形态轮换避免规律感、每枚随机横向侧偏 0.2~0.8m 且偏离正路（像环境本来就有的物件）、点光能量仅 0.5/射程 3m（只照亮脚下，不照亮通路）、起点 2 格内与出口前一格不放（不抢传送门戏）。

**灯光布置算法：**

- 收集所有 FLOOR 格
- 从第一个未覆盖格开始，放置灯光
- 将射程内（有效半径 = 10m × 0.8 ÷ 4m = 2 格）的所有格标记为已覆盖
- 重复直到所有格被覆盖
- **保证零死角：每个可行走格都在至少一盏灯的照射范围内**

**灯光参数：**

| 参数 | 值 |
|------|-----|
| 射程 (omni_range) | 10m |
| 有效覆盖半径 | 8m（0.8 安全系数） |
| 衰减 | 1.5 |
| 阴影 | 启用 |
| 颜色 | 暖白 (1, 0.95, 0.8) |
| 能量 | 1.0 - 1.5（随机） |
| 闪烁概率 | 12% |
| 灯管面板 | 1.8×0.08×0.6m 自发光方块 |
| 体积雾能量 | 0.8（顶灯在雾中形成可见光柱） |

**闪烁灯行为（generation/flickering_light.gd）：**
- 等待 2-8 秒后触发
- 快闪 2-5 次（每次亮→灭 0.03-0.08s）
- 恢复正常亮度后重新等待 3-10 秒

---

### 4. 全局状态管理（autoload/game_state.gd）

自动加载为 `GameState`，管理跨场景的游戏状态。

**信号：**

| 信号 | 参数 | 说明 |
|------|------|------|
| `stamina_changed` | current, max_value | 体力变化 |
| `flashlight_changed` | is_on, battery | 手电筒状态变化 |
| `hint_changed` | text | 提示文字变化 |
| `settings_changed` | — | 灵敏度/FOV/体积光/浮尘/SSAO 变化，玩家与关卡实时订阅应用 |

**方法：**

| 方法 | 说明 |
|------|------|
| `reset()` | 重置所有状态（新游戏） |
| `set_stamina(v)` | 更新体力并广播 |
| `set_flashlight(on)` | 更新手电筒状态并广播 |
| `set_flashlight_battery(v)` | 更新电量并广播 |
| `show_hint(text)` | 显示提示文字 |

---

### 5. HUD 界面（ui/hud.tscn + hud.gd）

| 元素 | 类型 | 说明 |
|------|------|------|
| 十字准星 | ColorRect | 4×4px 白色半透明，屏幕居中 |
| 体力条 | ProgressBar | 200×12px，体力满时隐藏 |
| 手电筒标签 | Label | 显示开关状态和电量百分比 |
| 提示标签 | Label | 居中显示，4 秒后自动淡出 |

---

### 6. 暂停菜单（ui/pause_menu.tscn + pause_menu.gd）

- **Esc** 暂停游戏（`get_tree().paused = true`），显示菜单，释放鼠标
- **继续游戏** — 恢复游戏，重新捕获鼠标
- **设置** — 打开设置面板（遮罩下方再叠一层）
- **重新开始** — 重载当前关卡
- **返回主界面** — `change_scene_to_file("res://main/main_menu.tscn")`；main_menu 的「开始游戏」重载 main.tscn，main.gd `_ready` 调 `GameState.reset()`，体力/电量/关卡自动归零
- **退出游戏** — 关闭程序
- **Esc 分层**：设置面板打开时按 Esc 先关闭面板并保存，而不是跳过它直接恢复游戏
- `process_mode = PROCESS_MODE_ALWAYS`（暂停时仍可接收输入）
- CanvasLayer layer = 10（设置面板 layer = 11，始终在最上层）

---

### 7. 后室氛围（WorldEnvironment）

| 参数 | 值 |
|------|-----|
| 环境光颜色 | (0.2, 0.18, 0.12) 暗黄 |
| 环境光能量 | 0.4 |
| 雾效 | 启用，颜色 (0.1, 0.09, 0.06)，密度 0.02 |
| 色调映射 | Filmic |
| 辉光 | 启用，强度 0.3，泛光 0.1 |
| 亮度 | 0.9 |
| 对比度 | 1.1 |
| 饱和度 | 0.8 |
| 天空 | 暗色 ProceduralSky |
| 补光 | DirectionalLight3D (0.35, 0.32, 0.22) 能量 0.18 |

### 7b. 体积光 + 环境浮尘（氛围增强，含性能优化）

由 `generation/atmosphere.gd` 统一配置，`levels/level_0.gd` 与 `main/main_menu.gd` 共用。

**体积光（体积雾 Volumetric Fog，Forward+ 专属）：** 灯光穿过空气时形成可见光束，配合浮尘强化后室氛围。

| 参数 | 值 | 性能/画质考量 |
|------|-----|----------------|
| `volumetric_fog_density` | 0.02 | 极低密度：暗处几乎透明，雾只在灯周可见，不抬高黑位对比 |
| `volumetric_fog_length` | 40m（默认 64） | froxel 缓冲集中室内距离，等效提升单位精度 |
| `albedo` | (0.9, 0.85, 0.68) | 暖色散射匹配黄墙灯光 |
| `anisotropy` | 0.3 | 轻度前向散射 |
| `gi_inject` / `ambient_inject` | 0.0 | 室内无 VoxelGI/SDFGI，省两路采样 |
| `sky_affect` | 0.0 | 全封闭地图，跳过天空与雾混合 |
| 每盏顶灯 `light_volumetric_fog_energy` | 0.8 | 参与体积光；补光设 0 避免整体发灰 |
| 手电筒 `light_volumetric_fog_energy` | 1.5 | 开灯时光锥扫过雾与浮尘 |
| 项目设置 `volume_size` | 96 | froxel 横纵分辨率（默认 128→96 更省 GPU） |
| 项目设置 `volume_depth` | 64 | 深度切片（默认 128→64 更省） |

**环境浮尘（`generation/dust_field.gd`）：**
- 全场景**只有一个** `GPUParticles3D` 节点，发射盒 `local_coords=false` 留在世界空间、跟随玩家平移 → 开销与地图大小无关
- 700 粒（菜单 250），`preprocess=lifetime` 开场即铺满、无「粒子涌入」感
- 粒子为受光小面片（非自发光，alpha 0.22）→ 只在灯光附近显形，暗角自动隐形
- 湍流 + 微重力，模拟空气缓沉；`visibility_aabb` 让离屏时整体剔除
- 闪烁灯通过 `_apply_energy()` 同步熄灭光束与浮尘亮度，避免闪灭间隙光柱残留

**开关（均即时生效 + 持久化）：** 设置面板「体积光」「环境浮尘」两个 CheckBox → 改 `GameState` → `settings_changed.emit()` → 关卡/菜单重配 Environment 与粒子可见性。

### 7c. 抗锯齿 + SSAO（设置面板可调，实时生效）

**抗锯齿（11 挡下拉菜单）：** 全部是根视口（`get_tree().root`）运行时属性，`GameState.apply_anti_aliasing()` 按选项复位后重新叠加，切换即时生效无需重启：

| 索引 | 选项 | 实现（Viewport 属性） | 开销 |
|------|------|------------------------|------|
| 0 | 关闭 | 全部复位 | — |
| 1 | FXAA | `screen_space_aa=FXAA` | 极低 |
| 2 | SMAA 1x | `screen_space_aa=SMAA` | 低 |
| 3-5 | MSAA 2×/4×/8× | `msaa_3d=MSAA_2X/4X/8X` | 中→高 |
| 6 | TAA | `use_taa=true` | 中 |
| 7 | MSAA 4×+TAA | 叠加 | 中高 |
| 8 | FSR2（原生分辨率） | `scaling_3d_mode=FSR2, scale=1.0` | 高 |
| 9-10 | SSAA 2.25×/4× | 双线性 `scaling_3d_scale=1.5/2.0` | 极高 |

默认 MSAA 4×（索引 4）。注意：TAA/FSR2 对粒子/自发光可能有拖影伪像（引擎已知限制），恐怖静态场景建议 MSAA/SMAA。

**SSAO 环境光遮蔽：** `Atmosphere._configure_ssao()` 随 `configure()` 每帧重配应用；墙脚/柱基/地标背后接触阴影，空间层次感明显提升。三档（低/中/高）映射 `ssao_radius/intensity/power/detail`（半径 0.7/1.0/1.5），`ssao_light_affect=0.15` 保留灯下细节；关闭时「质量」下拉置灰。SSAO 仅 Forward+ 支持。

---

## 场景层级

```
Main (main.tscn)
├── Level0 (level_0.tscn)
│   ├── WorldEnvironment
│   ├── Floor (CSGBox3D, 动态生成)
│   ├── Ceiling (CSGBox3D, 动态生成)
│   ├── Walls (Node3D, 动态生成)
│   │   ├── [合并后的整段薄墙 CSGBox3D × N]
│   │   └── [开阔区柱体 CSGBox3D × M]
│   ├── Lights (Node3D, 动态生成)
│   │   └── [OmniLight3D + 自发光面板 CSGBox3D]
│   ├── AmbientFill (DirectionalLight3D)
│   ├── Landmarks (Node3D, 动态生成)
│   │   └── [黑碑/门框/信标地标，沿最短路间隔侧偏放置]
│   ├── DustField (Node3D→GPUParticles3D, 动态生成)
│   │   └── [跟随玩家的环境浮尘粒子场]
│   └── ExitDoor (Area3D, 动态生成, 贴墙定向)
│       ├── CollisionShape3D
│       ├── Portal (CSGBox3D, 绿色发光)
│       └── Label3D ("EXIT")
├── Player (player.tscn)
│   ├── CollisionShape3D (CapsuleShape3D)
│   ├── Camera3D
│   │   └── Flashlight (SpotLight3D, 体积雾能量 1.5)
│   └── FootstepAudio (AudioStreamPlayer3D, 预留)
├── HUD (hud.tscn)
│   ├── Crosshair (ColorRect)
│   └── MarginContainer
│       └── VBoxContainer
│           ├── StaminaBar (ProgressBar)
│           ├── BatteryLabel (Label)
│           └── HintLabel (Label)
└── PauseMenu (pause_menu.tscn)
    ├── Background (ColorRect, 半透明黑)
    └── CenterContainer
        └── VBoxContainer
            ├── TitleLabel ("PAUSED")
            ├── ResumeButton ("继续游戏")
            ├── SettingsButton ("设置")
            ├── RestartButton ("重新开始")
            ├── MainMenuButton ("返回主界面")
            └── QuitButton ("退出游戏")
```

---

## 输入映射（project.godot）

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
| interact | E | 69 |
| pause | Esc | 4194305 |

---

## 运行方式

1. 打开 `C:\Users\Lenovo\Documents\godothub\engine\4.7.2-stable\godot.exe`
2. 导入项目 `D:\杂类\后室-godot4.7.2\project.godot`
3. 按 **F5** 运行

**命令行运行：**
```
C:\Users\Lenovo\Documents\godothub\engine\4.7.2-stable\godot.exe --path "D:\杂类\后室-godot4.7.2"
```

**Headless 验证：**
```
godot.exe --headless --path . --quit-after 3 res://main/main.tscn
```

---

## 开发路线图

### Phase 1：原型验证 ✅ 已完成
- [x] 项目搭建，Godot 4.7.2 配置
- [x] 第一人称玩家控制（移动/冲刺/蹲伏/头部晃动）
- [x] 程序化迷宫生成（递归回溯 + 环路 + 开阔区域）
- [x] 灯光覆盖系统（保证无死角 + 闪烁灯 + 自发光面板）
- [x] 手电筒系统（电量消耗 / 开关 / 聚光灯）
- [x] 体力系统（冲刺消耗 / 自动恢复）
- [x] HUD 界面（准星/体力条/电量/提示文字）
- [x] 暂停菜单（继续/重开/退出）
- [x] 后室氛围（雾效/暗角/低饱和度/黄色调）
- [x] 出口传送门（Area3D 检测 + 绿色发光 + EXIT 标签）
- [x] 场景切换（到达出口后重载关卡）
- [x] 开始菜单 + 设置菜单
- [x] 跳跃系统（短滞空 + 空中禁摇头）
- [x] ambientCG 真实贴图材质库（程序化回退）
- [x] 薄墙重建 + 布局强化（大房间/死端编织/地标柱）
- [x] 地面弱指引箭头（BFS 最短路 + 呼吸发光）
- [x] 箭头改为吸引性地标面包屑（黑碑/门框/信标）+ 出口按最短路距离选最远 + 迷宫复杂度提升（MAZE_SIZE 11/假分支/更多环路房间）
- [x] 复杂度回调（假分支≤6 条等）+ 路口地标加密，缓解「找不到路」；抗锯齿 11 挡下拉 + SSAO 开关/三档（均实时生效）
- [x] 设置界面修复（Esc 分层 / FOV 实时生效 / 即时保存）
- [x] 体积光（体积雾）+ 环境浮尘粒子场（跟随玩家、性能优化、设置可开关）

### Phase 2：核心玩法 ⬜ 未开始
- [ ] 实体 AI（至少 1 种：巡逻型 / 追猎型）
- [ ] NavigationServer3D 导航网格
- [ ] 物品拾取（电池、补给）
- [ ] 脚步音效 + 环境音（嗡鸣、灯管电流声）
- [ ] VHS 后处理 Shader（扫描线 / 噪点 / 色差）
- [ ] 多关卡支持（Level 1 仓库、Level 2 通道）
- [ ] 死亡 / 重生系统

### Phase 3：内容与打磨 ⬜ 未开始
- [ ] 3-5 个不同风格的 Level
- [ ] 3 种以上实体
- [ ] 完整音频体系
- [ ] 主菜单 + 设置界面
- [ ] 难度分级
- [ ] 存档系统
- [ ] 成就系统

### Phase 4：扩展 ⬜ 未开始
- [ ] 联机合作（ENet / Steam）
- [ ] 更多 Level 和实体
- [ ] Steam 页面上架

---

### 8. 材质库（generation/material_lib.gd）

**优先加载 ambientCG CC0 真实贴图**（`assets/textures/`，Color + NormalGL + Roughness 1K-JPG 三件套），**缺失时自动回退** `FastNoiseLite` + `NoiseTexture2D` 程序化纹理。

| 材质 | 贴图目录 | albedo 色调叠加 | 每米平铺 | 用途 |
|------|----------|------------------|----------|------|
| 墙壁 | Plaster001 | (0.86, 0.79, 0.52) 泛黄 | 0.5 | 后室经典黄墙 |
| 地板 | Carpet001 | (0.60, 0.53, 0.36) 暗棕 | 0.55 | 潮湿黄棕地毯 |
| 天花板 | Fabric001 | (0.80, 0.77, 0.62) 米白 | 0.4 | 吊顶织物感面板 |
| 柱体 | Concrete030 | (0.62, 0.60, 0.55) 冷灰 | 0.45 | 开阔区地标柱 |

- 全部启用 `uv1_world_triplanar` 世界三向投影，CSGBox3D 无需手动调 UV
- Roughness 贴图走 R 通道；程序化回退纹理 `seamless = true`
- 贴图来源: https://ambientcg.com (CC0)

---

### 9. 程序化音效（generation/sound_generator.gd）

使用 `AudioStreamWAV` + 数学波形在运行时生成音频数据（16-bit PCM, 44100Hz, 单声道）。

| 音效 | 时长 | 波形组成 | 播放方式 |
|------|------|----------|----------|
| 脚步声 | 0.08s | 60Hz 正弦 × 0.55 + 白噪 × 0.12，指数衰减包络 | AudioStreamPlayer3D，音调随机 ±15% |
| 环境嗡鸣 | 1.0s 循环 | 100Hz × 0.08 + 200Hz × 0.04 + 300Hz × 0.02 + 微噪 | AudioStreamPlayer，LOOP_FORWARD，-15dB |
| 手电筒点击 | 0.02s | 白噪 × 0.3，三次方衰减 | AudioStreamPlayer，-10dB |

**脚步触发逻辑：**
- `head_bob_time` 每增加 0.5（半周期）触发一次
- 仅在 `is_on_floor()` 且 `velocity.length() > 1.0` 时触发
- 每次播放随机 pitch_scale (0.85-1.15) 模拟自然步态变化


### 10. 开始菜单（main/main_menu.tscn）

背景为程序化构建的 Level 0 走廊（4x3x14m），墙面/地面/天花板使用与关卡相同的 `MaterialLib` 真实贴图材质，含日光灯 + 闪烁灯 + 环境嗡鸣。相机轻微呼吸晃动。UI 包含标题和三个按钮（开始游戏/设置/退出游戏）。

### 11. 设置菜单（ui/settings_menu.tscn）

| 设置项 | 控件 | 范围 | 默认值 | 生效方式 |
|--------|------|------|--------|----------|
| 鼠标灵敏度 | HSlider | 0.0005-0.005 | 0.002 | 实时（settings_changed） |
| 视野 | HSlider | 60-100 | 75 | 实时（settings_changed） |
| 主音量 | HSlider | 0-100% | 80% | 实时 + 即时保存 |
| 全屏 | CheckBox | 开/关 | 关 | 实时 + 即时保存 |
| 体积光 | CheckBox | 开/关 | 开 | 实时（重配 Environment）+ 保存 |
| 环境浮尘 | CheckBox | 开/关 | 开 | 实时（切粒子可见性）+ 保存 |
| 抗锯齿 | OptionButton | 11 挡（关/FXAA/SMAA/MSAA×3/TAA/MSAA+TAA/FSR2/SSAA×2） | MSAA 4× | 实时（切根视口）+ 保存 |
| 环境光遮蔽 | CheckBox | 开/关 | 开 | 实时（重配 Environment）+ 保存 |
| SSAO 质量 | OptionButton | 低/中/高 | 中 | 实时；SSAO 关时置灰 |

灵敏度/FOV 改动经 `GameState.settings_changed` 广播，玩家相机即时应用；关闭面板时统一保存到 `user://settings.cfg`（`GameState.load_settings()` 启动时恢复）。从开始菜单和暂停菜单均可打开。

---

## 已知限制

- VHS 后处理 Shader 未添加
- 实体 AI 未实现
- 交互系统（E 键）已定义输入但无功能
- 迷宫每次运行随机生成（无法固定 seed 进行调试复现）
- CSGBox3D 用于所有几何体，大型关卡可能需要优化为 MeshInstance3D + StaticBody3D






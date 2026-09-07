# Backrooms Prototype

> 基于「后室」(Backrooms) 世界观的第一人称恐怖探索游戏原型
> **Godot 4.7.2 | Forward+ 渲染器**

玩家被随机切入 Level 0 —— 那片没完没了的黄色迷宫房间。想要逃出去，就得在昏暗潮湿的无限回廊里，靠手电筒那点微弱光芒，集齐 **3 瓶杏仁水**，找到藏在迷宫深处的绿色 **EXIT** 出口。逃出一层，还有四层。

`Level 0 黄色迷宫 → Level 1 无尽仓库 → Level 2 管道之梦 → Poolrooms 泳室 → Level ! 红色狂奔`

---

## 特性

- 🌀 **程序化迷宫生成**：递归回溯 + 环路 + 房间 + 死端编织 + BFS 距离场，五种生成器各管一关（房间簇 / 仓库网格 / 管道迷宫 / 泳室大厅群 / 红色直道）
- 🕯️ **零死角灯光覆盖**：贪心算法保证每个可行走格都有光照，配闪烁日光灯、红手轮阀喷蒸汽、暗红应急灯
- 💡 **手电筒系统**：F 键开关，消耗电量；**电池**散落在地图上，碰到即自动充能（+35%）
- 🥤 **收集系统**：**杏仁水**靠近按 E 拾取，每关 3 瓶，集齐出口才放行；右侧任务面板实时显示进度，集齐变绿打 ✓
- 🏃 **真实感玩家控制**：冲刺消耗体力（力竭机制防无限冲刺）、蹲伏、跳跃、头部晃动、脚步声
- 🌫️ **后室氛围**：体积雾（体积光）、跟随玩家的浮尘粒子场、SSAO、抗锯齿 11 挡实时切换
- 🗺️ **弱引导地标**：黑碑 / 门框 / 信标八大形态（贴墙 / 落地多状态），沿最短路在关键路口放置，「吸引」而非「指路」
- 🏃♂️ **Level ! 追逐氛围**：没有实体、没有 AI——身后的灯一盏盏熄灭，低吼渐强，屏幕红脉冲越跳越快，黑暗追着你跑
- 🧟 **完善 UI**：HUD（任务面板 / 拾取提示 / 红脉冲暗角）、暂停菜单、关卡选择（自选起点 / 继续 / 重开）、设置面板实时生效
- 📦 **程序化音效**：脚步 / 环境嗡鸣 / 手电点击 / 蒸汽嘶嘶 / 滴水 / 追逐低吼，全部运行时生成，零音频资源
- 🎬 **场景切换遮罩**：程序化生成卡顿帧被全屏「正在进入下一层…」遮罩盖住，无缝丝滑

---

## 操作方式

| 动作 | 按键 |
|------|------|
| 移动 | W / A / S / D |
| 冲刺 | Shift |
| 蹲伏 | Ctrl |
| 跳跃 | Space |
| 手电筒 | F |
| 拾取杏仁水 | E（靠近 2.6m 出现提示） |
| 暂停 | Esc |

> 彩蛋：主菜单输入科乐美秘技「上上下下左右左右 BABA」解锁连跳。

---

## 运行方式

1. 使用 **Godot 4.7.2**（或兼容 4.7 的版本）导入项目根目录 `project.godot`
2. 打开 `res://main/main_menu.tscn`（主场景）
3. 按 **F5** 运行

命令行方式：

```bash
godot --path . --quit-after 3 res://main/main.tscn
```

Headless 验证（六场景扫描）：

```bash
godot --headless --path . --quit-after 90 res://main/main.tscn
godot --headless --path . --quit-after 90 res://levels/level_2.tscn
```

---

## 项目结构

```
res://
├── project.godot              # 项目配置（输入映射、自动加载、渲染器）
├── autoload/
│   ├── game_state.gd          # 全局状态（关卡进度/体力/手电/杏仁水/设置信号）
│   └── loader.gd              # 场景切换加载遮罩
├── generation/
│   ├── maze_generator.gd      # 迷宫生成算法（回溯+环路+房间+距离场）
│   ├── material_lib.gd        # 材质库（真实贴图优先，程序化回退，五关套装）
│   ├── landmark_breadcrumb.gd # 弱引导地标（8 形态贴墙/落地）
│   ├── pickup_item.gd         # 拾取物（杏仁水 E 拾取 / 电池自动拾取）
│   ├── atmosphere.gd          # 体积雾 / SSAO 统一配置
│   ├── dust_field.gd          # 跟随玩家的 GPU 浮尘粒子场
│   ├── flickering_light.gd    # 闪烁日光灯
│   └── sound_generator.gd     # 程序化音效生成器
├── levels/
│   ├── level_base.gd          # 关卡基类（装配流水线 + 可覆盖钩子）
│   ├── level_0.gd / .tscn     # Level 0 黄色迷宫
│   ├── level_1.gd / .tscn     # Level 1 无尽仓库
│   ├── level_2.gd / .tscn     # Level 2 管道之梦
│   ├── level_poolrooms.gd/.tscn # Poolrooms 泳室
│   ├── level_run.gd / .tscn   # Level ! 红色狂奔
│   ├── level0_generator.gd    # L0 房间簇生成器
│   ├── poolrooms_generator.gd # 泳室大厅群生成器
│   └── warehouse_generator.gd # L1 仓库网格生成器
├── main/
│   ├── main.tscn / main.gd    # 游戏主场景（按 current_level 装配关卡）
│   ├── main_menu.tscn / .gd   # 开始菜单（含科乐美秘技彩蛋）
│   └── level_select.tscn/.gd  # 关卡选择界面
├── player/
│   ├── player.tscn            # 玩家场景
│   └── player.gd              # 第一人称控制器
├── ui/
│   ├── hud.tscn / hud.gd      # HUD（任务面板/拾取提示/红脉冲暗角）
│   ├── pause_menu.tscn        # 暂停菜单
│   └── settings_menu.tscn/gd  # 设置面板
├── docs/                      # 各关卡独立设计文档
│   ├── level0_design.md / level1_design.md / level2_design.md
│   ├── level_poolrooms_design.md / level_run_design.md
└── assets/textures/           # ambientCG CC0 真实贴图
```

---

## 开发路线图

- **Phase 1·原型验证** ✅ 已完成：玩家控制 / 迷宫生成 / 灯光系统 / 手电筒 / 体力 / HUD / 暂停 / 后室氛围 / 材质库 / 体积光与浮尘
- **Phase 2·核心玩法** 🔶 大部分完成：五关线性推进 / 关卡基类钩子 / 杏仁水收集 + 电池 / 关卡选择 / Level ! 追逐氛围 / 程序化环境音
  - ⬜ 待办：实体 AI、Navigation 导航网格、VHS 后处理、死亡 / 重生系统
- **Phase 3·内容打磨** ⬜：3 种以上实体、完整音频体系、难度分级 / 成就
- **Phase 4·扩展** ⬜：联机合作、Steam 发行

> 详细设计文档见 [DESIGN.md](DESIGN.md)

---

## 素材致谢

- 贴图来自 [ambientCG](https://ambientcg.com)，遵循 CC0 协议
- 项目使用性能优化后的体积雾 / 浮尘方案，支持动态开关（详见 `DESIGN.md`）

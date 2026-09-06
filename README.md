# Backrooms Prototype

> 基于「后室」(Backrooms) 世界观的第一人称恐怖探索游戏原型
> **Godot 4.7.2 | Forward+ 渲染器**

玩家被随机切入 Level 0 —— 那片没完没了的黄色迷宫房间。想要逃出去，就得在昏暗潮湿的无限回廊里，靠手电筒那点微弱光芒，找到藏在迷宫深处的绿色 **EXIT** 出口。

---

## 特性

- 🌀 **程序化迷宫生成**：递归回溯 + 随机环路 + 矩形房间 + 死端编织 + 假分支 + BFS 距离场（23×23 格 / 92×92 米）
- 🕯️ **零死角灯光覆盖**：贪心算法保证每个可行走格都有光照，配 12% 概率的闪烁日光灯
- 💡 **手电筒系统**：F 键开关，消耗电量，光锥扫过体积雾与浮尘
- 🏃 **真实感玩家控制**：冲刺消耗体力（力竭机制防无限冲刺）、蹲伏、跳跃、头部晃动、脚步声
- 🌫️ **后室氛围**：体积雾（体积光）、环境浮尘粒子场、闪烁灯管、环境嗡鸣
- 🗺️ **弱引导地标**：黑碑 / 门框 / 信标三大形态，沿最短路在关键路口放置，「吸引」而非「指路」
- 🧟 **完善 UI**：HUD、暂停菜单、开始菜单、设置面板（灵敏度 / FOV / 全屏 / 抗锯齿 / SSAO 等实时生效）
- 📦 **程序化音效**：脚步 / 环境嗡鸣 / 手电筒点击，全部运行时生成，零音频资源

---

## 操作方式

| 动作 | 按键 |
|------|------|
| 移动 | W / A / S / D |
| 冲刺 | Shift |
| 蹲伏 | Ctrl |
| 跳跃 | Space |
| 手电筒 | F |
| 交互 | E（预留） |
| 暂停 | Esc |

---

## 运行方式

1. 使用 **Godot 4.7.2**（或兼容 4.7 的版本）导入项目根目录 `project.godot`
2. 打开 `res://main/main_menu.tscn`（主场景）
3. 按 **F5** 运行

命令行方式：

```bash
godot --path . --quit-after 3 res://main/main.tscn
```

Headless 验证：

```bash
godot --headless --path . --quit-after 3 res://main/main.tscn
```

---

## 项目结构

```
res://
├── project.godot              # 项目配置（输入映射、自动加载、渲染器）
├── autoload/
│   └── game_state.gd          # 全局状态管理（体力/手电/提示/设置信号）
├── generation/
│   ├── maze_generator.gd      # 迷宫生成算法
│   ├── material_lib.gd        # 材质库（真实贴图优先，程序化回退）
│   ├── landmark_breadcrumb.gd # 弱引导地标
│   ├── atmosphere.gd          # 体积雾 / SSAO 统一配置
│   ├── dust_field.gd          # 跟随玩家的 GPU 浮尘粒子场
│   ├── flickering_light.gd    # 闪烁日光灯
│   └── sound_generator.gd     # 程序化音效生成器
├── levels/
│   ├── level_0.tscn           # Level 0 场景
│   └── level_0.gd             # 程序化关卡构建器
├── main/
│   ├── main.tscn / main.gd    # 游戏主场景
│   └── main_menu.tscn/gd      # 开始菜单
├── player/
│   ├── player.tscn            # 玩家场景
│   └── player.gd              # 第一人称控制器
├── ui/
│   ├── hud.tscn / hud.gd             # HUD
│   ├── pause_menu.tscn               # 暂停菜单
│   └── settings_menu.tscn/gd         # 设置面板
└── assets/textures/           # ambientCG CC0 真实贴图
```

---

## 开发路线图

- **Phase 1·原型验证** ✅ 已完成：玩家控制 / 迷宫生成 / 灯光系统 / 手电筒 / 体力 / HUD / 暂停 / 后室氛围 / 出口传送门 / 开始+设置菜单 / 材质库 / 体积光与浮尘
- **Phase 2·核心玩法** ⬜：实体 AI、Navigation 导航网格、物品拾取、脚步与音效完善、VHS 后处理
- **Phase 3·内容打磨** ⬜：多 Level、多实体、完整音频、难度 / 存档 / 成就
- **Phase 4·扩展** ⬜：联机合作、Steam 发行

> 详细设计文档见 [DESIGN.md](DESIGN.md)

---

## 素材致谢

- 贴图来自 [ambientCG](https://ambientcg.com)，遵循 CC0 协议
- 项目使用性能优化后的体积雾 / 浮尘方案，支持动态开关（详见 `DESIGN.md`）
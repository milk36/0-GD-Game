# llmdoc 索引

项目：demo-game（Godot 4.7.2，游戏大厅 + 小游戏合集）

| 文档 | 说明 |
| --- | --- |
| [ui-main-menu.html](ui-main-menu.html) | 游戏大厅主菜单 UI：场景结构、脚本、主题说明 |
| [tetris-design.html](tetris-design.html) | 赛博朋克俄罗斯方块：游戏设计规划（视觉规范/规则/技术方案/里程碑） |
| [tetris-game.html](tetris-game.html) | 赛博朋克俄罗斯方块：实现说明（文件结构/场景树/踩坑记录/验证结果） |
| [tetris-items-design.html](tetris-items-design.html) | 俄罗斯方块增量需求：风/雨/雷电道具系统 + 消除粒子特效（含设计决策与验收标准） |
| [voxel-eagle-design.html](voxel-eagle-design.html) | 方块雄鹰：Sky Force 类体素弹幕射击设计规划（玩法/体素视觉/技术方案/里程碑与 M0-M3.14 实施记录；**当前进度：全部交付**——3 关选关/奖牌解锁/悬停救援/Boss/机库/存档/BGM+音效/金属红涂装/地貌差异/高度分层，玩家机+Boss+E1~E10 敌机均为 MagicaVoxel .vox 资产（E1~E6 由 gen_units.py 生成，E7~E10 由 AI 体素管线 spec 产出，game.gd 内敌机字符画已清零），美术已全面转 MagicaVoxel 工作流；另产出海盗关卡地图切片 gen_pirate.py（4 张独立 .vox，待确认后接入）；遗留：难度分级、海盗关卡整合） |
| [tools-vox.html](tools-vox.html) | 体素工具链 tools/vox：MagicaVoxel ↔ Godot 工作流（文件清单/标准流程/核心约定/单位与海盗资产表/voxlib API/**声明式 spec 管线 voxspec+gen_spec**/验证流程/踩坑速查；细节以 tools/vox/README.md 为准） |
| [ai-voxel-pipeline.html](ai-voxel-pipeline.html) | AI 驱动体素资产：方案评估与推荐架构（AI 介入四层级 L0~L3 对比/为何必须用编译器约束/声明式 spec 草案与 op 集合/编译器校验项/现有基建盘点/阶段 0~3 落地路径/风险边界/§9 评审修订/§10 实施记录；**当前状态：阶段 0~2 已投产**——voxspec.py 编译器（solid/paint 分离、box/symbox/oct/ring/profile/dots/paint 七 op、对称/连通/量级/朝向校验、verify 零回归与漂移检测）+ gen_spec.py 一条命令（assembly 合成预览）+ specs/PROMPT.md 提示词模板；spec 管线已产出并接入 E7 武装直升机（双 part）与首批批量 E8 飞翼轰炸机 / E9 双体炮艇 / E10 浮空盾堡（ring op 首投产），三关波次已编排，_check_enemies 覆盖 E1~E10；另有单位审查场景 scenes/unit_review.tscn（快捷键 1=正交 34 游戏机位认物 / 2 等距 / 3 特写）；既有资产真源仍为 gen_units.py） |
| [voxel-to-tile.html](voxel-to-tile.html) | 体素改瓦片：方案评估与建议（「瓦片」四种含义适配度/为何不退 2D TileMapLayer/三层架构·瓦片本体+排布层+渲染层/滚动走廊行式瓦片/必须先定死的三个数·边长·锚点·北向/渲染层选型 GridMap·MultiMesh·合并 mesh/性能账约 87→15~25 次绘制/与 spec 管线的复用边界·共用 op 实现另立 terrain schema/阶段 1~4 落地路径·定规格→海面→pirate 试点→现有地貌/风险边界/待定决策清单；**当前状态：落地设计已由 tile-eagle-design.html 承接**） |
| [tile-eagle-design.html](tile-eagle-design.html) | **瓦片雄鹰**：瓦片表现形式对照重制版设计方案（范围界定·瓦片只落地貌/单位保持 .vox 及分歧声明/继承三规格·16 体素=4.8·底面中心锚点·北向四向 rot/三层架构·行式瓦片走廊·场景树/M0 首批 8 瓦片集与产线约束·边缘无缝/排布层·段落+图章+种子复现/渲染层 MultiMesh 分组·绘制账 87→11~14/调试键沿用 F1F2F5/复用边界·跨目录 preload 单一真源/里程碑 M0~M3·M0 五条验收含对照截图/**对评估文档三处调整**·MultiMesh 替 GridMap·程序化先行·16 体素瓦片替代 pirate 大块试点/风险与待确认·单位瓦片化分歧置顶/**当前状态：M0 已交付**（瓦片走廊可飞行·12 瓦片集含 2×2 超级瓦岛·三机位验收图与并排对照图·60FPS/150 实例·9 条踩坑与调参入口见 §13；M1 为下一交付物）） |
| [tile-3d-vs-2d-demo.html](tile-3d-vs-2d-demo.html) | 配套演示（可交互）：**瓦片+3D vs 纯2D 瓦片**效果对比。两侧跑同一份瓦片布局与同一套颜色，3D 侧按游戏真实相机（正交 34 / (0,30,12) / 方向光 (-52°,-28°)）做软件投影与逐面着色（顶面 1.000 / +Z 0.798 / -X 0.588 / +X 0.350 死黑面，与 asset_review.gd 记录一致），2D 侧为同视野纯俯视平铺。可切 68°/90° 机位、地形高度 ×1/×1.8、重摇布局、暂停滚动；读数含瓦片数与绘制四边形数（195 瓦片 → 3D 约 274~316 面 / 2D 195 面） |

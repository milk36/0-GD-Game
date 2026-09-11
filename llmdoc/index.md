# llmdoc 索引

项目：demo-game（Godot 4.7.2，游戏大厅 + 小游戏合集）

| 文档 | 说明 |
| --- | --- |
| [ui-main-menu.html](ui-main-menu.html) | 游戏大厅主菜单 UI：场景结构、脚本、主题说明 |
| [tetris-design.html](tetris-design.html) | 赛博朋克俄罗斯方块：游戏设计规划（视觉规范/规则/技术方案/里程碑） |
| [tetris-game.html](tetris-game.html) | 赛博朋克俄罗斯方块：实现说明（文件结构/场景树/踩坑记录/验证结果） |
| [tetris-items-design.html](tetris-items-design.html) | 俄罗斯方块增量需求：风/雨/雷电道具系统 + 消除粒子特效（含设计决策与验收标准） |
| [voxel-eagle-design.html](voxel-eagle-design.html) | 方块雄鹰：Sky Force 类体素弹幕射击设计规划（玩法/体素视觉/技术方案/里程碑与 M0-M3.14 实施记录；**当前进度：全部交付**——3 关选关/奖牌解锁/悬停救援/Boss/机库/存档/BGM+音效/金属红涂装/地貌差异/高度分层，玩家机+Boss+E1~E6 敌机均已迁移 MagicaVoxel .vox 资产管线（gen_units.py 生成，game.gd 内敌机字符画已清零），美术已全面转 MagicaVoxel 工作流；另产出海盗关卡地图切片 gen_pirate.py（4 张独立 .vox，待确认后接入）；遗留：难度分级、海盗关卡整合） |
| [tools-vox.html](tools-vox.html) | 体素工具链 tools/vox：MagicaVoxel ↔ Godot 工作流（文件清单/标准流程/核心约定/单位与海盗资产表/voxlib API/**声明式 spec 管线 voxspec+gen_spec**/验证流程/踩坑速查；细节以 tools/vox/README.md 为准） |
| [ai-voxel-pipeline.html](ai-voxel-pipeline.html) | AI 驱动体素资产：方案评估与推荐架构（AI 介入四层级 L0~L3 对比/为何必须用编译器约束/声明式 spec 草案与 op 集合/编译器校验项/现有基建盘点/阶段 0~3 落地路径/风险边界/§9 评审修订/§10 实施记录；**当前状态：阶段 0~2 冒烟通过**——voxspec.py 编译器（solid/paint 分离、oct/profile/dots/paint op、对称/连通/量级/朝向校验、verify 零回归与漂移检测）+ gen_spec.py 一条命令（assembly 合成预览）+ specs/{e1,e4,player} 三级零回归样本（逐体素一致全过）+ specs/PROMPT.md 提示词模板；E7 武装直升机（双 part：机身+旋翼层）已按模板端到端产出并落盘（初筛 2 轮通过，未接入 game.gd）；既有资产真源仍为 gen_units.py；批量生产按"≥10 个新单位"触发） |

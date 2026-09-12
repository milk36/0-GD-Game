# 体素工具链（MagicaVoxel ↔ Godot）

用代码直接生成 / 修改 MagicaVoxel `.vox` 场景，并把它接进「方块雄鹰」。
**MagicaVoxel 本身只当查看器和手工微调工具**——它没有 CLI、没有脚本 API、不能 headless 导出，
所以所有自动化都走「直接读写 .vox 文件」这条路（格式是 ephtracy 公开的 RIFF）。

---

## 1. 文件清单

| 文件 | 作用 |
| `E12.vox` / `E12R.vox` | 13×25×8 / 15×17×1 | 3.9×7.5×2.4 | 重型武装直升机：串列座舱 + 短翼挂巢 + 五叶主旋翼，机头朝 **+Y**（瓦片雄鹰接入，beh=gunship：机枪压制 + 追踪导弹） |
|---|---|
| `tools/vox/voxlib.py` | 核心库：.vox 读 / 写 / 等距预览渲染（纯标准库，零依赖） |
| `tools/vox/gen_scene.py` | 示例生成器：程序化小岛（地形+海洋+树+小屋） |
| `tools/vox/gen_units.py` | 单位生成器：玩家机 / Boss / **E1~E6 敌机** → `assets/vox/units/*.vox` |
| `tools/vox/gen_pirate.py` | 海盗关卡地图切片生成器：海面瓦片 / 海盗岛 / 要塞 / 帆船 → `assets/vox/pirate/*.vox` |
| `tools/vox/voxspec.py` | 声明式 spec 编译器（AI 体素管线 L2）：spec JSON → 展开校验 → .vox；`verify` 子命令兼作零回归闸门 / 漂移检测 |
| `tools/vox/gen_spec.py` | 一条命令出图：spec → 编译+审计+预览（默认 dry，`--write` 才落盘） |
| `tools/vox/specs/*.json` | 单位 spec（E1/E4/player 为零回归验证样本，与 gen_units 等价） |
| `tools/vox/_smoke.gd` | 冒烟测试：headless 跑真实场景，检查体素岛是否挂载成功 |
| `tools/vox/_check_enemies.gd` | 敌机回归：headless 生成 E1~E5 + 跑更新循环，检查 .vox 加载与炮头 look_at |
| `tools/vox/asset_audit.gd` | 量化审计：绕序/法线硬边/光照溢出（headless 可跑，输出表格） |
| `tools/vox/asset_review.gd` | 视觉验收：把每个资产离屏渲染成 PNG（需要 GPU，会短暂开窗） |
| `tools/vox/ingame_view.gd` | 按游戏真实相机参数渲染：核对实际观感、物体比例、认物 |
| `tools/vox/scene_shot.gd` | 把任意场景按 1280×720 离屏拍成 PNG（改 `SCENE` 即可换场景） |
| `scripts/voxel_eagle/survivor_unit.gd` | 幸存者单位唯一构建入口（网格/双臂/叹号/姿态/营救参数/绳索位姿），游戏与测试场景共用 |
| `scripts/voxel_eagle/rescue_ring.gd` | 机上营救进度计时圈（屏幕对齐的 ImmediateMesh 圆环，半径=触发距离） |
| `scripts/voxel_eagle/survivor_test.gd` + `scenes/survivor_test.tscn` | 幸存者外观测试场景（开局 10 个，可切换机位/缩放/阴影） |
| `tools/vox/pngsheet.py` | 把多张 PNG 拼成接触表（纯标准库 PNG 解码，替代 PIL） |
| `tools/tile_eagle/shot.gd` | 瓦片雄鹰出图验收：三机位 + 关云 + 关阴影 + 关水波 + 要塞段 + 战斗图 + 精英取景 + 方舟 + **救援两连拍**（待救 / 起吊中），用 `debug_seek` 固定构图（同种子逐像素可复现） |
| `tools/tile_eagle/_mesh_probe.gd` | 瓦片回归探针（headless）：AABB / off / 三角面数 / 贴瓦边的竖直面顶点数 / 水面层顶面世界高度 |
| `tools/tile_eagle/_play_smoke.gd` | M1/M2 玩法冒烟（headless）：固定步长跑满波次表（240s，含精英段），查敌机生成 / 分层落位 / 落岛高度 / 弹幕峰值 / 击杀 / 死亡重开 / **精摆段与种子逐位无关** |
| `tools/tile_eagle/_probe_wave.gd` | 水面 shader 诊断（headless 出图）：把浪光 sheen 放大 5.3 倍，肉眼判据「亮度栅格是否跨瓦连续」——若相位锚在局部坐标会按瓦格重置、露出 100px 见方的错位格 |
| `tools/vox/terraintile.py` | 地形/结构瓦 spec 编译器（M2）：复用 voxspec 的 op 展开，另立地形 schema；`build specs/terrain` 一条命令批量产出 |
| `tools/vox/gen_pirate_tiles.py` | 外来 64×64 资产 → 4×4 超级瓦的接入管线（M2）：平移对齐 / 补水面板 / 整体抬 1 体素，附兼容性报告 |
| `scenes/unit_review.tscn` + `scripts/voxel_eagle/unit_review.gd` | 单位审查场景：全单位 4×3 阵列，快捷键切机位（1=正交 34 游戏机位认物 / 2 等距 / 3 特写） |
| `scripts/voxel_eagle/vox_reader.gd` | GDScript 运行时 .vox 解析器 → ArrayMesh |
| `assets/vox/island_scene.vox` | 产物：小岛场景（48×49×21，19295 体素，11 色；v2 起无水体，贴地生长） |
| `assets/vox/island_scene_preview.png` | 产物：等距预览图（自检用，不参与游戏） |

运行 Python 用任意 3.8+ 均可（无第三方依赖）：

```bash
PY="C:/Users/milk_36/.workbuddy/binaries/python/versions/3.13.12/python.exe"
```

---

## 2. 标准工作流

```
① 改 gen_scene.py（或写新脚本）→ 生成 .vox
② python gen_scene.py                       # 同时输出预览 PNG
③ 看预览图确认 → 双击 .vox 用 MagicaVoxel 打开精修 → 保存
④ 切回 Godot 编辑器窗口等 1~2 秒（自动重导入生成 .mesh）
⑤ 运行游戏，体素岛已在场景里
```

`.vox` 必须落在 `assets/vox/`（或项目任意 `res://` 路径）下，Godot 的
`MagicaVoxel Importer with Extensions` 插件才会接管导入。

---

## 3. voxlib.py API

### 读取

```python
import voxlib

d = voxlib.read_vox("assets/vox/island_scene.vox")
# d = {"models": [{"size": (x,y,z), "voxels": [(x,y,z,ci), ...]}],
#      "palette": [(r,g,b,a) × 256],   # 第 k 项对应颜色索引 k+1
#      "instances": [(model_idx, (tx,ty,tz))],   # 场景图解算后的摆放
#      "trn": {node_id: {"child":.., "t":.., "r":..}}}

blocks = voxlib.vox_to_colors("assets/vox/island_scene.vox")
# 展平成 {(x,y,z): (r,g,b)}，MagicaVoxel 原生 Z-up 坐标，含实例平移
```

命令行速查：

```bash
python voxlib.py inspect D:/Tools/MagicaVoxel-0.99.7.2-win64/vox/chr_knight.vox
# models / 每个模型尺寸与体素数 / 调色板 / 实例摆放 / nTRN 节点
```

### 写入

```python
voxels = {(0,0,0): (255,0,0), (1,0,0): (0,255,0)}   # {(x,y,z): (r,g,b)}
info = voxlib.write_vox("out.vox", voxels)           # size 自动按包围盒算
info = voxlib.write_vox("out.vox", voxels, size=(72,72,29))  # 或显式指定
# 返回 {"size": (...), "voxels": n, "colors": n}
```

- 颜色数**上限 255**，超出会抛错（调色板限制）。
- 自动去重建调色板并按规范写 RGBA（第 k 项 ↔ 索引 k+1）。
- **自动附带场景图节点** `nTRN(0) → nGRP(1) → nTRN(2) → nSHP(3)`——
  这是 Godot 导入插件的硬性要求（见第 6 节）。

### 预览渲染

```python
voxlib.render_iso(voxels, "preview.png", cell=5, up_axis="z")
# cell：每体素半宽像素；up_axis="z" 表示输入是 MagicaVoxel 原生坐标（默认）
# 返回 (宽, 高)
```

2:1 等距投影，画家算法（自下而上 + 由远及近），顶面/右侧/左侧分别 1.0 / 0.76 / 0.55 明度。
纯 Python 光栅化，`cell=5` 的 3 万体素约 2~4 秒；只做自检，别拿它当生产渲染器。

---

## 3.5 gen_units.py —— 单位造型（玩家机 / Boss / E1~E6）

```bash
python gen_units.py        # 输出 assets/vox/units/*.vox + _preview_*.png
```

造型全部用 `put(x, y, z, col)` / `_sym()` 程序化写出来，坐标约定 **x=左右（只画 x>=c 的右半边，再按 `2c-x` 镜像）、y=前后（数值小 = 游戏 -Z）、z=高低**，
与 `vox_reader.gd` 的 `godot(x,y,z) = vox(x,z,y)` 配套。

### ⚠️ 分辨率约定（不要改错）

**所有单位按 0.3 世界单位/体素建模，在 `game.gd` 里统一 `scale = 0.3`（Boss 例外，0.5）。**
所以「体素数 = 造型细节量」，敌机必须和玩家机（15×19）、Boss（17×24）落在同一量级，
否则在正交 34 的相机里就是"几个大方块"，认不出是什么 —— 初版敌机只有 3~5 体素宽（E1 才 9 体素、
E6 才 101 体素），就是这个毛病：看着"太简单、看不出是什么"。重做后是 11~25 体素宽、175~3413 体素。

| 资产 | 尺寸（体素） | 世界尺寸（×0.3） | 说明 |
|---|---|---|---|
| `player.vox` | 15×19×6 | 4.5×5.7×1.8 | 玩家机，青色座舱脊线是俯视主要识别特征 |
| `boss.vox` | 17×24×6 | 8.5×12×3.0（×0.5） | Boss 方舟战舰 |
| `E1.vox` | 11×11×3 | 3.3×3.3×0.9 | 炮台基座（地面单位，贴海面摆放） |
| `E1H.vox` | 11×19×6 | 3.3×5.7×1.8 | 双管炮塔，炮管朝 **-Y**（游戏 -Z），`look_at` 转向玩家 |
| `E2.vox` | 15×15×8 | 4.5×4.5×2.4 | 环形机：厚壁能量环 + 环心悬浮核心 + 四座发射器 |
| `E3.vox` | 15×13×4 | 4.5×3.9×1.2 | 四旋翼无人机·机身（X 形悬臂 + 吊舱），朝向稳定不自转 |
| `E3R.vox` | 19×17×1 | 5.7×5.1×0.3 | E3 旋翼层：四组十字桨盘，挂机身顶部单独绕 Y 旋转（14 rad/s） |
| `E4.vox` | 19×20×5 | 5.7×6.0×1.5 | 后掠翼战斗机，机头朝 **+Y**（迎向玩家） |
| `E5.vox` | 19×24×7 | 5.7×7.2×2.1 | 重型巡洋机，矩形直翼 + 双发吊舱 + 白色识别带 |
| `E6.vox` | 21×29×14 | 6.3×8.7×4.2 | 精英炮舰：尖艏 + 多层甲板 + 主/副炮 + 舰桥青窗 + 三联引擎 |

**朝向约定（踩过坑）**：地面炮台（E1H）的炮管要沿 **-Y**，因为 `look_at` 让节点的 -Z 指向目标，
而 `godot_z = vox_y`；空中单位（E3~E6）则是机头朝 **+Y**（游戏 +Z，正对玩家）。

**贴地对齐**：体素网格以「块的整数键均值」居中，键与几何中心差半格，所以 `game.gd::_spawn_ground`
用 `-mesh.get_aabb().position.y * ENEMY_SCALE` 反推；E1 炮头偏移也由两者 AABB 反推
（`base_aabb.end.y - head_aabb.position.y`，head 继承父节点缩放所以不用再乘），**改模型高度不必改 game.gd**。

**敌机字符画已清零**：`game.gd` 里旧的 `ART_*` 常量与 `PAL_ENEMY` 调色板已全部删除。
剩下的程序化方块只有地貌（草岛 / 暗礁 / 沉船）与幸存者（`survivor_unit.gd`），不属于"单位造型"。

**认物要看两张图**：`asset_review.gd` 出的是等距图（看层次），
`_sheet_enemies_topdown.png` 是各资产的 `*_play.png`（游戏相机同向俯视，看实际读感）——改完造型两张都要看。

---

## 3.6 gen_pirate.py —— 海盗关卡地图切片

```bash
python gen_pirate.py       # 输出 assets/vox/pirate/*.vox + _preview_*.png + _preview_layout.png
```

| 切片 | 体素数 | 说明 |
|---|---|---|
| `pirate_sea.vox` | ~4.1k | 64×64 开放海面瓦片，正弦周期整除边长 → 可无缝平铺 |
| `pirate_island.vox` | ~21k | 海盗岛：沙滩 / 棕榈林 / 木栈桥 / 红顶小屋 / 篝火 / 黑旗 |
| `pirate_fort.vox` | ~9k | 要塞岛：石墙垛口 + 四门火炮 + 中央塔楼 + 黑旗 |
| `pirate_ship.vox` | ~8.6k | 三桅帆船：金框炮门 + 红漆舷缘 + 两层方帆 + 艉楼提灯 + 骷髅黑旗 |

两条设计约定（都踩过坑）：

1. **不写水体积素**。所有内容从 `z=0` 往上长，落到游戏里就是"贴着海面"——与既有草岛/暗礁/沉船
   的摆放方式一致。写体素水块会和游戏的海面片打架。
2. **切成多张独立文件**，运行时可只加载关卡当前段需要的那几张，避免一次性解析一张超大地图。
   `_preview_layout.png` 是排布预览（海面瓦片铺 2×6，按行进方向摆上帆船/要塞/海岛），
   用来一次看清整体效果与相对比例。

海面瓦片注意别用"高度场 + 大面积浪花"（等距预览会糊成一块块浮冰），改用**单层水面 + 颜色分带**表现浪纹。
帆船船体只保留外壳/甲板/底（内部空腔不可见），体素数能砍掉 2/3。

---

## 3.7 voxspec.py —— 声明式 spec 管线（AI 体素管线 L2，阶段 0/1 已交付）

设计文档：`llmdoc/ai-voxel-pipeline.html`（op 集合、校验项、§9 评审修订）。
大模型（或人）只写 **spec JSON**（十几个 op），编译器负责展开、校验、落盘——
编译器是唯一写 .vox 的出口，模型胡编的后果从"坏资产进游戏"降级为"一次失败重试"。

```bash
python voxspec.py check  specs/e1.json            # 编译+校验，不落盘
python gen_spec.py specs/                          # 批量：编译+审计+预览（dry，不碰正式资产）
python gen_spec.py specs/e7.json --write           # 新资产：写 assets/vox/units/
python voxspec.py verify specs/e1.json --ref ../../assets/vox/units/E1.vox
                                                   # 逐体素比对（零回归闸门 / 漂移检测）
```

### spec 结构与 op 语义

顶层：`name / category(air|ground) / facing(+Y|-Y|none) / palettes(["player"|"enemy"]) /
axis(镜像轴 c) / parts:[{file, ops}]`（多部件单位如 E3+旋翼层用多个 part）。
坐标约定与 gen_units.py 完全一致（x=左右按 2c-x 镜像、y=前后、z=高低）。

op 分两类（**solid / paint 语义分离**，§9.2）：

| op | 类别 | 语义 |
|---|---|---|
| `box` / `symbox` | solid | 闭区间实心块；symbox 自动镜像 |
| `oct` | solid | 八边形柱（`cx,cy,r,cut`），`edge` 可换外缘色（`mode: ring\|cheb`） |
| `ring` | solid | 欧氏圆环（`cx,cy,r_in,r_out,z`，`r_in=0` 即圆盘）——能量盾 / 环形轮廓 |
| `profile` | solid | 沿 y 逐行按 `half` 表铺层（`z` 为层→色表）；`edge:{z,within,col}` 表达「翼尖红」类相对条件；`x0` 支持翼段从 dx>2 起 |
| `dots` | solid | 点枚举（数学刻线等零星装饰的兜底，别用它写主体） |
| `paint` | solid 之外 | **只改已存在体素的颜色，绝不新增**——覆盖涂色不会长出新块 |

校验项（编译时强制 / 警告）：调色板引用（≤255 色）、左右对称（报错）、
连通性 ≥99%（警告+漂浮块坐标）、量级带（宽 11~21 / 长 ≤29 / 体素 175~3000，越带警告）、
敌机 facing 必须 +Y。落盘前按坐标排序 → **同 spec 字节级可复现**。

### 零回归闸门（已通过）

`specs/e1.json`、`specs/e4.json`、`specs/player.json` 反向导出自
`build_e1_base()` / `build_e4()` / `build_player()`，verify 按 `(x,y,z)→(r,g,b)`
逐体素一致（E1 175 / E4 498 / player 512 体素，全部 PASS）。**既有资产真源仍是
gen_units.py**（§9.4：不迁移，spec 是验证样本兼漂移检测基准）；新单位直接写 spec。

### 与既有通道的关系

- `gen_units.py`：不变，继续作为既有资产的真源；
- spec 通道：新单位（E7+）与 AI 产出的入口；`verify` 兼作漂移检测——
  .vox 被 MagicaVoxel 手工精修后与 spec 不一致时会报差异，
  区分"编译器回归"（必须修）与"手工精修漂移"（更新或废弃 spec）；
- 地貌（gen_pirate / gen_scene）**不走** spec 管线（范式不同，见 §9.5）。

### AI 产 spec（阶段 2）

`specs/PROMPT.md` 是喂给大模型的提示词模板（schema / op 语义 / 调色板纪律 /
量级基准 / 视觉初筛清单）。端到端冒烟样本：`specs/e7.json`（E7 武装直升机，
双 part：机身 + 独立旋翼层）——一句描述 → spec → 编译器拦错（漏镜像）→
初筛 2 轮（新增 assembly 合成预览）→ `--write` 落盘 `E7.vox` / `E7R.vox`。
多部件单位的初筛看 `_spec_preview_<name>_all.png`（装配合成图）。
E7 已接入三关波次（与批量产出的 E8/E9/E10 一同，见 `stages.gd`）。

### 单位审查场景（认物快捷键）

`scenes/unit_review.tscn`（F5 运行当前场景）：player / boss / E1~E10 全部摆成 4×3 阵列，
旋翼旋转、E1 炮头扫摆。**快捷键 `1` = 正交 34 / (0,30,12) 游戏机位**（与 game.gd
完全一致，认物用这个）；`2` 等距（看层次）、`3` 特写（正交 8 看块面）、
`←/→` 切单位、`S` 全家福/单看、`R` 自转、`Esc` 退出。
spec 管线的视觉验收优先用本场景，等距 PNG 只做初筛。

---

## 3.8 gen_tiles.py —— 瓦片雄鹰瓦片集（M0 交付 / M1 两次修订）

    python gen_tiles.py
    # → assets/vox/tiles/  sea_a~f / sea_crest / shoal / reef_s
    #                      island_4x4（64×64 = 4×4 格）/ island_2x2（32×32 = 2×2 格）/ sandbar_2x2
    #   + seam_test.vox（2×2 接缝测试）+ tools/vox/_preview_*.png / _preview_tiles_layout.png

### 瓦片三规格（llmdoc/tile-eagle-design.html §2 拍板，全工程约定）

| 项 | 值 | 说明 |
|---|---|---|
| 瓦片边长 | **16 体素 = 4.8 世界单位** | 体素缩放 0.3 不变；走廊 13 列覆盖 62.4（正交 34 视野宽 60.44） |
| 锚点 | **底面中心 / 水面层顶面统一 y=0.30** | 公共管线 `voxel_model.gd` 的 AABB 居中**不改**；游戏端 `tiles.gd` 反推 `off`。⚠️ **y 不能用 AABB 反推**（水面层只出顶面 → 单层瓦没有底面），要用**方块键的 y 均值**；x/z 仍用 AABB |
| 北向 | **vox +Y = 游戏 -Z** | `rot ∈ {0,90,180,270}` 只旋转不镜像；镜像瓦片必须翻转三角面绕序（M3.13 教训） |

### 尺寸纪律（M1 修订）：岛/沙洲只走超级瓦整张资产

| 档 | 资产 | 体素 | 世界尺寸 | 用途 |
|---|---|---|---|---|
| 大 | `island_4x4` | 64×64×6 | 19.2 单位 | 主岛（有机轮廓 + 沙环 + 草丘台地） |
| 中 | `island_2x2` | 32×32×5 | 9.6 单位 | 小岛 |
| 中 | `sandbar_2x2` | 32×32×4 | 9.6 单位 | 沙洲（比岛矮一档，最高 1.2） |

M0 的 1×1 `isle_grass` / `isle_sand` **已废弃删除**——1×1 的岛在 62.4 宽的走廊里摆出来就是
「撒了一地小白点」，而且多瓦拼装做不出有机岸线（design §13.4 ⑨ / §14.1）。
`build_island(rng, S)` 的几何常量全部按 `k = S/32` 等比缩放，S 必须是 16 的整数倍
（48=3×16、64=4×16 都能用），换尺寸只需改 S。

### 产线约束（新瓦片必须遵守）

- **边缘无缝**：噪声/正弦按 `(x mod 16, y mod 16)` 周期采样，正弦周期必须整除 16（现用 8）。
  ⚠️ 超级瓦（64/32）的**瓦外水面**也必须按 **mod 16 网格**取同一个噪声——若按 `x/S` 归一化，
  噪声尺度会与相邻海面瓦差 2~4 倍，瓦界立刻显出一个「方形水斑」；
- **边缘余量**：滩面的最大半径 = `RAD + warp_max`，瓦最远的几何面在 `d = S/2 + 1`（体素索引相对 `c=(S-1)/2`），
  必须留 ≥1 体素余量，否则沙会顶到瓦边、在瓦界立起一道「沙崖」；
- **分层烘焙要同基准**：`tiles.gd::_build_tile_mesh` 把水面层与上层分两次 `build_blocks`，
  两次的键均值不同 → 合并前必须按 `(自身均值 − 全局均值)` 平移，否则水面与陆地的相对高度会错
  （4×4 岛会错到沙滩沉入水下、瓦界露出 0.3 高台阶）；
- **底色水面必须与海面瓦同源**：任何「水上漂着东西」的瓦（礁 / 浪尖 / 浅滩）的 z=0 层都要走
  `_sea_color`，**不许**整块铺一个扁平色（M0 的礁瓦铺 SEA_D，走廊里会显成一个「把浪带切断的暗方块」）；
- **贴边余量（抬升类体素）**：凡是会立起侧立面的体素（浪尖瓦的泡沫块 `CREST_MARGIN=3`、
  礁瓦的岩体 `REEF_MARGIN=3`）都必须离瓦边 ≥3 体素——贴边的块会对着邻居的 z=0 水面立墙，
  在瓦界留下一排 1 体素高的小缝。⚠️ 余量取 3 不是 2：探针阈值是 `|顶点| > 半宽−1.5`，而网格
  原点按「键均值」居中（均值 ≈ 7.49 ≠ 7.50），margin=2 时最外面的竖直面落在 6.511 上，**刚好越界**；
- **带浪带的瓦一律 rot=0**：`_band` 的相位是全局特征，旋转 90° 会把相位也转过去 → 瓦界浪纹断开。
  海面系瓦、浪尖瓦、礁瓦（M1 起底色带浪带）都受这条约束；礁瓦的四向变化改由「峰位随机」提供；
- **单层水面**：海面 1 体素高，颜色分带表现浪纹（`gen_pirate.py` 踩坑结论），浪尖瓦最多 2 层；
- **高瓦从水长出**：礁/沙洲/岛的底层先铺 1 层水色（SHAL/SEA_D），内容从 z=0 往上长，不留悬空洞；
- 排布（哪行哪列放哪块）不在 .vox 里——那是游戏端 `layout.gd` 的**节奏表**职责，.vox 只管单块本体。

### 改完必须跑的两道回归

```bash
# ① 锚点 / 边缘探针：水面层顶面世界高度必须全部 = 0.3000，贴瓦边的竖直面顶点数必须全部 = 0
#   （M1 第三步起无例外：浪尖瓦 60→0、礁瓦 114→0）
"...Godot...console.exe" --headless --path <项目> -s res://tools/tile_eagle/_mesh_probe.gd
# ② 出图验收：三机位 + 关云 + 关阴影 + 战斗图（同种子构图，可逐像素复现）
"...Godot...console.exe" --path <项目> -s res://tools/tile_eagle/shot.gd
# ③ M1 玩法冒烟：固定步长跑满整张波次表，检查生成/落岛/弹幕/击杀/死亡重开
"...Godot...console.exe" --headless --path <项目> -s res://tools/tile_eagle/_play_smoke.gd
```

### 逐列高度表（M1 起，地面单位落位用）

`tiles.gd::get_tile()` 返回的字典除 `mesh/off/span` 外，还有两个 M1 新增字段：

| 字段 | 内容 |
|---|---|
| `heights` | `PackedFloat32Array`，下标 `(z−mn.z)·sx + (x−mn.x)`，值 = 该列顶面的**世界 y** |
| `landing` | 可落位列的**网格局部坐标**列表——岸线沙面（0.60）+ 可站立平台面（≤3.0，M2 起含要塞甲板/城墙顶） |

**关键恒等式**：世界 y = `(列顶体素数 + 1) × 0.3`，与瓦片的均值基准无关
（因为 `off.y ≡ mean_key.y`），所以水面恒 0.30、沙滩恒 0.60、草丘恒 0.90~1.50。
落点的世界坐标 = **瓦片实例变换 × `landing[i]`**（game.gd `_cell_xf`），
与画瓦片用的是同一份变换，因此"反算的落点"和"看到的瓦片"不可能对不上。
（M1 时这个字段叫 `shore`、只收沙面；M2 要塞是石头结构，只认沙面会让炮台永远上不了要塞。）

---

## 3.9 terraintile.py —— 地形/结构瓦 spec 编译器（M2）

    python terraintile.py build specs/terrain     # 批量：目录下全部 .json
    python terraintile.py check specs/terrain/fort_wall.json

与 `voxspec.py`（单位编译器）的关系是**「共用 op 展开，另立 schema」**：op 层直接调
`voxspec.compile_part`，校验层换地形瓦自己的约束——

| 约束 | 内容 |
|---|---|
| 画布 | `16 × span`（span ∈ 1/2/4），越界体素编译期报错 |
| **禁写 z=0** | 那一层属于水面板（自动铺一张与 `sea_*` 同源的），内容必须从 z=1 长起 |
| 高度 | ≤ 24 体素 = 7.2 世界单位 |
| 镜像 | 不支持 `symbox` / `profile` / `mirror`——16 宽瓦的对称轴在 7.5，整数轴镜像必偏半格 |

调色板 `TILE_PALETTE` 直接引用 `gen_tiles` 的共享色库（含 M2 新增 `WOOD`/`WOOD2`），
结构瓦与程序化瓦永远同色。M2 产出 4 张：`fort_wall` / `fort_tower` / `fort_gate` / `dock_2x2`。

**贴边余量条目的边界**：那条纪律管的是**水线附近的碎块**（浪尖泡沫/礁石），不是跨瓦连续结构——
`fort_wall` 刻意沿 x 顶满瓦边，相邻同类瓦接上后是连续墙线。探针的 `EDGE_OK` 白名单登记了这一条例外。

## 3.10 gen_pirate_tiles.py —— 外来 64×64 资产接入（M2）

    python gen_pirate_tiles.py
    # → assets/vox/tiles/fort_4x4.vox + 控制台兼容性报告

把 `assets/vox/pirate/pirate_fort.vox` 接成 span=4 超级瓦。**兼容性结论：能接入，但 3 处必须归一**
（完整报告见 `llmdoc/tile-eagle-design.html` §17.1）：

| # | 冲突 | 归一动作 |
|---|---|---|
| ① | 内容包围盒不是 16 的倍数（55×49） | 平移到原点即可——span 只管占位掩码，几何由 AABB 居中 |
| ② | z=0 底层覆盖 54% 且没有一滴水 | 用 `_sea_color` 补齐整张 64×64 水面板（与海面瓦同源 → 瓦界无缝） |
| ③ | 外来底层与水面同高（y=0.30） | **整个结构抬 1 体素**——否则游戏端水面材质按「朝上的面 × y<水位线」判定时，沙滩会被误判成水跟着起伏 |

配色不做 remap：外来陆上结构与本产线 ROCK2/SAND2/GRASS 同族，直接保留。

---

## 4. gen_scene.py 可调项

| 常量 | 默认 | 说明 |
|---|---|---|
| `SIZE` | `(72, 72, 30)` | 场景尺寸（第三个值是高度上限，实际高度由噪声决定，当前产出 29） |
| `WATER` | `5` | 海平面高度 |
| `SEED` | `20260910` | 随机种子，换一个就是另一座岛 |
| `C_*` | 14 色 | 调色板：深海/浅海/沙滩/草地/岩石/雪/树干/树叶/墙/屋顶/门 |

生成逻辑顺序：值噪声高度场（3 倍频）→ 径向衰减成岛 → 分色（雪/岩/草/沙）→ 水面填充
→ 撒 14 棵树（间距 ≥6）→ 在岛心找最平处铺地基并盖 7×7 红顶小屋。

改主题的最快办法：只动 `C_*` 调色板 + `WATER`，例如沙漠主题把 `C_GRASS/C_GRASS2` 换成沙黄、
`C_WATER` 换浅绿、`C_SNOW` 换深棕即可。

---

## 5. .vox 格式要点（改解析器时必看）

```
"VOX " + int32 version(150)
└─ MAIN
   ├─ SIZE  : int32 x, y, z                      模型尺寸
   ├─ XYZI  : int32 numVoxels + (x, y, z, ci) ×n 体素，ci ∈ 1..255，0 表示空
   ├─ RGBA  : 256 × (r,g,b,a)                    第 k 项 ↔ 颜色索引 k+1（规范明确要求）
   ├─ nTRN  : 节点变换（平移 _t、旋转 _r）
   ├─ nGRP  : 节点分组
   └─ nSHP  : 节点引用的模型 id
```

- 每个 chunk：`<id:4> <contentSize:int32> <childrenSize:int32>`，content 后紧跟 children。
- **坐标系**：MagicaVoxel 是 **Z-up**，Godot 是 **Y-up** → `godot(x, y, z) = vox(x, z, y)`。
- **旋转 `_r`**：1 字节。bit0-1 / 2-3 = 第一/二行非零元的列号，bit4 / 5 = 该行符号，第三行取叉积。
  （`_r` 在 DICT 里以字符串存，取值要用首字节，不是 `int(str)`。）
- 官方样例在 `D:/Tools/MagicaVoxel-0.99.7.2-win64/vox/`（chr_knight / castle / monu1 …），
  改解析器时拿它们当回归样本。

---

## 6. 已踩过的坑（别再踩）

| 现象 | 原因 | 处理 |
|---|---|---|
| 编辑器只生成 `.vox.import` 和 `.md5`，没有 `.mesh` | 插件 `unify_voxels()` 取 `vox.nodes[0]`，缺少场景图节点直接崩 | `write_vox` 已自动补 `nTRN/nGRP/nSHP`；自己手写字节时务必带上 |
| 运行时 `load("res://....vox")` 返回 null | 同上，导入没成功 | 代码里有 `VoxReader` 回退，但这说明导入链有问题，应排查 |
| 模型躺倒 | 忘了 Z-up → Y-up | 渲染用 `up_axis="z"`，GDScript 里 `Vector3i(x, z, y)` |
| 颜色全错 / 变成品红 | 调色板索引用成 `pal[ci]` | 正确是 `pal[ci - 1]`；缺调色板时 `_palette_color` 会返回品红占位 |
| 改完 .vox 游戏里还是旧模型 | 编辑器没扫描重导入 | 切回编辑器窗口等 1~2 秒；`.godot/imported/*.mesh` 时间戳会变 |

---

## 7. GDScript 侧：vox_reader.gd

```gdscript
const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")

var blocks := VoxReader.read_blocks("res://assets/vox/xxx.vox")  # {Vector3i: Color}，Y-up
var mesh   := VoxReader.read_mesh("res://assets/vox/xxx.vox")    # ArrayMesh（顶点色+内面剔除）
```

- 支持 `SIZE / XYZI / RGBA / nTRN / nGRP / nSHP`，含 `_r` 旋转解码。
- 输出复用 `VoxelModel.build_blocks()`，网格以 AABB 中心为原点。
- 无场景图节点的文件会退化为「所有模型叠在原点」，不会崩。

游戏里实际接入的是 `game.gd` 的这几个常量（在文件顶部）：

```gdscript
const VOX_DECOR_PATH := "res://assets/vox/island_scene.vox"
const VOX_DECOR_COUNT := 2        # 数量，0 = 关闭
const VOX_DECOR_SCALE := 0.1      # 仅运行时解析路径用（1 体素 = 0.1 世界单位）
const VOX_DECOR_REPLACE := true   # true = 体素岛替换全部草岛（当前开启；暗礁/沉船仍为程序化）
```

`_spawn_vox_decor()` 逻辑：优先 `load()` 编辑器导入产物（已烘焙 0.1 缩放，scale=1）→
失败则 `VoxReader.read_mesh()`（scale=0.1）→ 按 `p.y = -aabb.position.y * s - 0.1` 贴海面 →
随机绕 Y 旋转 → 挂 `world` 并 `append` 进 `islands` 数组，
**直接复用既有的 z 回绕（>30 回卷 -230）与波浪穿模剔除逻辑**。

换模型只改 `VOX_DECOR_PATH`；数量改 `VOX_DECOR_COUNT`。

**单位（玩家机 / Boss / E1~E5）走的是另一条路径**：`VoxReader.read_mesh()` 运行时解析，不依赖编辑器导入产物。
玩家机 / Boss 直接写死在 `_build_player()` 与 `_spawn_boss()` 里；E1~E5 由顶部的 `ENEMY_VOX` 路径表 +
`_load_vox_mesh()` 统一加载（失败退化为占位方块，保证流程可跑）。换敌机造型 = 改 `gen_units.py` 重跑，
或直接用 MagicaVoxel 改 `assets/vox/units/*.vox`，重开游戏即生效。

---

## 8. 验证

```bash
# 1) Python 侧：解析官方样例 + 写入读回
python voxlib.py inspect D:/Tools/MagicaVoxel-0.99.7.2-win64/vox/chr_knight.vox

# 2) Godot 侧：headless 跑真实场景，打印 World 子节点与体素岛 AABB
"D:/Tools/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path "D:/GithubProjects/Godot-game/0-demo-game" -s res://tools/vox/_smoke.gd

# 2b) spec 管线：零回归闸门 / 漂移检测（headless，纯 Python）
python voxspec.py verify specs/e1.json --ref ../../assets/vox/units/E1.vox   # 期望 PASS

# 3) 量化审计（绕序 / 法线风格 / 光照预算，headless）
"...Godot...console.exe" --headless --path <项目> -s res://tools/vox/asset_audit.gd

# 3b) 敌机回归：E1~E5 .vox 加载 + 生成 + 更新循环（含 E1 炮头 look_at），headless
"...Godot...console.exe" --headless --path <项目> -s res://tools/vox/_check_enemies.gd

# 4) 视觉验收（需要 GPU，会短暂开窗；输出到 %TEMP%/vox_review）
"...Godot...console.exe" --path <项目> -s res://tools/vox/asset_review.gd
python pngsheet.py sheet.png 4 --scale 0.9 <临时目录>/*_iso.png   # 拼接触表便于一次看完

# 5) 游戏相机视角：核对"实际看到的样子"与物体比例（认物/尺寸争议时最有用）
"...Godot...console.exe" --path <项目> -s res://tools/vox/ingame_view.gd
# → ingame_wide.png（1280×720 全景，与游戏窗口同尺度）+ ingame_closeup.png（同尺度并排特写）
```

期望输出：`World children=60`、`体素大岛数量=2`，每座 `aabb_size=(7.2, 2.9, 7.2)`、`pos.y≈1.3`。

> 写临时 headless 脚本时注意：脚本必须 `extends SceneTree`，且在 `_initialize()` 里显式 `quit()`，
> 否则进程不会退出，会被 timeout 杀掉。若脚本里有 `await`，调用方必须 `await` 该函数，
> 否则协程挂起后主流程直接 `quit()`，后续输出全部丢失。
>
> 离屏渲染三个坑：① `Camera3D` 必须**先 `add_child` 入树再 `look_at()`**（`look_at` 依赖全局变换，
> 未入树会报错且朝向不变 → 渲出空图）；② `SubViewport.size` 要在使用前就设好，别等第一帧才 resize；
> ③ 离屏渲染不能用 `--headless`（dummy 渲染器出不了内容），必须带 GPU 跑。

### 审计脚本怎么用（改完模型/材质后跑一遍）

`asset_audit.gd` 输出四张表：

| 表 | 看什么 | 健康值 |
|---|---|---|
| ① 绕序 | 「反向朝外」与「存储法线朝外」两列 | 都是 100% |
| ② 法线风格 | 硬边 / 平滑 | 硬边 = 全部三角面，平滑 = 0 |
| ③ 光照预算 | 各朝向面在线性空间的最亮通道 | 顶面 <1.0（无 `*` 截断） |
| ④ 逐资产朝向分布 | 侧面占比、非轴法线比例 | 非轴法线 = 0%（体素面必须轴对齐） |

⚠️ 亮度要在**线性空间**算：Godot 会把 `albedo_color` 与 `light_color` 都转成线性再相乘，
在线性 >1 才截断。用 sRGB 数值直接相乘会得出"严重过曝"的错误结论。

判朝外用的是严格判据：面中心沿法线内推 0.25 格应落在实心体素内、外推 0.25 格应在空处。
注意体素网格以「块中心」居中（`c = pos + 0.5 - center`），键与几何中心差半格——
判据里必须按 `Vector3(k) + (0.5,0.5,0.5) - mean_key` 还原，否则单块模型会误报全 0%。

---

## 9. 幸存者外观测试场景

改动幸存者造型/尺寸或讨论"看得清不清"时，直接跑这个场景，不必等关卡波次刷出来：

**打开方式**：编辑器里打开 `scenes/survivor_test.tscn` → **F5（运行当前场景）**

| 键 | 作用 |
|---|---|
| `方向键` / `WASD` | 开飞机（与游戏同速 24 单位/秒，飞行高度 4.5） |
| `1` | 游戏尺度（正交 34 / 相机 (0,30,12)，与游戏内完全一致，截图就用它） |
| `2` | 特写（正交 8，看块面与双臂） |
| `3` | 救援跟拍（3/4 侧前方跟随飞机，看营救全流程） |
| `4` | 缩放循环 0.6 → 0.9 → 1.2（对比"放大是否更好认"） |
| `5` | 背景明暗（深海底色 ↔ 亮灰底，亮底更利于看轮廓截图） |
| `6` | 阴影开关（排查"身边大黑块"是不是投影） |
| `7` | 叹号显隐（游戏内叹号只在玩家 8 格内出现） |
| `T` | 一键演示营救：飞机瞬移到第 6 个幸存者上方 + 自动切跟拍，播完整起吊过程 |
| `R` | 重置全部幸存者（被救起的会复原，解除定格） |
| `空格` | 暂停/继续（同时定格营救推进，便于截图） |
| `Esc` | 退出 |

游戏内幸存者出生**锚定到漂来的地貌顶面**（体素岛滩涂 → 暗礁 → 沉船，按全局 z 选点；无地貌兜底空海面）——注意选点/出生必须按全局 z=world.z+局部 z 计算，按局部 z 会在 world.z 推进后永远落空、出生即在视野外被回收（历史上"一直看不到幸存者"的根因）。

营救判定与游戏完全一致（阈值都在 `survivor_unit.gd`）：悬停进入 **4.5 格** → 开始起吊；
超出 **6.0 格** → 绳索收回；**0.6 秒**拉升 **2.2 格** 并缩到 **0.25 倍** → 计入"已救"，
播 `eagle_rescue` 音效（C5-E5-G5-C6 上行琶音，0.6s，合成器在 `scripts/tetris/sfx_synth.gd`）。

机上还有一圈**营救进度计时圈**（`rescue_ring.gd`）：半径 = `RESCUE_TRIGGER`（4.5），
所以它同时也是"营救判定范围"的可视化；从 12 点方向顺时针填充，青色填充 / 白色底圈，
救起后转黄并保留 0.3 秒再消失。实现要点：
- 用 `ImmediateMesh` 每帧重建两段三角带（底圈 + 填充弧），不依赖 shader，GL Compatibility 可用；
- `aim()` 直接套用相机 basis → 屏幕空间正圆（不必自己去算投影）；
- 材质开 `no_depth_test`，否则会被机身/海面挡住。


> 注意：`3` 救援跟拍有存在的必要——游戏尺度的相机是近乎俯视，飞机机身会投影成一条线并**挡住**被吊起的人。
> 另外营救绳索只有 0.16 格粗，在游戏尺度（正交 34 / 720p）下约 **3 像素**宽，
> 实际游戏里很可能"看不见绳子"；要更醒目就把 `game.gd::_build_player` 里的
> `rm.size = Vector3(0.16, 0.16, 1.0)` 改成 0.3~0.4。

命令行直接出图（不用手点）：

```bash
"...Godot...console.exe" --path <项目> -s res://tools/vox/scene_shot.gd
# CLOSEUP=true → 特写机位；NO_SHADOW=true → 关阴影对比
```

> 造型常量集中在 `survivor_unit.gd`：`SCALE`(0.6) / `ARM_PIVOT`(肩部支点 y=3.1) / `ARM_WAVE`(挥臂角 2.4) /
> `MARK_Y`(叹号高度 6.4) / `MARK_SCALE`(0.55)。改这几个数就能调外观，游戏与测试场景同时生效。
>
> 换算：节点 scale 0.6、基点 y=0.5，所以「局部 y」× 0.6 + 0.5 = 世界高度。
> 当前叹号占世界 y∈[3.6, 5.25]（**高于玩家飞行高度 4.5**）、角色头顶在 y=2.0，
> 即叹号底距头顶 1.6 格；`MARK_Y ≈ 4.2` 可让它贴着头顶。

## 10. 已知限制

- 单文件最多 255 色（.vox 调色板上限）；单模型最大 256³。
- `render_iso` 是纯 Python 光栅化，几万体素级别尚可，再大就慢。
- `_r` 旋转已支持，但**组合多个带旋转实例**的场景没做端到端回归（官方样例多为无旋转）。
- 导出/分发时：运行时依赖 `.godot/imported/*.mesh`，若该文件缺失会自动回退 `VoxReader`（可用，仅启动略慢）。

# 体素工具链（MagicaVoxel ↔ Godot）

用代码直接生成 / 修改 MagicaVoxel `.vox` 场景，并把它接进「方块雄鹰」。
**MagicaVoxel 本身只当查看器和手工微调工具**——它没有 CLI、没有脚本 API、不能 headless 导出，
所以所有自动化都走「直接读写 .vox 文件」这条路（格式是 ephtracy 公开的 RIFF）。

---

## 1. 文件清单

| 文件 | 作用 |
|---|---|
| `tools/vox/voxlib.py` | 核心库：.vox 读 / 写 / 等距预览渲染（纯标准库，零依赖） |
| `tools/vox/gen_scene.py` | 示例生成器：程序化小岛（地形+海洋+树+小屋） |
| `tools/vox/_smoke.gd` | 冒烟测试：headless 跑真实场景，检查体素岛是否挂载成功 |
| `scripts/voxel_eagle/vox_reader.gd` | GDScript 运行时 .vox 解析器 → ArrayMesh |
| `assets/vox/island_scene.vox` | 产物：小岛场景（72×72×29，32946 体素，14 色） |
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
const VOX_DECOR_REPLACE := false  # true = 体素岛替换全部草岛
```

`_spawn_vox_decor()` 逻辑：优先 `load()` 编辑器导入产物（已烘焙 0.1 缩放，scale=1）→
失败则 `VoxReader.read_mesh()`（scale=0.1）→ 按 `p.y = -aabb.position.y * s - 0.1` 贴海面 →
随机绕 Y 旋转 → 挂 `world` 并 `append` 进 `islands` 数组，
**直接复用既有的 z 回绕（>30 回卷 -230）与波浪穿模剔除逻辑**。

换模型只改 `VOX_DECOR_PATH`；数量改 `VOX_DECOR_COUNT`。

---

## 8. 验证

```bash
# 1) Python 侧：解析官方样例 + 写入读回
python voxlib.py inspect D:/Tools/MagicaVoxel-0.99.7.2-win64/vox/chr_knight.vox

# 2) Godot 侧：headless 跑真实场景，打印 World 子节点与体素岛 AABB
"D:/Tools/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path "D:/GithubProjects/Godot-game/0-demo-game" -s res://tools/vox/_smoke.gd
```

期望输出：`World children=60`、`体素大岛数量=2`，每座 `aabb_size=(7.2, 2.9, 7.2)`、`pos.y≈1.3`。

> 写临时 headless 脚本时注意：脚本必须 `extends SceneTree`，且在 `_initialize()` 里显式 `quit()`，
> 否则进程不会退出，会被 timeout 杀掉。

---

## 9. 已知限制

- 单文件最多 255 色（.vox 调色板上限）；单模型最大 256³。
- `render_iso` 是纯 Python 光栅化，几万体素级别尚可，再大就慢。
- `_r` 旋转已支持，但**组合多个带旋转实例**的场景没做端到端回归（官方样例多为无旋转）。
- 导出/分发时：运行时依赖 `.godot/imported/*.mesh`，若该文件缺失会自动回退 `VoxReader`（可用，仅启动略慢）。

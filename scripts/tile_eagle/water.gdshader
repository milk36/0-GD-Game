shader_type spatial;
render_mode cull_back;

// 水面动感（M1 §16.1）。三条设计决定，每条都是被一次失败验证逼出来的：
//
// 【① 相位只写「世界 XZ 的函数」】瓦片是逐块独立 mesh + MultiMesh 实例，相邻两块在瓦界处的
// 顶点世界位置连续。只要相位是 f(world.xz)，瓦界两侧的位移/亮度必然相等，接缝不会裂；
// 若写成 f(local) 或直接叠加 sin(TIME)，两侧各走各的。（p2 分量的周期 2.976 不整除瓦宽 4.8，
// 所以"退化成 local"会在每 4.8 单位的瓦格线上露出错位缝 —— tools/tile_eagle/_probe_wave.gd
// 把 sheen 放大 5 倍就是为了把这个判据看出来。）
//
// 【② 水面/陆地在水位线层面切分，而不是拆成两张 mesh】全部瓦片共用这一份材质：
//   `wmask = 朝上的面 × (世界 y < sea_y + 0.08)`。
//   为什么要叠"法线朝上"这一条：水面层（z=0 的顶面）与陆地块的**底面**同在 y = sea_y，
//   只看高度分不开。为什么不能拆 mesh：岛/礁/沙洲的 z=0 层就是水面板、z≥1 才是陆地，
//   拆成两张 MultiMesh 要动实例/释放/回绕三处代码；而按水位线切分后，海瓦、浪尖瓦、
//   岛瓦、礁瓦、沙洲**自动统一** —— 否则岛瓦那 19.2×19.2 的水面不参与起伏，
//   会在岛周围留下一块"海在动、这块不动"的方斑（诊断图里一眼可见）。
//   代价：浪尖瓦的泡沫块（z=1，跨 y=0.30~0.60）整块 mask=0，比脚下的水面晚动 ±0.055
//   世界单位（≈0.18 体素，正交 68° 下 0.18px）——不可见。
//
// 【③ 主力是亮度行波（sheen），几何振幅（wave_amp）只是配菜】正交俯视下垂直位移几乎不可见：
//   它位移的是一片**没有纹理的连续水面**，而水面的颜色图案是钉在几何上的（跟水面一起动）→
//   整体上下移不产生可读变化。真正读得出来的是①水面相对静止的岛/船在动 ②亮度本身在流。
//   所以 sheen 给得比 wave_amp 大，且亮度波跑得比几何波快（反光比水面跑得快）；
//   两者速度相同就只是一块跟着水面平移的灰板。

uniform float sea_y = 0.30;        // 水位线（altitude.gd 的 SEA）——水面的世界高度
uniform float wave_amp = 0.055;    // 几何起伏幅度（世界单位；0.055 ≈ 0.18 体素）
uniform float wave_len = 4.8;      // 主涌浪空间周期（世界单位）＝ 一格瓦宽，与瓦格同拍
uniform float wave_speed = 1.15;   // 几何相位流速
uniform float sheen = 0.30;        // 浪光（亮度行波）幅度，相对值

varying float v_amp;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 瓦片实例的 basis 只含绕 Y 旋转 → 模型空间法线的 y 分量 = 世界空间法线的 y 分量
	float wmask = step(0.5, NORMAL.y) * (1.0 - step(sea_y + 0.08, wp.y));

	// 两组方向不同的行波叠加：单正弦会读成整片海在"呼吸"，交叉两组才有方向性
	float p1 = (wp.x + wp.z) / wave_len * TAU + TIME * wave_speed;
	float p2 = (wp.x - wp.z) / (wave_len * 0.62) * TAU - TIME * wave_speed * 0.77;

	float g = sin(p1) * 0.62 + sin(p2) * 0.38;                            // 几何：涌浪
	float s = sin(p1 + TIME * 1.9) * 0.5 + sin(p2 - TIME * 2.4) * 0.5;    // 浪光：跑得更快

	v_amp = (g * 0.45 + s * 0.55) * wmask;
	// 位移量以世界单位给出，而 VERTEX 在模型空间：MODEL_MATRIX 第 1 列的长度 = 该实例的 Y 缩放
	VERTEX.y += g * wave_amp * wmask / max(length(MODEL_MATRIX[1].xyz), 0.0001);
}

void fragment() {
	// COLOR = 网格顶点色 × MultiMesh 逐实例色（打破同瓦重复感的亮度抖动仍在）
	ALBEDO = COLOR.rgb * (1.0 + v_amp * sheen);
	ROUGHNESS = 0.85;
}

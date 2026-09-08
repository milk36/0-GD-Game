extends Control
## 赛博朋克背景:地平线透视网格、扫描线、地平线光带。静态绘制。

func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cyan := Color("#00f0ff")

	# 地面透视网格(下半屏,水平线间距向下递增)
	var horizon := h * 0.42
	for i in 13:
		var t := float(i) / 12.0
		var y := horizon + (h - horizon) * pow(t, 2.2)
		draw_line(Vector2(0, y), Vector2(w, y), Color(cyan, 0.05))
	# 消失点放射垂直线
	var vp := Vector2(w / 2.0, horizon - 120.0)
	for i in 15:
		var x0 := w * float(i) / 14.0
		draw_line(Vector2(x0, horizon), Vector2(vp.x + (x0 - vp.x) * 3.0, h), Color(cyan, 0.045))

	# 地平线光带(粉芯 + 青晕)
	draw_line(Vector2(0, horizon), Vector2(w, horizon), Color("#ff2a6d", 0.30), 1.5)
	draw_line(Vector2(0, horizon), Vector2(w, horizon), Color(cyan, 0.10), 6.0)

	# 全屏扫描线
	var dark := Color(0, 0, 0, 0.05)
	var y := 0.0
	while y < h:
		draw_rect(Rect2(0, y, w, 2), dark)
		y += 4.0

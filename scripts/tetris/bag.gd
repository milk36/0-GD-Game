extends RefCounted
## 7-bag 随机器:每袋发完 7 种再补袋,保证分布均匀。

var _pool: Array[int] = []


func next() -> int:
	if _pool.is_empty():
		_pool = [0, 1, 2, 3, 4, 5, 6]
		_pool.shuffle()
	return _pool.pop_front()

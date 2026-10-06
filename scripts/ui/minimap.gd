class_name Minimap
extends Control
# Мінікартка: біоми запікаються один раз у текстуру, далі щокадру
# домальовуються тільки точки (гравець білий, вороги червоні).

const CELLS := 120

var _acc := 0.0
var _tex: Texture2D
var _terrain: Terrain
var _player: Player
var _enemies: Enemies
var _shrines: Shrines


func setup(t: Terrain, p: Player, e: Enemies, s: Shrines) -> void:
	_terrain = t
	_player = p
	_enemies = e
	_shrines = s
	custom_minimum_size = Vector2(180, 180)
	_render()


func _render() -> void:
	var img := Image.create(CELLS, CELLS, false, Image.FORMAT_RGB8)
	for z in CELLS:
		for x in CELLS:
			var wx := (float(x) / CELLS - 0.5) * Terrain.SIZE
			var wz := (float(z) / CELLS - 0.5) * Terrain.SIZE
			img.set_pixel(x, z, _cell_color(wx, wz))
	_tex = ImageTexture.create_from_image(img)


func _cell_color(x: float, z: float) -> Color:
	var b: Dictionary = GameData.BIOME[_terrain.biome_at(x, z)]
	var low: Color = b["low"]
	var high: Color = b["high"]
	var h := _terrain.height(x, z)
	return low.lerp(high, clampf((h + 4.0) / 10.0, 0.0, 1.0)).darkened(0.15)


func _process(_delta: float) -> void:
	_acc += _delta
	if _acc >= 0.1:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	if _enemies != null:
		for e in _enemies.list:
			var ep: Vector3 = e["node"].position
			if str(e.get("etype", "")) == "boss":
				draw_circle(_to_map(ep), 4.0, Color(1.0, 0.8, 0.2))
			else:
				draw_circle(_to_map(ep), 2.0, Color(1.0, 0.25, 0.25))
	if _shrines != null:
		for s in _shrines.list:
			if not s["used"]:
				draw_circle(_to_map(s["pos"]), 3.0, Color(0.4, 0.9, 1.0))
	if _player != null:
		var pc := _to_map(_player.position)
		draw_circle(pc, 3.5, Color.WHITE)
		draw_arc(pc, 5.5, 0.0, TAU, 12, Color.WHITE, 1.5)


func _to_map(pos: Vector3) -> Vector2:
	return Vector2(
		(pos.x / Terrain.SIZE + 0.5) * size.x,
		(pos.z / Terrain.SIZE + 0.5) * size.y)

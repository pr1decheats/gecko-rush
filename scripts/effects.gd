class_name RushEffects
extends Node2D

var particles: Array[Dictionary] = []
var labels: Array[Dictionary] = []
var enabled: bool = true
var font: Font = preload("res://assets/fonts/OpenSans-Bold.ttf")

func burst(at: Vector2, color: Color, amount: int = 12) -> void:
	for i in range(amount):
		var angle: float = TAU * float(i) / float(amount) + randf_range(-0.2, 0.2)
		particles.append({"p": at, "v": Vector2.from_angle(angle) * randf_range(70.0, 230.0), "life": randf_range(0.3, 0.65), "max": 0.65, "r": randf_range(3.0, 8.0), "c": color})
	queue_redraw()

func popup(at: Vector2, text: String, color: Color = Color("ffdf83")) -> void:
	labels.append({"p": at, "text": text, "life": 0.85, "c": color})

func clear() -> void:
	particles.clear()
	labels.clear()
	queue_redraw()

func _process(delta: float) -> void:
	if not enabled:
		return
	if particles.is_empty() and labels.is_empty():
		return
	for i in range(particles.size() - 1, -1, -1):
		var item: Dictionary = particles[i]
		item.life -= delta
		item.p += item.v * delta
		item.v.y += delta * 150.0
		if item.life <= 0.0:
			particles.remove_at(i)
	for i in range(labels.size() - 1, -1, -1):
		labels[i].life -= delta
		labels[i].p.y -= delta * 90.0
		if labels[i].life <= 0.0:
			labels.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for item in particles:
		var col: Color = item.c
		col.a *= clampf(float(item.life) / 0.3, 0.0, 1.0)
		draw_rect(Rect2((Vector2(item.p) - Vector2.ONE * float(item.r)).round(), Vector2.ONE * float(item.r) * 2.0), col)
	for item in labels:
		var col: Color = item.c
		col.a *= clampf(float(item.life) / 0.3, 0.0, 1.0)
		var at: Vector2 = item.p
		draw_string(font, at + Vector2(-24, 3), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color(0.05, 0.18, 0.12, col.a * 0.55))
		draw_string(font, at + Vector2(-24, 0), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, col)

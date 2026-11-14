extends SceneTree
## Fly selection follows the mouth's bounded swept reach at any running speed.
const COURSE = preload("res://scripts/course.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func fixture(x: float = 290.0, height: float = 1200.0, wall: int = 0) -> Dictionary:
	return {"x": x, "h": height, "side": wall, "eaten": false}

func _run() -> void:
	await process_frame
	var course: Node2D = COURSE.new()
	root.add_child(course)
	course.set_process(false)
	var mouth := Vector2(300.0, -1200.0)
	course.flies = [fixture()]
	var picked: Dictionary = course.take_fly(mouth, -1)
	check(not picked.is_empty() and picked["position"] == Vector2(290.0, -1200.0), "Close fly is caught at its actual wall position")
	check(bool(course.flies[0]["eaten"]), "Fly is marked eaten atomically")
	check(course.take_fly(mouth, -1).is_empty(), "The same fly is never caught twice")
	course.flies = [fixture(290.0, 1450.0)]
	check(course.take_fly(mouth, -1).is_empty() and not course.flies[0]["eaten"], "A fly250pixels ahead stays on the wall")
	course.flies = [fixture(290.0, 1200.0, 1)]
	check(course.take_fly(mouth, -1).is_empty() and not course.flies[0]["eaten"], "Other-wall fly cannot be caught")
	check(not course.take_fly(mouth, 1).is_empty(), "Correct wall selector catches its fly")
	course.flies = [fixture(290.0, 1200.0)]
	check(course.take_fly(Vector2(395.1, -1200.0), -1).is_empty(), "Fly just beyond105reach is not removed")
	check(not course.take_fly(Vector2(395.0, -1200.0), -1).is_empty(), "Fly exactly105pixels away is reachable")
	course.flies = [fixture(290.0, 1200.0)]
	check(course.take_fly(mouth, -1, 5.0).is_empty(), "Explicit smaller mouth reach is respected")
	check(not course.take_fly(mouth, -1, 10.0).is_empty(), "Explicit reach includes its boundary")
	# At18kpx/s a120Hz step advances150px. A narrower optional reach means
	# neither endpoint alone sees the fly, while the actual swept mouth does.
	var previous := Vector2(300.0, -1100.0)
	var current := previous + Vector2(0.0, -18000.0 / 120.0)
	course.flies = [fixture(290.0, 1175.0)]
	check(course.take_fly(previous, -1, 40.0).is_empty() and course.take_fly(current, -1, 40.0).is_empty(), "Fast-step endpoints alone do not capture distant flies")
	check(not course.take_fly(current, -1, 40.0, previous).is_empty(), "Swept mouth catches a fly passed within an18k-speed step")
	check(course.take_fly(current, -1, 40.0, previous).is_empty(), "Swept catch still processes each fly once")
	course.flies = [fixture(350.1, 1175.0)]
	check(course.take_fly(current, -1, 50.0, previous).is_empty(), "A fly outside the swept capsule remains available")
	course.flies = [fixture(290.0, 1175.0, 1), fixture(290.0, 1175.0)]
	picked = course.take_fly(current, -1, 40.0, previous)
	check(not picked.is_empty() and not course.flies[0]["eaten"] and course.flies[1]["eaten"], "Swept selection skips the opposite wall")
	course.flies = [fixture(290.0, 1200.0), fixture(295.0, 1200.0)]
	check(not course.take_fly(mouth, -1).is_empty() and not course.flies[1]["eaten"], "One call removes at most one fly")
	check(not course.take_fly(mouth, -1).is_empty() and course.take_fly(mouth, -1).is_empty(), "Remaining close fly can be caught separately")
	course.queue_free()
	await process_frame
	print("V27 FLIES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

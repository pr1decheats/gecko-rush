class_name RushAndroidRefresh
extends RefCounted
## Android 11+ Surface frame-rate hint, using Godot's built-in Java bridge.
## Engine.max_fps still limits rendering; Android chooses the physical display mode.
## Call again after surface recreation/resume and after a 60/120 setting change.
## No Android-only class identifiers are referenced, so desktop exports also parse.

static var _request_serial: int = 0

static func request_rate(rate: int) -> bool:
	if not OS.has_feature("android"):
		return false
	_request_serial += 1
	var serial: int = _request_serial
	var requested: int = 120 if rate >= 120 else 60
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
		_commit_cap(60, serial)
		return false
	var wrapper: Object = Engine.get_singleton("JavaClassWrapper")
	var version: Variant = wrapper.call("wrap", "android.os.Build$VERSION")
	if version == null or int(version.get("SDK_INT")) < 30:
		_commit_cap(60, serial)
		return false
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Variant = runtime.call("getActivity")
	if activity == null:
		_commit_cap(60, serial)
		return false
	# Godot's documented bridge runs Java UI work on the Android UI thread.
	var callback: Callable = _request_on_ui.bind(activity, requested, serial)
	var runnable: Variant = runtime.call("createRunnableFromGodotCallable", callback)
	if runnable == null or not _has_java_method(activity, "runOnUiThread"):
		_commit_cap(60, serial)
		return false
	activity.call("runOnUiThread", runnable)
	return true # Queued a hint; this is not a measured/guaranteed device FPS.

static func _request_on_ui(activity: Variant, requested: int, serial: int) -> void:
	if serial != _request_serial:
		return
	var godot: Variant = _java(activity, "getGodot")
	var render_view: Variant = _java(godot, "getRenderView")
	var view: Variant = _java(render_view, "getView")
	var holder: Variant = _java(view, "getHolder")
	var surface: Variant = _java(holder, "getSurface")
	if surface == null or not bool(_java(surface, "isValid")):
		# Main calls again once its surface is ready. Do not cache an old Surface.
		_commit_cap.call_deferred(60, serial)
		return
	var effective: int = requested
	if requested == 120:
		var manager: Variant = _java(activity, "getWindowManager")
		var display: Variant = _java(manager, "getDefaultDisplay")
		var modes: Variant = _java(display, "getSupportedModes")
		var highest: float = 0.0
		if modes is Array:
			for mode: Variant in modes:
				var refresh: Variant = _java(mode, "getRefreshRate")
				if refresh is int or refresh is float:
					highest = maxf(highest, float(refresh))
		if highest < 119.0: # Includes fractional 119.88 Hz, excludes 60/90-only panels.
			effective = 60
	if not _has_java_method(surface, "setFrameRate"):
		_commit_cap.call_deferred(60, serial)
		return
	# API 30 two-argument overload. 0 = FRAME_RATE_COMPATIBILITY_DEFAULT,
	# appropriate for games; do not force disruptive display/resolution switches.
	surface.call("setFrameRate", float(effective), 0)
	# Engine/RenderingDevice state stays on Godot's main thread, not the Java UI thread.
	_commit_cap.call_deferred(effective, serial)

static func _commit_cap(rate: int, serial: int) -> void:
	if serial == _request_serial:
		Engine.max_fps = rate

static func _has_java_method(value: Variant, method: String) -> bool:
	return value is Object and value != null and value.has_method("has_java_method") and bool(value.call("has_java_method", method))

static func _java(value: Variant, method: String) -> Variant:
	if not _has_java_method(value, method):
		return null
	return value.call(method)

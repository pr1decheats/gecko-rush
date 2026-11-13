extends SceneTree
## CI-only: verify actual native launch PNGs against the supplied source art.
## Re-encoding may change PNG bytes, so compare normalized decoded RGBA pixels.

const SOURCE_SHA256 := "59f25a432ae2f364524569d1afa703e01fd1632e1684c6d8d3cb52eb55063e84"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		_fail("Usage: --script check_ios_branding.gd -- original.png compact-launch.png exported@2x.png exported@3x.png")
		return
	if FileAccess.get_sha256(args[0]) != SOURCE_SHA256:
		_fail("Source boot PNG differs from the exact supplied Triada Games logo")
		return
	var source := Image.load_from_file(args[0])
	if source == null or source.is_empty() or source.get_size() != Vector2i(1170, 1075):
		_fail("Source Triada Games logo must decode at 1170x1075")
		return
	var launch := Image.load_from_file(args[1])
	if launch == null or launch.is_empty() or launch.get_size() != Vector2i(1080, 1920):
		_fail("Compact launch handoff must be a portrait 1080x1920 image")
		return
	launch.convert(Image.FORMAT_RGBA8)
	var expected := launch.get_data()
	for index: int in [2, 3]:
		var exported := Image.load_from_file(args[index])
		if exported == null or exported.is_empty():
			_fail("Native iOS launch PNG did not decode: " + args[index])
			return
		if exported.get_size() != launch.get_size():
			_fail("Native iOS launch PNG has different dimensions: " + args[index])
			return
		exported.convert(Image.FORMAT_RGBA8)
		if exported.get_data() != expected:
			_fail("Native iOS launch PNG pixels differ from compact Triada Games handoff: " + args[index])
			return
		print("Native iOS Triada Games @%dx: PASS, compact 1080x1920 decoded RGBA pixels identical" % index)
	print("IOS_BRANDING_PIXELS_PASS: original supplied art preserved; compact handoff identical at both native densities")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

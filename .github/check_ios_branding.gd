extends SceneTree
## CI-only: verify actual native launch PNGs against the supplied source art.
## Re-encoding may change PNG bytes, so compare normalized decoded RGBA pixels.

const SOURCE_SHA256 := "59f25a432ae2f364524569d1afa703e01fd1632e1684c6d8d3cb52eb55063e84"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		_fail("Usage: --script check_ios_branding.gd -- source.png exported@2x.png exported@3x.png")
		return
	if FileAccess.get_sha256(args[0]) != SOURCE_SHA256:
		_fail("Source boot PNG differs from the exact supplied Triada Games logo")
		return
	var source := Image.load_from_file(args[0])
	if source == null or source.is_empty() or source.get_size() != Vector2i(1170, 1075):
		_fail("Source Triada Games logo must decode at 1170x1075")
		return
	source.convert(Image.FORMAT_RGBA8)
	var expected := source.get_data()
	for index: int in [1, 2]:
		var exported := Image.load_from_file(args[index])
		if exported == null or exported.is_empty():
			_fail("Native iOS launch PNG did not decode: " + args[index])
			return
		if exported.get_size() != source.get_size():
			_fail("Native iOS launch PNG has different dimensions: " + args[index])
			return
		exported.convert(Image.FORMAT_RGBA8)
		if exported.get_data() != expected:
			_fail("Native iOS launch PNG pixels differ from supplied Triada Games logo: " + args[index])
			return
		print("Native iOS Triada Games @%dx: PASS, 1170x1075 decoded RGBA pixels identical" % (index + 1))
	print("IOS_BRANDING_PIXELS_PASS: supplied logo preserved at both native launch densities")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

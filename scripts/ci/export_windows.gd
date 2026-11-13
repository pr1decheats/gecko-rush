extends SceneTree
## Prepare only an isolated Windows staging copy; the mobile presets stay frozen.

func _initialize() -> void:
	var staging := OS.get_environment("GECKO_WINDOWS_STAGING_DIR").trim_suffix("/")
	if staging.is_empty() or ProjectSettings.globalize_path("res://").trim_suffix("/") != staging:
		push_error("Run only inside the GECKO_WINDOWS_STAGING_DIR source copy")
		quit(1)
		return
	var config := ConfigFile.new()
	if config.load("res://export_presets.cfg") != OK:
		quit(1)
		return
	var windows := ""
	for section: String in config.get_sections():
		if not section.ends_with(".options") and config.get_value(section, "platform", "") == "Windows Desktop":
			windows = section
	if windows.is_empty():
		quit(1)
		return
	var options := windows + ".options"
	var version := str(ProjectSettings.get_setting("application/config/version"))
	config.set_value(windows, "name", "Windows")
	config.set_value(options, "binary_format/architecture", "x86_64")
	config.set_value(options, "binary_format/embed_pck", true)
	config.set_value(options, "application/modify_resources", true)
	config.set_value(options, "application/file_version", version + ".7")
	config.set_value(options, "application/product_version", version + ".0")
	config.set_value(options, "application/product_name", "Gecko Rush")
	config.set_value(options, "application/file_description", "Gecko Rush")
	config.set_value(options, "application/copyright", "Triada Games")
	config.set_value(options, "codesign/enable", false)
	config.set_value(options, "debug/export_console_wrapper", 0)
	if config.save("res://export_presets.cfg") != OK:
		quit(1)
		return
	print("Prepared Windows x64: embedded game, native icon and version " + version + ".7")
	quit(0)

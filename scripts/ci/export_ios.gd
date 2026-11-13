extends SceneTree
## CI-only: configure an isolated source copy for unsigned Xcode project export.
## This does not build or sign an app and never edits the checkout used by CI.

const PLACEHOLDER_TEAM_ID: String = "0000000000"

func _initialize() -> void:
	var actual_root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var staging_root: String = OS.get_environment("GECKO_IOS_STAGING_DIR").trim_suffix("/")
	if staging_root.is_empty() or actual_root != staging_root:
		_fail("Run this helper only inside the temporary GECKO_IOS_STAGING_DIR copy.")
		return
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 2 or arguments[0] != "--template":
		_fail("Usage: --script scripts/ci/export_ios.gd -- --template /absolute/path/ios.zip")
		return
	var template_path: String = arguments[1]
	if not template_path.is_absolute_path() or not FileAccess.file_exists(template_path):
		_fail("The official ios.zip export template must exist at an absolute path.")
		return
	var presets: ConfigFile = ConfigFile.new()
	var load_error: Error = presets.load("res://export_presets.cfg")
	if load_error != OK:
		_fail("Could not load export_presets.cfg: %s" % load_error)
		return
	var matches: Array[String] = []
	for section: String in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			if str(presets.get_value(section, "platform", "")) == "iOS":
				matches.append(section)
	if matches.size() != 1:
		_fail("Expected exactly one iOS export preset; found %d." % matches.size())
		return
	var section: String = matches[0]
	var options: String = section + ".options"
	presets.set_value(section, "name", "iOS")
	presets.set_value(section, "export_path", "build/ios/GeckoRush.xcodeproj")
	var excluded: String = str(presets.get_value(section, "exclude_filter", ""))
	presets.set_value(section, "exclude_filter", excluded + ",scripts/ci/*,.github/*")
	presets.set_value(options, "custom_template/debug", template_path)
	presets.set_value(options, "custom_template/release", template_path)
	presets.set_value(options, "application/export_project_only", true)
	presets.set_value(options, "application/delete_old_export_files_unconditionally", true)
	# Required by Godot even for project-only export. This is deliberately NOT
	# an Apple-issued team identifier and is overridden by xcodebuild below.
	presets.set_value(options, "application/app_store_team_id", PLACEHOLDER_TEAM_ID)
	presets.set_value(options, "application/bundle_identifier", "org.geckorush.game")
	# Keep native metadata aligned with the gameplay release, independently of
	# stale platform presets from earlier Android-only iterations.
	presets.set_value(options, "application/short_version", str(ProjectSettings.get_setting("application/config/version", "2.3.0")))
	presets.set_value(options, "application/version", str(presets.get_value(options, "application/version", "5")))
	presets.set_value(options, "application/min_ios_version", "14.0")
	for key: String in [
		"application/code_sign_identity_debug", "application/code_sign_identity_release",
		"application/provisioning_profile_uuid_debug", "application/provisioning_profile_uuid_release",
		"application/provisioning_profile_specifier_debug", "application/provisioning_profile_specifier_release"
	]:
		presets.set_value(options, key, "")
	var save_error: Error = presets.save("res://export_presets.cfg")
	if save_error != OK:
		_fail("Could not save the temporary iOS preset: %s" % save_error)
		return
	print("Prepared temporary iOS project-only preset. Team ID 0000000000 is a placeholder; no signing is configured.")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

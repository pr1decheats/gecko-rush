shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 logo = texture(TEXTURE, UV);
	// The source is an opaque photograph of the logo. Remove only its dark
	// navy surround, so the rotating upper region never reveals a rectangle.
	float luminance = dot(logo.rgb, vec3(0.2126, 0.7152, 0.0722));
	float edge = smoothstep(0.040, 0.100, luminance);
	// Fade the atlas split through the empty gap above the letters. Without
	// this, the photograph's faint backdrop exposes a rotating straight edge.
	float seam = smoothstep(0.0, 0.018, abs(UV.y - 707.0 / 1075.0));
	vec3 background = vec3(1.0, 3.0, 15.0) / 255.0;
	COLOR = vec4(max(logo.rgb, background), logo.a * edge * seam * opacity);
}

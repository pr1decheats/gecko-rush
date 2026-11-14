shader_type canvas_item;
render_mode unshaded;

uniform vec4 atlas_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 body_size = vec2(110.0, 205.0);
uniform vec2 body_anchor = vec2(0.48, 0.54);
uniform vec4 eye_region = vec4(0.64, 0.20, 0.10, 0.065);
uniform vec4 second_eye_region = vec4(0.0);
uniform vec4 eyelid_color : source_color = vec4(0.35, 0.65, 0.25, 1.0);
uniform float closed_eye = 0.0;
uniform float stride_phase = 0.0;
uniform float tail_phase = 0.0;
uniform float crawl_amount = 0.0;
uniform float breathing = 0.0;
uniform float sleeping = 0.0;
uniform float unfold = 0.0;
uniform vec2 rest_hip = vec2(3.2, 27.2);
uniform vec2 rest_control = vec2(6.4, -3.2);
uniform vec2 rest_control2 = vec2(6.4, -3.2);
uniform vec2 rest_chest = vec2(0.0, -32.0);
uniform vec2 pose_hip = vec2(3.2, 27.2);
uniform vec2 pose_control = vec2(6.4, -3.2);
uniform vec2 pose_control2 = vec2(6.4, -3.2);
uniform vec2 pose_chest = vec2(0.0, -32.0);
uniform vec2 head_shift = vec2(0.0);
uniform float head_turn = 0.0;
uniform float wall_reach = 26.0;
uniform float wake_curl = 0.0;
varying vec4 vertex_modulate;

vec2 curve(vec2 a, vec2 b, vec2 c, vec2 d, float t) {
	float q = 1.0 - t;
	return q * q * q * a + 3.0 * q * q * t * b + 3.0 * q * t * t * c + t * t * t * d;
}

void vertex() {
	vertex_modulate = COLOR;
	vec2 original = VERTEX;
	if (unfold > 0.0) {
		float u = clamp((0.68 - UV.y) / 0.34, 0.0, 1.0);
		vec2 rest = curve(rest_hip, rest_control, rest_control2, rest_chest, u);
		vec2 posed = curve(pose_hip, pose_control, pose_control2, pose_chest, u);
		float head_weight = 1.0 - smoothstep(0.27, 0.40, UV.y);
		vec2 pivot = (eye_region.xy - body_anchor) * body_size;
		float c = cos(head_turn);
		float s = sin(head_turn);
		vec2 from_head = original - pivot;
		vec2 head = pivot + vec2(c * from_head.x - s * from_head.y, s * from_head.x + c * from_head.y) + head_shift;
		vec2 torso = original + posed - rest;
		VERTEX = mix(original, mix(torso, head, head_weight), unfold);
		float curl_u = clamp((UV.y - 0.68) / 0.32, 0.0, 1.0);
		VERTEX.x -= sin(curl_u * 3.14159265) * 35.0 * wake_curl;
		VERTEX.y -= curl_u * 55.0 * wake_curl;
	}
	float tail_weight = smoothstep(0.65, 0.98, UV.y) * (1.0 - sleeping);
	VERTEX.x += sin(tail_phase + UV.y * 4.0) * 3.8 * tail_weight;
	float left_limbs = 1.0 - smoothstep(0.28, 0.54, UV.x);
	float fore = exp(-pow((UV.y - 0.40) / 0.105, 2.0));
	float rear = exp(-pow((UV.y - 0.65) / 0.105, 2.0));
	VERTEX.y += (sin(stride_phase + UV.x * 1.7) * fore - sin(stride_phase + UV.x * 1.7) * rear) * 3.6 * left_limbs * crawl_amount;
	VERTEX.x += (fore + rear) * cos(stride_phase) * 1.2 * left_limbs * crawl_amount;
	// The padded toe illustrations may reach farther than the physics body.
	// Bring only the fore/rear limbs toward their planted wall contact while
	// retaining the torso/head anchor used by collisions and jumping.
	float contacts = clamp((fore + rear) * left_limbs, 0.0, 1.0);
	float wall_x = -wall_reach + (original.x + wall_reach) * 0.16;
	VERTEX.x = mix(VERTEX.x, max(VERTEX.x, wall_x), contacts * 0.28 * (1.0 - unfold));
	VERTEX.x += breathing * exp(-pow((UV.y - 0.51) / 0.21, 2.0)) * (UV.x - 0.45);
}

void fragment() {
	vec2 pad = TEXTURE_PIXEL_SIZE * 0.5;
	vec2 at = clamp(atlas_rect.xy + UV * atlas_rect.zw, atlas_rect.xy + pad, atlas_rect.xy + atlas_rect.zw - pad);
	vec4 source = texture(TEXTURE, at);
	for (int i = 0; i < 2; i++) {
		vec4 region = i == 0 ? eye_region : second_eye_region;
		vec2 eye = (UV - region.xy) / max(region.zw, vec2(0.001));
		float mask = (1.0 - smoothstep(0.84, 1.0, length(eye))) * step(0.001, region.z);
		// A smoothly shaded lid, rather than stretching a single forehead row
		// across the eye (which would smear helmet stripes and scales).
		vec3 lid = eyelid_color.rgb * (1.05 - eye.y * 0.12 - eye.x * 0.06);
		float crease_y = 0.10 + eye.x * eye.x * 0.13;
		float fold = (1.0 - smoothstep(0.015, 0.055, abs(eye.y - crease_y))) * (1.0 - smoothstep(0.65, 0.90, abs(eye.x)));
		lid = mix(lid, lid * 0.27, fold);
		source.rgb = mix(source.rgb, lid, mask * closed_eye);
	}
	if (source.a < 0.03) {
		source.a = 0.0;
	}
	COLOR = vertex_modulate * source;
}

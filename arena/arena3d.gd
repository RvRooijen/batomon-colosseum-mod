extends Node2D

# Live 3D stadium behind the 2D battle. The monster visuals stay 2D, but every frame
# they are moved to the screen position of a fixed spot on the 3D floor and scaled by
# depth, so they behave like billboards. The camera slowly works through a set of wide
# stadium angles, each with its own pan, and glides from one to the next. Both trainers
# stand behind their team and throw a Poke Ball for every entrance.

@export var variant: String = "day"

const MODEL_PATH = "res://mod/arena/stadium.glb"
const RENDER_SIZE = Vector2i(320, 180)
const FEET = 22.0
const REST_POS = Vector3(0.0, 5.0, 24.0)
const REST_PITCH = -14.0
const REST_HFOV = 96.7
const TRAINER_HEIGHT = 5.0
const MONSTER_SIZE = 1.0
# 1.0 is full perspective; lower keeps front and back row closer in size
const PERSPECTIVE = 0.6
# world grid per team: column spacing in meters, the back row sits a third of a column inward
const COLUMN_SPACING = 4.2
const INNER_GAP = 3.6
const ROW_DEPTH = 8.0
const THROW_TIME = 0.5
const THROW_ARC = 3.0
const SHOT_LENGTH = 14.0
const BLEND_TIME = 4.0
# wide shots: camera start/end, look-at start/end. All stay outside the field and in
# front of both teams so the monsters keep their usual draw order.
const SHOTS = [
	[Vector3(-4.0, 8.0, 30.0), Vector3(4.0, 8.0, 30.0), Vector3(-1.0, 0.0, 3.0), Vector3(1.0, 0.0, 3.0)],
	[Vector3(-17.0, 12.0, 26.0), Vector3(-10.0, 11.0, 29.0), Vector3(1.0, 0.0, 4.0), Vector3(2.0, 0.0, 3.0)],
	[Vector3(17.0, 12.0, 26.0), Vector3(10.0, 11.0, 29.0), Vector3(-1.0, 0.0, 4.0), Vector3(-2.0, 0.0, 3.0)],
	[Vector3(-6.0, 5.0, 30.0), Vector3(6.0, 5.0, 30.0), Vector3(-2.0, 0.8, 0.0), Vector3(2.0, 0.8, 0.0)],
	[Vector3(0.0, 13.0, 32.0), Vector3(0.0, 11.0, 31.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 4.0)],
]

const VARIANTS = {
	"day": {"sun": 1.3, "sun_color": Color(1.0, 0.93, 0.82), "ambient": Color(0.75, 0.72, 0.7), "ambient_energy": 0.6,
		"sky_top": Color(0.2, 0.35, 0.7), "sky_horizon": Color(0.95, 0.7, 0.5), "lamps": 2.0, "spots": false, "snow": false},
	"night": {"sun": 0.08, "sun_color": Color(0.5, 0.6, 1.0), "ambient": Color(0.25, 0.28, 0.45), "ambient_energy": 0.35,
		"sky_top": Color(0.01, 0.01, 0.04), "sky_horizon": Color(0.06, 0.07, 0.16), "lamps": 8.0, "spots": true, "snow": false},
	"snow": {"sun": 0.7, "sun_color": Color(0.85, 0.9, 1.0), "ambient": Color(0.8, 0.85, 0.95), "ambient_energy": 0.8,
		"sky_top": Color(0.55, 0.62, 0.75), "sky_horizon": Color(0.8, 0.84, 0.9), "lamps": 3.0, "spots": false, "snow": true},
}

var _vp: SubViewport
var _cam: Camera3D
var _rest_xform: Transform3D
var _cam2d: Camera2D
var _anchors: Dictionary = {}
var _rest_depth: Dictionary = {}
var _ref_pos: Dictionary = {}
var _m_per_px: float = 0.05
var _time: float = 0.0
var _shake: float = 0.0
var _shot: int = 0
var _prev_shot: int = -1
var _shot_time: float = 0.0
var _prev_end: Transform3D
var _team_of: Dictionary = {}
var _trainers: Array = [null, null]
var _trainer_pos: Array = [Vector3.ZERO, Vector3.ZERO]
var _last_anim: Dictionary = {}
var _throws: Array = []
var _ball_tex: Texture2D
var _ref_depth: float = 15.0
var _trainer_layer: CanvasLayer
var _base_xf: Transform3D

func _ready() -> void:
	process_priority = 100
	var cfg: Dictionary = VARIANTS.get(variant, VARIANTS["day"])
	_build_view()
	_build_world(cfg)
	_load_stadium(cfg)
	if cfg["snow"]:
		_add_snow()
	var bv = get_parent()
	if bv:
		_cam2d = bv.get("camera") as Camera2D
	var signal_bus = get_node_or_null("/root/SignalBus")
	if signal_bus and signal_bus.has_signal("impact_requested"):
		signal_bus.impact_requested.connect(_on_impact)
	_cam.global_transform = _rest_xform
	_set_fov(1.0)
	_collect_visuals()
	# start on the first wide shot rather than the flat-layout rest camera
	_prev_end = _shot_xform(0, 0.0)
	_ball_tex = _make_ball_texture()
	_place_trainer_spots()
	if not _rest_depth.is_empty():
		var total: float = 0.0
		for d in _rest_depth.values():
			total += d
		_ref_depth = total / _rest_depth.size() * MONSTER_SIZE
	_trainer_layer = CanvasLayer.new()
	_trainer_layer.layer = -3
	add_child(_trainer_layer)
	_base_xf = _prev_end
	# the 2D camera's final position for a frame is only known after tweens and shakes ran,
	# so everything that follows it is placed right before drawing
	RenderingServer.frame_pre_draw.connect(_sync)


func _build_view() -> void:
	_vp = SubViewport.new()
	_vp.size = RENDER_SIZE
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)

	var layer = CanvasLayer.new()
	layer.layer = -5
	add_child(layer)
	var rect = TextureRect.new()
	rect.texture = _vp.get_texture()
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)

	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.near = 0.1
	_cam.far = 300.0
	_rest_xform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(REST_PITCH)), REST_POS)
	_vp.add_child(_cam)
	_cam.current = true


func _build_world(cfg: Dictionary) -> void:
	var env = Environment.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = cfg["sky_top"]
	sky_mat.sky_horizon_color = cfg["sky_horizon"]
	sky_mat.ground_horizon_color = cfg["sky_horizon"]
	sky_mat.ground_bottom_color = cfg["sky_top"]
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = cfg["ambient"]
	env.ambient_light_energy = cfg["ambient_energy"]
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if cfg["snow"]:
		env.fog_enabled = true
		env.fog_light_color = Color(0.85, 0.88, 0.95)
		env.fog_density = 0.006
	var we = WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var sun = DirectionalLight3D.new()
	sun.light_energy = cfg["sun"]
	sun.light_color = cfg["sun_color"]
	sun.shadow_enabled = true
	_vp.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(0.369, -0.766, -0.527), Vector3.UP)

	if cfg["spots"]:
		for deg in [40.0, 140.0, 200.0, 340.0]:
			var a = deg_to_rad(deg)
			var spot = SpotLight3D.new()
			spot.light_energy = 6.0
			spot.spot_range = 90.0
			spot.spot_angle = 30.0
			spot.light_color = Color(1.0, 0.95, 0.85)
			_vp.add_child(spot)
			spot.look_at_from_position(Vector3(46.0 * cos(a), 30.0, -46.0 * sin(a)), Vector3(0, 0, 3), Vector3.UP)


func _load_stadium(cfg: Dictionary) -> void:
	var bytes = FileAccess.get_file_as_bytes(MODEL_PATH)
	if bytes.is_empty():
		push_warning("arena3d: stadium model missing")
		return
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	if doc.append_from_buffer(bytes, "res://mod/arena/", state) != OK:
		push_warning("arena3d: could not parse stadium model")
		return
	var scene = doc.generate_scene(state)
	_vp.add_child(scene)
	_tune_materials(scene, cfg)


func _tune_materials(node: Node, cfg: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var mat = mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				mat.roughness = 1.0
				mat.metallic = 0.0
				if mat.emission_enabled:
					mat.emission_energy_multiplier = cfg["lamps"]
	for child in node.get_children():
		_tune_materials(child, cfg)


func _add_snow() -> void:
	var layer = CanvasLayer.new()
	layer.layer = -4
	add_child(layer)
	var p = CPUParticles2D.new()
	p.amount = 160
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.position = Vector2(320, -10)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(360, 4)
	p.direction = Vector2(0.2, 1.0)
	p.spread = 15.0
	p.gravity = Vector2(0, 8)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 45.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(1, 1, 1, 0.85)
	layer.add_child(p)


func _collect_visuals() -> void:
	var bv = get_parent()
	if bv == null:
		return
	var main_size: Vector2 = get_viewport().get_visible_rect().size
	var to_vp: Vector2 = Vector2(RENDER_SIZE) / main_size
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var front: Array = []
	for team in [bv.get("player_team_container"), bv.get("enemy_team_container")]:
		if team == null:
			continue
		for v in team.get_children():
			if not v.has_node("SpriteContainer"):
				continue
			var feet_screen: Vector2 = ct * (v.global_position + Vector2(0, FEET))
			var sv: Vector2 = feet_screen * to_vp
			var o: Vector3 = _cam.project_ray_origin(sv)
			var d: Vector3 = _cam.project_ray_normal(sv)
			if absf(d.y) < 0.0001:
				continue
			var anchor: Vector3 = o + d * (-o.y / d.y)
			_anchors[v] = anchor
			_rest_depth[v] = -(_cam.global_transform.affine_inverse() * anchor).z
			var rc = v.get_node_or_null("ReflectionContainer")
			if rc:
				_ref_pos[v] = rc.position
			_team_of[v] = 0 if team == bv.get("player_team_container") else 1
			if v.global_position.y > 0.0:
				front.append([v.global_position.x, anchor.x])
	if front.size() >= 2:
		front.sort_custom(func(a, b): return a[0] < b[0])
		var dpx: float = front[-1][0] - front[0][0]
		if dpx > 1.0:
			_m_per_px = (front[-1][1] - front[0][1]) / dpx
	_regrid()


func _regrid() -> void:
	# The raycast anchors copy the flat 2D layout, which spaces both rows equally on screen
	# and so spreads the back row wider in the world. Put every team on an even world grid
	# instead and let perspective do the rest; only the row depths are kept.
	var front_z: float = 0.0
	var n_front: int = 0
	for v in _anchors.keys():
		if v.global_position.y > 0.0:
			front_z += _anchors[v].z
			n_front += 1
	if n_front > 0:
		front_z /= n_front
	for t in [0, 1]:
		for row in [0, 1]:
			var members: Array = []
			for v in _anchors.keys():
				if _team_of.get(v, -1) != t:
					continue
				var is_front: bool = v.global_position.y > 0.0
				if (row == 0) != is_front:
					continue
				members.append(v)
			if members.is_empty():
				continue
			var z: float = front_z if row == 0 else front_z - ROW_DEPTH
			members.sort_custom(func(a, b): return absf(_anchors[a].x) < absf(_anchors[b].x))
			var side: float = -1.0 if t == 0 else 1.0
			for i in members.size():
				var x: float = INNER_GAP + i * COLUMN_SPACING - (COLUMN_SPACING / 3.0 if row == 1 else 0.0)
				var a: Vector3 = Vector3(side * x, 0.0, z)
				_anchors[members[i]] = a
				_rest_depth[members[i]] = -(_rest_xform.affine_inverse() * a).z
				# front row sprites draw over the back row
				members[i].get_node("SpriteContainer").z_index = 1 if row == 0 else 0


func _on_impact(intensity) -> void:
	_shake = maxf(_shake, float(intensity))


func _set_fov(zoom: float) -> void:
	var half: float = deg_to_rad(REST_HFOV) * 0.5
	_cam.fov = rad_to_deg(2.0 * atan(tan(half) / maxf(zoom, 0.01)))


func _shot_xform(i: int, t: float) -> Transform3D:
	var sh: Array = SHOTS[i]
	var e: float = smoothstep(0.0, 1.0, t)
	var pos: Vector3 = sh[0].lerp(sh[1], e)
	var target: Vector3 = sh[2].lerp(sh[3], e)
	return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


func _direct(delta: float) -> Transform3D:
	_shot_time += delta
	if _shot_time >= SHOT_LENGTH:
		_prev_end = _shot_xform(_shot, 1.0)
		_prev_shot = _shot
		var next: int = randi() % SHOTS.size()
		while next == _shot:
			next = randi() % SHOTS.size()
		_shot = next
		_shot_time = 0.0
	var xf: Transform3D = _shot_xform(_shot, _shot_time / SHOT_LENGTH)
	if _shot_time < BLEND_TIME:
		# glide over from where the previous shot ended
		xf = _prev_end.interpolate_with(xf, smoothstep(0.0, 1.0, _shot_time / BLEND_TIME))
	return xf


func _place_trainer_spots() -> void:
	# behind each team, on the outer side, centred on the team's depth
	for t in [0, 1]:
		var xs: Array = []
		var zs: Array = []
		for v in _anchors.keys():
			if _team_of.get(v, -1) == t:
				xs.append(_anchors[v].x)
				zs.append(_anchors[v].z)
		if xs.is_empty():
			continue
		var outer: float = xs.min() - 3.0 if t == 0 else xs.max() + 3.0
		var mid_z: float = (zs.min() + zs.max()) * 0.5
		_trainer_pos[t] = Vector3(outer, 0.0, mid_z)


const TRAINER_FADE_SHADER = """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.a *= smoothstep(1.0, 0.8, UV.y);
	COLOR = c * COLOR;
}
"""


func _update_trainers() -> void:
	# The trainer art is high-res and cut off at the knees, so it is drawn in 2D on top of
	# the low-res stadium at the projected spot, with the bottom faded out.
	var bv = get_parent()
	if bv == null:
		return
	var to_main: Vector2 = get_viewport().get_visible_rect().size / Vector2(RENDER_SIZE)
	for t in [0, 1]:
		var rect = bv.get("player_trainer_rect" if t == 0 else "enemy_trainer_rect")
		var tex: Texture2D = rect.texture if rect else null
		if tex == null:
			continue
		if _trainers[t] == null:
			var spr = Sprite2D.new()
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			spr.flip_h = t == 1
			var mat = ShaderMaterial.new()
			var sh = Shader.new()
			sh.code = TRAINER_FADE_SHADER
			mat.shader = sh
			spr.material = mat
			_trainer_layer.add_child(spr)
			_trainers[t] = spr
		var spr2: Sprite2D = _trainers[t]
		if spr2.texture != tex:
			spr2.texture = tex
			spr2.centered = true
			spr2.offset = Vector2(0.0, -tex.get_height() * 0.5)
		var base: Vector3 = _trainer_pos[t]
		if _cam.is_position_behind(base):
			spr2.visible = false
			continue
		spr2.visible = true
		var foot: Vector2 = _cam.unproject_position(base) * to_main
		var head: Vector2 = _cam.unproject_position(base + Vector3(0.0, TRAINER_HEIGHT, 0.0)) * to_main
		spr2.position = foot
		var h: float = maxf(foot.y - head.y, 1.0)
		spr2.scale = Vector2.ONE * (h / maxf(tex.get_height(), 1.0))


func _make_ball_texture() -> Texture2D:
	var n: int = 16
	var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c: float = (n - 1) * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(x - c, y - c).length()
			if d > c + 0.3:
				continue
			var col: Color = Color(0.85, 0.1, 0.1) if y < c else Color(0.95, 0.95, 0.95)
			if d > c - 1.0 or absf(y - c) < 1.0:
				col = Color(0.08, 0.08, 0.1)
			if d < 2.6:
				col = Color(0.08, 0.08, 0.1) if d > 1.6 else Color(1, 1, 1)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _start_throw(v) -> void:
	var ap = v.get("anim_player")
	if ap == null:
		return
	# hold the entrance on its first (invisible) frame until the ball lands
	ap.seek(0.0, true)
	ap.pause()
	var t: int = _team_of.get(v, 0)
	var ball = Sprite3D.new()
	ball.texture = _ball_tex
	ball.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ball.shaded = false
	ball.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	ball.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ball.pixel_size = 0.04
	_vp.add_child(ball)
	var from: Vector3 = _trainer_pos[t] + Vector3(0.0, TRAINER_HEIGHT * 0.7, 0.0)
	_throws.append({"v": v, "ap": ap, "ball": ball, "from": from, "to": _anchors[v] + Vector3(0.0, 0.4, 0.0), "t": 0.0, "flash": null})


func _update_throws(delta: float) -> void:
	for th in _throws.duplicate():
		th["t"] += delta
		var k: float = th["t"] / THROW_TIME
		if th["flash"] == null:
			if k < 1.0:
				var p: Vector3 = th["from"].lerp(th["to"], k)
				p.y += sin(k * PI) * THROW_ARC
				th["ball"].position = p
				th["ball"].rotation.z = -k * TAU * 2.0
			else:
				th["ball"].queue_free()
				var flash = Sprite3D.new()
				flash.texture = _ball_tex
				flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				flash.shaded = false
				flash.modulate = Color(1.6, 1.6, 1.6, 1.0)
				flash.pixel_size = 0.05
				flash.position = th["to"]
				_vp.add_child(flash)
				th["flash"] = flash
				if is_instance_valid(th["v"]) and th["ap"]:
					th["ap"].play()
		else:
			var f: float = (th["t"] - THROW_TIME) / 0.25
			var flash: Sprite3D = th["flash"]
			flash.pixel_size = 0.05 + f * 0.25
			flash.modulate.a = 1.0 - f
			if f >= 1.0:
				flash.queue_free()
				_throws.erase(th)


func _watch_entrances() -> void:
	for v in _anchors.keys():
		if not is_instance_valid(v):
			continue
		var ap = v.get("anim_player")
		var cur: String = String(ap.current_animation) if ap else ""
		if cur == "entrance" and _last_anim.get(v, "") != "entrance":
			var busy: bool = false
			for th in _throws:
				if th["v"] == v:
					busy = true
			if not busy:
				_start_throw(v)
		_last_anim[v] = cur


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)


func _sync() -> void:
	if _cam == null or not is_inside_tree():
		return
	var zoom: float = 1.0
	var pan: float = 0.0
	if is_instance_valid(_cam2d):
		zoom = _cam2d.zoom.x
		pan = _cam2d.position.x
	var xf: Transform3D = _base_xf
	xf.origin += xf.basis.x * (pan * _m_per_px)
	if _shake > 0.0:
		xf.origin += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake * 0.08
	_cam.global_transform = xf
	_set_fov(zoom)
	_place_visuals()
	_update_trainers()


func _process(delta: float) -> void:
	if _cam == null:
		return
	_time += delta
	_base_xf = _direct(delta)
	_shake = move_toward(_shake, 0.0, delta * 4.0)
	_watch_entrances()
	_update_throws(delta)


func _place_visuals() -> void:
	var main_size: Vector2 = get_viewport().get_visible_rect().size
	var to_main: Vector2 = main_size / Vector2(RENDER_SIZE)
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var cam_inv: Transform3D = _cam.global_transform.affine_inverse()
	for v in _anchors.keys():
		if not is_instance_valid(v):
			_anchors.erase(v)
			continue
		var a: Vector3 = _anchors[v]
		if _cam.is_position_behind(a):
			continue
		var depth: float = -(cam_inv * a).z
		# perspective: nearer monsters are drawn bigger
		var s: float = clampf(pow(_ref_depth / maxf(depth, 0.01), PERSPECTIVE), 0.35, 2.5)
		var feet_world: Vector2 = inv * (_cam.unproject_position(a) * to_main)
		v.global_position = feet_world - Vector2(0, FEET * s)
		v.get_node("SpriteContainer").scale = Vector2(s, s)
		var rc = v.get_node_or_null("ReflectionContainer")
		if rc and _ref_pos.has(v):
			rc.scale = Vector2(s, s)
			rc.position = _ref_pos[v] * s

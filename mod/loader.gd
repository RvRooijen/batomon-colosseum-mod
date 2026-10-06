extends Node

# Batomon Pokémon mod loader. It is injected as an autoload through override.cfg next to
# the game exe, so the game's own encrypted pack stays untouched. It mounts
# batomon_mod.pck (3D arena) and swaps sprites, names, cries and music at runtime with
# the files in this folder. Sprites and audio are not shipped; see README.md.

const PACK = "batomon_mod.pck"
const CANVAS = 96
const GROW = 1.4
const FORMS = {
	"Pokémon Egg": "egg", "Marowak (Alola)": "marowak-alola", "Zoroark (Hisui)": "zoroark-hisui",
	"Lilligant (Hisui)": "lilligant-hisui", "Hoopa Unbound": "hoopa-unbound", "Porygon-Z": "porygonz",
}
const MUSIC_SLOTS = {
	"Main_menu.wav": "title", "Shop.wav": "shop", "Shop2.mp3": "shop", "Boss_fight.wav": "boss",
	"Battle_normal_v2.wav": "battle", "Battle 2.mp3": "battle", "BattleMusic.mp3": "battle",
	"Monster_Battle_Fight_OST_loopable.mp3": "battle", "Victory_Fanfare.mp3": "victory",
}
const TYPE_NAMES = {"monster.type.toxic": "Poison", "monster.type.curio": "Psychic"}
const MAP_SCENES = [
	"res://game/maps/meadow/meadow_map.tscn",
	"res://game/maps/caves/cave_map.tscn",
	"res://game/maps/snow_field/snow_field_map.tscn",
]

var mod_dir: String
var mapping: Dictionary = {}
var _species_refs: Array = []
var _cries: Dictionary = {}
var _music: Dictionary = {}
var _last_music: AudioStream
var _cry_player: AudioStreamPlayer
var _badge: Label
var _badge_check: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mod_dir = get_script().resource_path.get_base_dir()
	if ProjectSettings.load_resource_pack(mod_dir.path_join(PACK), true):
		_swap_maps()
	else:
		push_warning("batomon-mod: could not mount " + PACK)
	_read_mapping()
	_apply_sprites()
	_apply_names()
	_load_music()
	_cry_player = AudioStreamPlayer.new()
	_cry_player.bus = "SFX"
	_cry_player.volume_db = -4.0
	add_child(_cry_player)
	var bus = get_node_or_null("/root/SignalBus")
	if bus:
		bus.monster_bought.connect(_play_cry)
		bus.monster_transformed.connect(_play_cry)
	_make_badge()
	print("batomon-mod: loaded from %s (%d mapped, %d music slots)" % [mod_dir, mapping.size(), _music.size()])


func _make_badge() -> void:
	# "Colosseum mod" in the top-left corner of the main menu
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_badge = Label.new()
	_badge.text = "Colosseum mod"
	_badge.position = Vector2(6, 4)
	_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_badge.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.05))
	_badge.add_theme_constant_override("outline_size", 4)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	layer.add_child(_badge)


func _on_title_screen() -> bool:
	# main.gd keeps the active game state in current_state
	var scene = get_tree().current_scene
	var state = scene.get("current_state") if scene else null
	if not is_instance_valid(state):
		return false
	var script = state.get_script()
	return script != null and script.get_global_name() == "TitleState"


func _swap_maps() -> void:
	# Autoloads that ran before this one may already have loaded the battle maps, and the
	# cache keeps serving those. Load them again through the new remaps and swap the scene
	# data into the cached instances that the battle scene already references.
	for path in MAP_SCENES:
		var fresh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not fresh is PackedScene:
			push_warning("batomon-mod: could not load " + path)
			continue
		if ResourceLoader.has_cached(path):
			var cached = ResourceLoader.load(path)
			if cached is PackedScene and cached != fresh:
				cached._bundled = fresh._bundled


func _read_mapping() -> void:
	var f = FileAccess.open(mod_dir.path_join("mapping.txt"), FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or not "=" in line:
			continue
		var parts: PackedStringArray = line.split("=", true, 1)
		mapping[parts[0].strip_edges()] = parts[1].strip_edges()


func slug(display_name: String) -> String:
	if FORMS.has(display_name):
		return FORMS[display_name]
	var re = RegEx.create_from_string("[^a-z0-9]")
	return re.sub(display_name.to_lower(), "", true)


# --- sprites ---------------------------------------------------------------

func _apply_sprites() -> void:
	var db = get_node_or_null("/root/GameDatabase")
	if db == null:
		return
	for sp in db.get_all_species():
		# keep the species resources alive so later loads return these edited instances
		_species_refs.append(sp)
		if not mapping.has(sp.id):
			continue
		var normal: Image = _user_image(sp.id, false)
		if normal and sp.texture:
			sp.texture = _hd_texture(normal, sp.texture)
		if sp.shiny_data and sp.shiny_data.texture:
			var shiny: Image = _user_image(sp.id, true)
			if shiny == null:
				shiny = normal
			if shiny:
				sp.shiny_data.texture = _hd_texture(shiny, sp.shiny_data.texture)


func _user_image(id: String, shiny: bool) -> Image:
	var dir: String = mod_dir.path_join("sprites")
	if shiny:
		dir = dir.path_join("shiny")
	for base in [id, slug(mapping[id])]:
		var path: String = dir.path_join(base + ".png")
		if FileAccess.file_exists(path):
			var img = Image.load_from_file(path)
			if img:
				return img
	return null


func _hd_texture(src: Image, orig: Texture2D) -> Texture2D:
	# Same look as the original sprites: matched to the original's visible area, pixel
	# scaled, 2 px black outline, facing right, bottom-centred on a 96 px canvas that is
	# shown at the original 48 px size.
	var oi: Image = orig.get_image()
	if oi == null:
		return orig
	if oi.is_compressed():
		oi.decompress()
	var used: Rect2i = oi.get_used_rect()
	var area: float = maxf(used.size.x * used.size.y, 1.0)
	src.convert(Image.FORMAT_RGBA8)
	var r: Rect2i = src.get_used_rect()
	if r.size.x == 0 or r.size.y == 0:
		return orig
	var img: Image = src.get_region(r)
	var want: float = sqrt(GROW * 4.0 * area / float(img.get_width() * img.get_height()))
	var fit: float = float(CANVAS - 4) / float(maxi(img.get_width(), img.get_height()))
	var k: float = minf(clampf(want, 1.0, 2.0), fit)
	var w: int = maxi(1, roundi(img.get_width() * k))
	var h: int = maxi(1, roundi(img.get_height() * k))
	if k >= 1.0:
		img.resize(w, h, Image.INTERPOLATE_NEAREST)
	else:
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		for y in h:
			for x in w:
				var c: Color = img.get_pixel(x, y)
				c.a = 1.0 if c.a >= 0.43 else 0.0
				img.set_pixel(x, y, c)
	var sil: Image = img.duplicate()
	sil.adjust_bcs(0.0, 1.0, 1.0)
	var out: Image = Image.create(w + 4, h + 4, false, Image.FORMAT_RGBA8)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if absi(dx) + absi(dy) <= 2:
				out.blend_rect(sil, Rect2i(0, 0, w, h), Vector2i(2 + dx, 2 + dy))
	out.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(2, 2))
	out.flip_x()
	var canvas: Image = Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.blend_rect(out, Rect2i(Vector2i.ZERO, out.get_size()), Vector2i((CANVAS - out.get_width()) / 2, CANVAS - out.get_height()))
	var tex = ImageTexture.create_from_image(canvas)
	tex.set_size_override(Vector2i(orig.get_size()))
	return tex


# --- names -----------------------------------------------------------------

func _apply_names() -> void:
	var t: Translation = TranslationServer.get_translation_object("en")
	if t == null:
		return
	var placeholder = RegEx.create_from_string("\\{[^}]*\\}")
	for key in t.get_message_list():
		var k: String = String(key)
		var text: String = String(t.get_message(key))
		var new_text: String
		if k.begins_with("monster.name.") and mapping.has(k.trim_prefix("monster.name.")):
			var display: String = mapping[k.trim_prefix("monster.name.")]
			new_text = "Dragon Egg" if display == "Pokémon Egg" and "dragon" in k else ("Mystery Egg" if display == "Pokémon Egg" else display)
		elif TYPE_NAMES.has(k):
			new_text = TYPE_NAMES[k]
		else:
			new_text = _reword(text, placeholder)
		if new_text != text:
			t.add_message(k, new_text)


func _reword(text: String, placeholder: RegEx) -> String:
	# rename monsters to Pokémon, but leave {placeholders} alone
	var out: String = ""
	var pos: int = 0
	for m in placeholder.search_all(text):
		out += _reword_plain(text.substr(pos, m.get_start() - pos)) + m.get_string()
		pos = m.get_end()
	return out + _reword_plain(text.substr(pos))


func _reword_plain(s: String) -> String:
	s = s.replace("Batomon", "Pokémon")
	for pair in [["monsters", "Pokémon"], ["monster", "Pokémon"], ["Monsters", "Pokémon"], ["Monster", "Pokémon"]]:
		s = RegEx.create_from_string("\\b" + pair[0] + "\\b").sub(s, pair[1], true)
	return s.replace("an Pokémon", "a Pokémon")


# --- audio -----------------------------------------------------------------

func _load_audio(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var s = AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(path)
			return s
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


func _find_audio(dir: String, names: Array) -> AudioStream:
	for n in names:
		for ext in ["ogg", "mp3", "wav"]:
			var s: AudioStream = _load_audio(mod_dir.path_join(dir).path_join(n + "." + ext))
			if s:
				return s
	return null


func _play_cry(monster) -> void:
	if monster == null or monster.data == null:
		return
	var id: String = monster.data.id
	if not _cries.has(id):
		var names: Array = [id]
		if mapping.has(id):
			names.append(slug(mapping[id]))
		_cries[id] = _find_audio("cries", names)
	if _cries[id]:
		_cry_player.stream = _cries[id]
		_cry_player.play()


func _load_music() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(mod_dir.path_join("music.cfg")) != OK:
		return
	for slot in cfg.get_sections():
		var s: AudioStream = _load_audio(mod_dir.path_join("music").path_join(cfg.get_value(slot, "file", "")))
		if s == null:
			continue
		var start: float = float(cfg.get_value(slot, "loop_start", 0.0))
		var loop: bool = bool(cfg.get_value(slot, "loop", true))
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
			s.loop_begin = int(start * s.mix_rate)
			s.loop_end = int(s.get_length() * s.mix_rate)
		else:
			s.loop = loop
			s.loop_offset = start
		_music[slot] = s


func _process(delta: float) -> void:
	_badge_check -= delta
	if _badge and _badge_check <= 0.0:
		_badge_check = 0.25
		_badge.visible = _on_title_screen()
	# swap the game's tracks for ours as soon as the game starts playing one
	var am = get_node_or_null("/root/AudioManager")
	if am == null or am.get("music_player") == null:
		return
	var p: AudioStreamPlayer = am.music_player
	if p.stream == null or p.stream == _last_music:
		return
	var slot: String = MUSIC_SLOTS.get(p.stream.resource_path.get_file(), "")
	if slot != "" and _music.has(slot):
		var pos_playing: bool = p.playing
		p.stream = _music[slot]
		if pos_playing:
			p.play()
	_last_music = p.stream

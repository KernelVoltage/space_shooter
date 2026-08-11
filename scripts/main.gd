extends Node2D

# --- EXPORTED SCENES ---
@export var enemy_normal_scene: PackedScene = preload("res://scenes/enemy_normal.tscn")
@export var asteroid_scene: PackedScene = preload("res://scenes/asteroid.tscn")
@export var enemy_zigzag_scene: PackedScene = preload("res://scenes/enemy_zigzag.tscn")
@export var boss_scene: PackedScene = preload("res://scenes/mega_boss.tscn")
@export var game_over_scene: PackedScene = preload("res://scenes/game_over.tscn")

# --- UI & TIMERS ---
@onready var spawn_timer: Timer = $UI/SpawnTimer
@onready var phase_timer: Timer = $UI/PhaseTimer
@onready var alert_timer: Timer = $UI/AlertTimer
@onready var alert_label: Label = $UI/Label

var game_over_ui: Control = null
var active_boss_instance: Node2D = null

# --- FADE OVERLAY & TRANSITION STATE ---
var fade_layer: CanvasLayer
var fade_rect: ColorRect
var is_switching: bool = false

# --- 🚀 1GB RAM OPTIMIZATION ENGINE ---
var normal_pool: Array = []
var asteroid_pool: Array = []
var zigzag_pool: Array = []

var cleanup_timer: float = 0.0

func _ready() -> void:
	# Web Focus & Pause Listeners
	get_tree().root.focus_exited.connect(_on_window_focus_lost)
	get_tree().root.focus_entered.connect(_on_window_focus_gained)

	# Signal Connections
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	phase_timer.timeout.connect(_on_phase_timer_timeout)
	alert_timer.timeout.connect(_on_alert_timer_timeout)
	
	# Pause Button Listener
	var pause_btn = find_child("PauseButton", true, false) as BaseButton
	if pause_btn:
		pause_btn.pressed.connect(_on_pause_button_pressed)
	
	var player = get_node_or_null("Player")
	if player and player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)
		
	setup_game_over_ui()
	
	# Smooth Fade Transition Setup & Trigger
	_setup_fade_overlay()
	_fade_in_from_black()
	
	GameManager.reset_game()
	
	# Reset current session coins to ZERO at the start of the match
	if "current_coins" in GameManager:
		GameManager.current_coins = 0

	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		if hud.has_method("update_coins"):
			hud.update_coins(0)
		elif hud.has_method("update_score"):
			hud.update_score(0)
	
	start_phase(GameManager.Phase.NORMAL_ENEMIES)

func _process(delta: float) -> void:
	cleanup_timer += delta
	if cleanup_timer >= 1.5:
		cleanup_timer = 0.0
		_cleanup_offscreen_entities()

# --- SAFE & SMOOTH FADE TRANSITION SYSTEM ---
func _setup_fade_overlay() -> void:
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 128
	fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(fade_layer)
	
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.process_mode = Node.PROCESS_MODE_ALWAYS
	fade_layer.add_child(fade_rect)

func _fade_in_from_black() -> void:
	fade_layer.show()
	fade_rect.color.a = 1.0
	
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(fade_rect, "color:a", 0.0, 0.25)
	
	tween.finished.connect(func():
		fade_layer.hide()
		is_switching = false
	)

func _fade_out_to_black() -> void:
	fade_layer.show()
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(fade_rect, "color:a", 1.0, 0.25)
	await fade_tween.finished

# --- ♻️ RAM OBJECT POOLING SYSTEM ---
func _get_pooled_instance(scene: PackedScene, pool: Array) -> Node2D:
	var instance: Node2D = null
	while pool.size() > 0:
		var candidate = pool.pop_back()
		if is_instance_valid(candidate):
			instance = candidate
			break

	if not instance and scene:
		instance = scene.instantiate()
		
	if instance:
		instance.process_mode = Node.PROCESS_MODE_INHERIT
		instance.visible = true
		if not instance.is_inside_tree():
			add_child(instance)
			
	return instance

func _recycle_entity(entity: Node2D, pool: Array) -> void:
	if not is_instance_valid(entity): return
	entity.process_mode = Node.PROCESS_MODE_DISABLED
	entity.visible = false
	entity.global_position = Vector2(-2000, -2000)
	pool.append(entity)

func _cleanup_offscreen_entities() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.global_position.y > 1350:
			_recycle_entity(enemy, normal_pool)
			
	for ast in get_tree().get_nodes_in_group("asteroids"):
		if is_instance_valid(ast) and ast.global_position.y > 1350:
			_recycle_entity(ast, asteroid_pool)

# --- PHASE MANAGEMENT SYSTEM ---
func start_phase(new_phase: GameManager.Phase) -> void:
	GameManager.current_phase = new_phase
	
	match new_phase:
		GameManager.Phase.NORMAL_ENEMIES:
			show_alert("LET'S GO!")
			start_spawner(1.5 / (GameManager.difficulty_multiplier * GameManager.spawn_rate_multiplier), 30.0)
			
		GameManager.Phase.ASTEROID_ATTACK:
			show_alert("ASTEROID'S ATTACK!")
			start_spawner(0.6 / (GameManager.difficulty_multiplier * GameManager.spawn_rate_multiplier), 20.0)
			
		GameManager.Phase.ZIGZAG_ENEMIES:
			show_alert("ALERT: ZIG-ZAG SQUAD!")
			start_spawner(1.8 / (GameManager.difficulty_multiplier * GameManager.spawn_rate_multiplier), 35.0)
			
		GameManager.Phase.BOSS_BATTLE:
			show_alert("PREPARE FOR BATTLE!")
			phase_timer.stop()
			spawn_boss()
			start_spawner(4.0 / GameManager.difficulty_multiplier, 0.0)

func start_spawner(spawn_interval: float, phase_duration: float) -> void:
	spawn_timer.wait_time = max(0.1, spawn_interval)
	spawn_timer.start()
	
	if phase_duration > 0.0:
		phase_timer.wait_time = phase_duration
		phase_timer.start()

func _on_spawn_timer_timeout() -> void:
	match GameManager.current_phase:
		GameManager.Phase.NORMAL_ENEMIES:
			spawn_normal(Vector2(randf_range(160.0, 560.0), -60.0))
		GameManager.Phase.ASTEROID_ATTACK:
			spawn_asteroid_entity(Vector2(randf_range(160.0, 560.0), -60.0))
		GameManager.Phase.ZIGZAG_ENEMIES:
			spawn_zigzag(Vector2(randf_range(160.0, 560.0), -60.0))
		GameManager.Phase.BOSS_BATTLE:
			var spawn_x = randf_range(180.0, 540.0)
			var spawn_y = 280.0
			if is_instance_valid(active_boss_instance):
				spawn_y = active_boss_instance.global_position.y + 120.0
				spawn_x = clamp(active_boss_instance.global_position.x + randf_range(-140.0, 140.0), 160.0, 560.0)
			if randf() < 0.5:
				spawn_normal(Vector2(spawn_x, spawn_y), true)
			else:
				spawn_zigzag(Vector2(spawn_x, spawn_y), true)

func spawn_normal(pos: Vector2, is_under_boss: bool = false) -> void:
	var obj = _get_pooled_instance(enemy_normal_scene, normal_pool)
	if not obj: return
	obj.global_position = pos
	if is_under_boss and is_instance_valid(active_boss_instance):
		move_child(obj, active_boss_instance.get_index())
		obj.z_index = active_boss_instance.z_index - 1
	if GameManager.normal_ship_textures.size() > 0 and obj.has_method("set_enemy_texture"):
		obj.set_enemy_texture(GameManager.normal_ship_textures.pick_random())

func spawn_asteroid_entity(pos: Vector2) -> void:
	var obj = _get_pooled_instance(asteroid_scene, asteroid_pool)
	if not obj: return
	obj.global_position = pos
	if GameManager.asteroid_textures.size() > 0 and obj.has_method("set_asteroid_texture"):
		obj.set_asteroid_texture(GameManager.asteroid_textures.pick_random())

func spawn_zigzag(pos: Vector2, is_under_boss: bool = false) -> void:
	var obj = _get_pooled_instance(enemy_zigzag_scene, zigzag_pool)
	if not obj: return
	obj.global_position = pos
	if is_under_boss and is_instance_valid(active_boss_instance):
		move_child(obj, active_boss_instance.get_index())
		obj.z_index = active_boss_instance.z_index - 1
	if GameManager.zigzag_ship_textures.size() > 0 and obj.has_method("set_enemy_texture"):
		obj.set_enemy_texture(GameManager.zigzag_ship_textures.pick_random())

func spawn_boss() -> void:
	if not boss_scene: return
	var boss = boss_scene.instantiate()
	boss.global_position = Vector2(360, -120)
	boss.z_index = 10
	var lvl = GameManager.current_level
	var chosen_path = GameManager.boss_ship_textures[clamp(lvl - 1, 0, GameManager.boss_ship_textures.size() - 1)]
	if boss.has_method("setup_boss_texture"):
		boss.setup_boss_texture(chosen_path, lvl)
	if boss.has_signal("boss_defeated"):
		boss.boss_defeated.connect(_on_boss_defeated)
	add_child(boss)
	active_boss_instance = boss

func _on_phase_timer_timeout() -> void:
	match GameManager.current_phase:
		GameManager.Phase.NORMAL_ENEMIES: start_phase(GameManager.Phase.ASTEROID_ATTACK)
		GameManager.Phase.ASTEROID_ATTACK: start_phase(GameManager.Phase.ZIGZAG_ENEMIES)
		GameManager.Phase.ZIGZAG_ENEMIES: start_phase(GameManager.Phase.BOSS_BATTLE)

func _on_boss_defeated() -> void:
	active_boss_instance = null
	show_alert("BOSS DEFEATED! ADVANCING TO LEVEL " + str(GameManager.current_level + 1))
	GameManager.advance_level()
	start_phase(GameManager.Phase.NORMAL_ENEMIES)

func show_alert(text: String) -> void:
	if alert_label:
		alert_label.text = text
		alert_label.visible = true
	alert_timer.wait_time = 3.5
	alert_timer.start()

func _on_alert_timer_timeout() -> void:
	if alert_label: alert_label.visible = false
	alert_timer.stop()

func _on_window_focus_lost() -> void:
	AudioServer.set_bus_mute(0, true)
	get_tree().paused = true

func _on_window_focus_gained() -> void:
	AudioServer.set_bus_mute(0, false)
	if get_tree().paused and game_over_ui and not game_over_ui.visible:
		get_tree().paused = false

# --- COIN CONVERSION HELPER ---
func _commit_match_coins_to_total() -> void:
	# Adds coins collected during the current match into the Shop Total Bank
	if "current_coins" in GameManager and GameManager.current_coins > 0:
		if "total_coins" in GameManager:
			GameManager.total_coins += GameManager.current_coins
		elif "coins" in GameManager:
			GameManager.coins += GameManager.current_coins
		
		# Reset current match coins after transfer
		GameManager.current_coins = 0
		
	if GameManager.has_method("save_game_data"):
		GameManager.save_game_data()

# --- GAME OVER & PAUSE UI HANDLING ---
func setup_game_over_ui() -> void:
	if game_over_scene:
		game_over_ui = game_over_scene.instantiate()
		game_over_ui.process_mode = Node.PROCESS_MODE_ALWAYS
		$UI.add_child(game_over_ui)
		
		if game_over_ui.has_signal("restart_pressed"):
			game_over_ui.restart_pressed.connect(_on_restart_pressed)
		if game_over_ui.has_signal("setting_pressed"):
			game_over_ui.setting_pressed.connect(_on_setting_pressed)
		if game_over_ui.has_signal("shop_pressed"):
			game_over_ui.shop_pressed.connect(_on_shop_pressed)
		if game_over_ui.has_signal("resume_pressed"):
			game_over_ui.resume_pressed.connect(_on_resume_pressed)

func _on_pause_button_pressed() -> void:
	if get_tree().paused: return
	get_tree().paused = true
	if game_over_ui:
		game_over_ui.process_mode = Node.PROCESS_MODE_ALWAYS
		var current_match_coins = GameManager.current_coins if "current_coins" in GameManager else 0
		game_over_ui.setup_panel(true, current_match_coins)

func _on_player_died() -> void:
	await get_tree().create_timer(0.6).timeout
	
	# Credit match coins to the shop wallet upon death
	var match_coins_earned = GameManager.current_coins if "current_coins" in GameManager else 0
	_commit_match_coins_to_total()
	
	get_tree().paused = true
	if game_over_ui:
		game_over_ui.process_mode = Node.PROCESS_MODE_ALWAYS
		game_over_ui.setup_panel(false, match_coins_earned)

func _on_resume_pressed() -> void:
	if game_over_ui:
		game_over_ui.visible = false
	get_tree().paused = false

# --- 🔄 RETRY / RESTART / TRANSITION HANDLERS ---
func _on_restart_pressed() -> void:
	_commit_match_coins_to_total()
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_home_pressed() -> void:
	_commit_match_coins_to_total()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_setting_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/settings.tscn")

func _on_shop_pressed() -> void:
	_commit_match_coins_to_total()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/shop.tscn")

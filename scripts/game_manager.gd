extends Node

# ==========================================
# ⚙️ SIGNALS & EVENT BUS
# ==========================================
signal level_changed(new_level: int, loop: int)
signal phase_changed(new_phase: Phase)
signal boss_wave_triggered(level: int)
signal game_reset
signal score_updated(new_score: int)
signal coins_updated(new_coins: int)
signal slow_motion_state_changed(is_active: bool)
signal powerup_level_updated(powerup_name: String, level: int)
signal missed_enemies_updated(count: int)

# ==========================================
# 📊 ENUMS & GAME PHASES
# ==========================================
enum Phase { NORMAL_ENEMIES, ASTEROID_ATTACK, ZIGZAG_ENEMIES, BOSS_BATTLE }

var current_phase: Phase = Phase.NORMAL_ENEMIES:
	set(value):
		if current_phase != value:
			current_phase = value
			phase_time = 0.0
			emit_signal("phase_changed", current_phase)

# ==========================================
# 💰 GAME STATS & ECONOMY
# ==========================================
var score: int = 0

# Coins collected only during the active match run
var current_coins: int = 0:
	set(value):
		current_coins = max(0, value)
		emit_signal("coins_updated", current_coins)

# Legacy alias for current session coins to maintain backward compatibility
var coins: int:
	get:
		return current_coins
	set(value):
		current_coins = value

# Total persistent wallet coins stored and used for shop purchases
var total_coins: int = 0

var kills: int = 0
var missed_enemies: int = 0
const MAX_MISSED_ALLOWED: int = 3
var high_score: int = 0

# ==========================================
# 💾 SESSION-ONLY SHOP DATA & UPGRADES
# ==========================================
var current_ship_index: int = 1
var laser_damage_level: int = 1:
	set(val):
		laser_damage_level = val
		level_laser_damage = val
var level_laser_damage: int = 1

var max_hp_level: int = 1

var level_speed_upgrade: int = 1:
	set(val):
		level_speed_upgrade = val
		speed_level = val
var speed_level: int = 1

var level_powerup_duration: int = 1
var selected_laser_texture: String = "res://asstes/Lasers/Lasers_1.png"
var unlocked_ships: Array = [1]

const MAX_UPGRADE_LEVEL: int = 10
const UPGRADE_BASE_COST: int = 20

# ==========================================
# ⏱️ LEVEL & TIME SYSTEM
# ==========================================
var current_level: int = 1
var max_levels: int = 11
var current_loop: int = 0

var base_level_duration: float = 90.0
var current_level_duration: float = 90.0
var level_timer: float = 0.0

var game_time: float = 0.0
var phase_time: float = 0.0
var is_boss_active: bool = false

# ==========================================
# 📈 HARDCORE DIFFICULTY MULTIPLIERS
# ==========================================
var difficulty_multiplier: float = 1.0
var enemy_speed_multiplier: float = 1.0
var enemy_hp_multiplier: float = 1.0
var spawn_rate_multiplier: float = 1.0
var boss_hp_multiplier: float = 1.0

# ==========================================
# ⏳ SLOW-MOTION SYSTEM
# ==========================================
var is_slow_motion_active: bool = false
var slow_motion_speed_factor: float = 0.5
var slow_motion_timer: float = 0.0

# ==========================================
# ⚡ POWERUP PROGRESSION TRACKER
# ==========================================
var powerup_levels: Dictionary = {
	"TRIPLE SHOT": 1,
	"PURPLE": 1,
	"SHIELD": 1,
	"RAPID FIRE": 1,
	"SLOW_MOTION": 1,
	"MAGNET": 1
}

# ==========================================
# 🎨 CACHE & ASSET PATHS
# ==========================================
var texture_cache: Dictionary = {}

var normal_ship_textures: Array[String] = [
	"res://asstes/Ships/fighter_red.png",
	"res://asstes/Ships/scout_blue.png",
	"res://asstes/Ships/vanguard_green.png",
	"res://asstes/Ships/interceptor_gold.png",
	"res://asstes/Ships/cruiser_purple.png"
]

var zigzag_ship_textures: Array[String] = [
	"res://asstes/Ships/drone_light.png",
	"res://asstes/Ships/striker_orange.png",
	"res://asstes/Ships/seeker_white.png",
	"res://asstes/Ships/guardian_heavy.png",
	"res://asstes/Ships/phantom_dark.png"
]

var asteroid_textures: Array[String] = [
	"res://asstes/Asteroid/Asteroid_1.png",
	"res://asstes/Asteroid/Asteroid_2.png",
	"res://asstes/Asteroid/Asteroid_3.png",
	"res://asstes/Asteroid/Asteroid_4.png",
	"res://asstes/Asteroid/Asteroid_5.png"
]

var boss_ship_textures: Array[String] = [
	"res://asstes/Ships/alpha_prime.png",
	"res://asstes/Ships/cruiser_purple.png",
	"res://asstes/Ships/drone_light.png",
	"res://asstes/Ships/fighter_red.png",
	"res://asstes/Ships/guardian_heavy.png",
	"res://asstes/Ships/interceptor_gold.png",
	"res://asstes/Ships/phantom_dark.png",
	"res://asstes/Ships/seeker_white.png",
	"res://asstes/Ships/striker_orange.png",
	"res://asstes/Ships/boss_mega.png"
]

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	reset_game()

func _process(delta: float) -> void:
	var unscaled_delta = delta / Engine.time_scale if Engine.time_scale > 0 else delta
	
	game_time += unscaled_delta
	phase_time += unscaled_delta
	
	if is_slow_motion_active:
		slow_motion_timer -= unscaled_delta
		if slow_motion_timer <= 0.0:
			deactivate_global_slow_motion()
	
	if not is_boss_active:
		level_timer += unscaled_delta
		if level_timer >= current_level_duration:
			trigger_boss_wave()

# ==========================================
# 🔄 GAME LOOP & PROGRESSION
# ==========================================
func reset_game() -> void:
	score = 0
	kills = 0
	missed_enemies = 0
	current_level = 1
	current_loop = 0
	game_time = 0.0
	phase_time = 0.0
	is_boss_active = false
	current_coins = 0 # Ensures current active run starts at zero coins
	deactivate_global_slow_motion()
	current_phase = Phase.NORMAL_ENEMIES
	
	emit_signal("missed_enemies_updated", missed_enemies)
	
	for key in powerup_levels.keys():
		powerup_levels[key] = 1
		
	calculate_level_parameters()
	emit_signal("game_reset")

func calculate_level_parameters() -> void:
	current_level_duration = base_level_duration + ((current_level - 1) * 30.0)
	
	var level_factor: float = float(current_level - 1)
	var loop_factor: float = float(current_loop)
	
	# Smooth, balanced progression curve capped for high-performance low-end hardware
	difficulty_multiplier = 1.0 + (level_factor * 0.25) + (loop_factor * 0.5)
	enemy_speed_multiplier = clamp(1.0 + (level_factor * 0.08) + (loop_factor * 0.2), 1.0, 1.8)
	enemy_hp_multiplier = 1.0 + (level_factor * 0.35) + (loop_factor * 0.8)
	spawn_rate_multiplier = clamp(1.0 + (level_factor * 0.15) + (loop_factor * 0.4), 1.0, 2.5)
	boss_hp_multiplier = 1.0 + (level_factor * 0.50) + (loop_factor * 1.2)
	
	level_timer = 0.0
	emit_signal("level_changed", current_level, current_loop)

func register_kill() -> void:
	kills += 1

func enemy_missed() -> void:
	missed_enemies += 1
	emit_signal("missed_enemies_updated", missed_enemies)

	if missed_enemies >= MAX_MISSED_ALLOWED:
		trigger_game_over("3 ENEMIES ESCAPED!")

func trigger_game_over(reason: String = "3 ENEMIES ESCAPED!") -> void:
	Engine.time_scale = 1.0
	commit_session_coins() # Automatically bank current session coins before opening game over screen
	
	var current_scene = get_tree().current_scene
	if current_scene:
		var ui_node = current_scene.find_child("GameOver", true, false)
		if not ui_node:
			if current_scene.has_node("UI/GameOver"):
				ui_node = current_scene.get_node("UI/GameOver")
		
		if ui_node and ui_node.has_method("setup_panel"):
			current_scene.get_tree().paused = true
			ui_node.process_mode = Node.PROCESS_MODE_ALWAYS
			ui_node.setup_panel(false, current_coins)
			return

	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

# ==========================================
# ⏱️ SLOW MOTION CONTROL
# ==========================================
func activate_global_slow_motion(duration: float = 7.0, speed_factor: float = 0.5) -> void:
	slow_motion_speed_factor = speed_factor
	slow_motion_timer = duration
	Engine.time_scale = speed_factor
	
	if not is_slow_motion_active:
		is_slow_motion_active = true
		emit_signal("slow_motion_state_changed", true)

func deactivate_global_slow_motion() -> void:
	is_slow_motion_active = false
	slow_motion_timer = 0.0
	Engine.time_scale = 1.0
	emit_signal("slow_motion_state_changed", false)

# ==========================================
# 🌟 POWERUP UPGRADES
# ==========================================
func _normalize_key(powerup_name: String) -> String:
	var key = powerup_name.to_upper().strip_edges()
	if key == "ENERGY" or key == "RAPID FIRE": return "RAPID FIRE"
	if key == "STAR" or key == "TRIPLE SHOT": return "TRIPLE SHOT"
	if key == "PURPLE CRYSTAL" or key == "PURPLE": return "PURPLE"
	if key == "SLOW MOTION" or key == "SLOW_MOTION": return "SLOW_MOTION"
	if key == "SHIELD": return "SHIELD"
	if key == "MAGNET": return "MAGNET"
	return key

func upgrade_powerup_level(powerup_name: String, max_level: int = 10) -> int:
	var key: String = _normalize_key(powerup_name)
	var current_lvl: int = powerup_levels.get(key, 1)
	
	if current_lvl < max_level:
		current_lvl += 1
		powerup_levels[key] = current_lvl
		emit_signal("powerup_level_updated", key, current_lvl)
	
	return current_lvl

func reset_powerup_level(powerup_name: String) -> void:
	var key: String = _normalize_key(powerup_name)
	powerup_levels[key] = 1
	emit_signal("powerup_level_updated", key, 1)

func get_powerup_level(powerup_name: String) -> int:
	var key: String = _normalize_key(powerup_name)
	return powerup_levels.get(key, 1)

func get_effective_enemy_speed_multiplier() -> float:
	return enemy_speed_multiplier

func trigger_boss_wave() -> void:
	if is_boss_active:
		return
		
	is_boss_active = true
	current_phase = Phase.BOSS_BATTLE
	emit_signal("boss_wave_triggered", current_level)

func advance_level() -> void:
	is_boss_active = false
	
	if current_level < max_levels:
		current_level += 1
		current_phase = Phase.NORMAL_ENEMIES
		calculate_level_parameters()
	else:
		advance_loop()

func advance_loop() -> void:
	current_loop += 1
	current_level = 1
	is_boss_active = false
	current_phase = Phase.NORMAL_ENEMIES
	calculate_level_parameters()

func add_score(amount: int) -> void:
	score += int(amount * difficulty_multiplier)
	if score > high_score:
		high_score = score
	emit_signal("score_updated", score)

# ==========================================
# 💰 ECONOMY & COIN MANAGEMENT
# ==========================================
func add_coins(amount: int) -> void:
	current_coins += amount

func get_coins() -> int:
	return current_coins

func get_total_coins() -> int:
	return total_coins

func commit_session_coins() -> void:
	total_coins += current_coins
	save_game_data()

func spend_coins(amount: int) -> bool:
	if total_coins >= amount:
		total_coins -= amount
		save_game_data()
		return true
	return false

func save_game_data() -> void:
	# Safe placeholder for persistence logic
	pass

# ==========================================
# 🖼️ RESOURCE CACHING
# ==========================================
func get_cached_texture(path: String) -> Texture2D:
	if texture_cache.has(path):
		return texture_cache[path]
		
	if ResourceLoader.exists(path):
		var tex = load(path) as Texture2D
		if tex:
			texture_cache[path] = tex
			return tex
			
	return null

func clear_texture_cache() -> void:
	texture_cache.clear()

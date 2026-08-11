extends Node

var audio_player: AudioStreamPlayer

func _ready() -> void:
	# This script will keep running in the background even when the scene changes
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = preload("res://asstes/Sounds/BG_Music.ogg")
	audio_player.bus = "Music" # To be controlled by the Settings Music slider
	
	add_child(audio_player)
	audio_player.play()

func _process(_delta: float) -> void:
	# Automatic restart when music finishes (Looping)
	if audio_player and not audio_player.playing:
		audio_player.play()
		
	# Auto-adjust volume based on current scene
	var current_scene = get_tree().current_scene
	if current_scene:
		var s_name = current_scene.name.to_lower()
		
		# If it's Menu, Shop, Settings or Game Over screen, Full/Loud sound
		if s_name in ["main_menu", "mainmenu", "shop", "settings", "game_over", "gameover"]:
			audio_player.volume_db = 0.0
		else:
			# Lower volume during Main Gameplay so shooting/explosion sounds are clear
			audio_player.volume_db = -12.0

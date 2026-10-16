extends Node
## Tira capturas de ecrã do menu e do jogo (precisa de ecrã, ex.: xvfb-run).
## godot --path godot res://tests/screenshots.tscn -- --out=/caminho/pasta

func _ready() -> void:
	var out := "user://screenshots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(2.5)
	await _shot(out + "/menu.png")

	main.start_game()
	main.hud._touch.visible = true          # mostrar os botões táteis mesmo sem ecrã tátil
	main.hud.btn_fire.pressed = true
	await _wait(1.2)
	main.hud.btn_left.pressed = true        # puxar o nariz para cima
	await _wait(0.35)
	main.hud.btn_left.pressed = false
	await _wait(2.0)
	await _shot(out + "/jogo.png")

	main.world.player_input.eject = true
	await _wait(1.4)
	await _shot(out + "/paraquedas.png")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("captura: ", path)

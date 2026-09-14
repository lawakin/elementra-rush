extends Node2D

signal confirm_pressed

var buttons: Control
var fight_button: TextureButton

var rng = RandomNumberGenerator.new()
var chance: float

var fight_qte_scene: PackedScene = preload("res://scenes/fight_qte.tscn")
var fight_qte

var item_qte_scene: PackedScene = preload("res://scenes/item_qte.tscn")
var item_qte

var atk_bonus: float = 1
var def_bonus: float = 0

var cycles_run_def: int = 0
var cycles_run_atk: int = 0

var atk_buff_active: bool = false
var def_buff_active: bool = false

var fight_dialogue_scene: PackedScene = preload("res://scenes/fight_dialogue.tscn")
var fight_dialogue = fight_dialogue_scene.instantiate()
var unknown_icon: String = "res://object_sprites/unknown_identity_icon.png"
var player_icon: String = "res://player_sprites/anemo_walking_spritesheet.png"

var current_action: int = 0

var current_turn: int = 0

var dragon_phase: int = 0
var dmg: float = 0.0

var attacking_animations: Array = [
	"attacking anemo",
	"attacking hydro",
	"attacking pyro",
	"attacking dendro"
]

var blocking_animations: Array = [
	"blocking anemo",
	"blocking hydro",
	"blocking pyro",
	"blocking dendro"
]

var player_block_animation: String
var player_attack_animation: String

func _ready() -> void:
	rng.randomize()
	buttons = $FightHUD/Buttons
	fight_button = $FightHUD/Buttons/FightButton
	player_block_animation = blocking_animations[Global.player_element]
	player_attack_animation = attacking_animations[Global.player_element]
	
	while Global.ending == 0:
		if current_turn == 0:
			await player_turn()
			if Global.ending == 1: break
			
		elif current_turn == 1:
			await dragon_attack()
			
			if chance > 2:
				await player_defense()
			
			print("Dragon DMG D20: ",chance)
			print("Dragon's DMG: ", chance*2.5,"\n")
			print("Player's Defense D20: ",Global.player_qte,"\n")
			print("Player's Defense Multiplier: ", (1 - ((Global.player_qte/10) + def_bonus)))
			print("Player's Reduced DMG: ", (chance * 2.5) * (1 - ((Global.player_qte/10) + def_bonus)))
			print("Dragon's Real Damage: ", chance,"\n")
			
			if $FightHUD/PlayerHP.value == 0:
				fight_dialogue.change_dialogue("...Seu HP ficou baixo demais... Você está perdendo forças...","???",unknown_icon)
				Global.ending = 2
				continue
			
			current_turn = 0
			current_action = 4
			$FightHUD/DamagePlayer.hide()
			
		await get_tree().process_frame
	
	fight_end()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("confirm"): confirm_pressed.emit()

func change_scene():
	get_tree().change_scene_to_file("res://scenes/aftermath.tscn")

func player_turn():
	match current_action:
		1:
			await player_attack()
			print("Player QTE: ",Global.player_qte)
			print("Player Damage: ",dmg,"\n")
			
			if $FightHUD/DragonHP.value == 0:
				await dragon_death()
				return
			
			current_turn = 1
			current_action = 0
		2:
			await player_item()
			current_turn = 1
			current_action = 0
		3:
			print("Player RunAway: ",chance)
			await player_runaway()
			
			if chance >= 17:
				Global.ending = 1
				return
			
			current_turn = 1
			current_action = 0
		4:
			await verify_current_effects()
			remove_child(fight_dialogue)
			$FightHUD.add_child(buttons)
			fight_button.grab_focus()
			current_action = 0

func player_attack():
	await fight_qte.player_attacked
	fight_qte.queue_free()
	add_child(fight_dialogue)
	fight_dialogue.change_dialogue("...", "???", unknown_icon)
	
	if Global.player_qte == 0:
		fight_dialogue.change_text("...Errou o ataque...")
	elif Global.player_qte < 3:
		fight_dialogue.change_text("...Desferiu um poderoso golpe na criatura!")
	elif Global.player_qte < 7:
		fight_dialogue.change_text("...Obteve uma extrema perfomance e precisão no ataque e atingiu a criatura em cheio!")
	else:
		fight_dialogue.change_text("...Um acerto CRÍTICO na criatura!")
	dmg = Global.player_qte * (3+atk_bonus)
	
	if Global.player_qte > 0:
		await $Enemy.taking_damage()
		await $FightHUD/DragonHP.drop_health(dmg)
		$FightHUD/DamageDragon.text = str(int(dmg))
		$FightHUD/DamageDragon.show()
		await $Enemy.reappearing_effect()
	
	await confirm_pressed
	$FightHUD/DamageDragon.hide()

func player_item():
	await item_qte.item_chose
	item_qte.queue_free()
	add_child(fight_dialogue)

	match Global.item_qte:
		"heal":
			fight_dialogue.change_text("...Conseguiu uma poção de cura e recuperou HP!")
			await $Potion.use_item(Global.item_qte)
			$Player.heal_effect()
			await $FightHUD/PlayerHP.gain_health(Global.item_value)
		"atk":
			fight_dialogue.change_text("...Conseguiu uma poção de aumento de dano por 3 turnos!")
			atk_bonus = Global.item_value
			atk_buff_active = true
			await $Potion.use_item(Global.item_qte)
			$Player.atk_effect()
			$ATKBuff.show()
			cycles_run_atk = 0
		"def":
			fight_dialogue.change_text("...Conseguiu uma poção de aumento de defesa por 3 turnos!")
			def_bonus = Global.item_value
			def_buff_active = true
			await $Potion.use_item(Global.item_qte)
			$Player.def_effect()
			$DEFBuff.show()
			cycles_run_def = 0
		"none":
			fight_dialogue.change_text("...Não encontrou itens no inventário...")
			
	await get_tree().create_timer(0.5).timeout
	await confirm_pressed

func player_runaway():
	running_buff()
	await confirm_pressed
	
	if chance >= 19:
		fight_dialogue.change_text("...Com um ótimo controle de seu corpo, obteve extremo sucesso na sua fuga.")
	elif chance == 18:
		fight_dialogue.change_text("...Você conseguiu fugir, covardemente.")
	elif chance == 17:
		fight_dialogue.change_text("...Por pouco, quase perdia um pé durante a fuga... Mas obteve sucesso, ou quase isso.")
	elif chance >= 10:
		fight_dialogue.change_text("...A tentativa falhou miseravelmente... Exatamente como um jantar de dragão, tentando fugir de seu destino.")
	elif chance > 2:
		fight_dialogue.change_text("...Você é impedido no meio de sua fútil tentativa e cai no chão.")
	else:
		fight_dialogue.change_text("...Terrivelmente, você tropeça na menor rocha possível, cai no chão e leva dano por isso... Não é seu dia de sorte.")
	
	await confirm_pressed
	print("Player Real RunAway: ",chance,"\n")
	
	if chance <= 2:
		$FightHUD/DamagePlayer.text = "5"
		await $FightHUD/PlayerHP.drop_health(5)
		$FightHUD/DamagePlayer.show()
		await $Player.reappearing_effect()
		await get_tree().create_timer(0.5).timeout
		$FightHUD/DamagePlayer.hide()

func player_defense():
	fight_dialogue.change_text("Prepare-se para se defender!")
	await confirm_pressed
	
	remove_child(fight_dialogue)
	await get_tree().process_frame
	
	qte_start()
	await fight_qte.qte_has_started
	$Enemy.move_forward(300,128)
	$Player.play(player_block_animation)
	await fight_qte.player_attacked
	
	fight_qte.queue_free()
	add_child(fight_dialogue)
	if Global.player_qte == 0:
		fight_dialogue.change_text("...Errou a defesa...")
	elif Global.player_qte < 3:
		fight_dialogue.change_text("...Foi capaz de bloquear uma parte razoável de dano!")
	elif Global.player_qte < 7:
		fight_dialogue.change_text("...Conseguiu uma excelente postura defensiva!")
	else:
		fight_dialogue.change_text("...Realizou uma defesa PERFEITA! Essa foi por pouco...")
	
	dmg = (chance * 2.5) * (1 - ((Global.player_qte/10) + def_bonus))
	
	if dmg < 0: dmg = 0
	if dragon_phase == 1: dmg *= 1.2
	
	if Global.player_qte > 0:
		await $Player.blocking_effect()
	else:
		await $Player.taking_damage()
	
	await $FightHUD/PlayerHP.drop_health(dmg)
	
	$FightHUD/DamagePlayer.text = str(int(dmg))
	$FightHUD/DamagePlayer.show()
	
	if dmg > 0:
		await $Player.reappearing_effect()
	
	await confirm_pressed

func dragon_attack():
	chance = rng.randi_range(1,20)
	fight_dialogue.change_text("O dragão furiosamente ataca!")
	await confirm_pressed
	if chance < 3:
		fight_dialogue.change_text("...O dragão errou o golpe!")
		dmg = 0
	elif chance < 9:
		fight_dialogue.change_text("...A criatura vai desferir um golpe certeiro!")
	elif chance < 14:
		fight_dialogue.change_text("...A besta realizará um excelente ataque!")
	elif chance < 19:
		fight_dialogue.change_text("...A criatura dracônica avança em uma ofensiva letal!")
	elif chance == 20:
		fight_dialogue.change_text("...O dragão lhe atingirá com um acerto PERFEITO!")
	await confirm_pressed

func running_buff():
	if $FightHUD/PlayerHP.value < 5:
		chance += 8
	elif $FightHUD/PlayerHP.value < 10:
		chance += 6
	elif $FightHUD/PlayerHP.value < 20:
		chance += 4
	elif $FightHUD/PlayerHP.value < 40:
		chance += 3
	elif $FightHUD/PlayerHP.value < 60:
		chance += 2
	elif $FightHUD/PlayerHP.value < 80:
		chance += 1
	if chance > 20: chance = 20

func verify_current_effects():
	if atk_buff_active:
		cycles_run_atk += 1
		if cycles_run_atk == 4:
			cycles_run_atk = 0
			atk_bonus = 1
			atk_buff_active = false
			$ATKBuff.hide()
			fight_dialogue.change_text("...Seu aumento de dano expirou!")
			await confirm_pressed
	
	if def_buff_active:
		cycles_run_def += 1
		if cycles_run_def == 4:
			cycles_run_def = 0
			def_bonus = 0
			def_buff_active = false
			$DEFBuff.hide()
			fight_dialogue.change_text("...Seu aumento de defesa expirou!")
			await confirm_pressed

func _on_fight_button_pressed() -> void:
	$FightHUD.remove_child(buttons)
	qte_start()
	await fight_qte.qte_has_started
	$Player.move_forward(360,186)
	$Player.play(player_attack_animation)
	current_action = 1

func qte_start():
	fight_qte = fight_qte_scene.instantiate()
	$FightHUD.add_child(fight_qte)

func _on_item_button_pressed() -> void:
	$FightHUD.remove_child(buttons)
	item_qte_start()
	current_action = 2

func item_qte_start():
	item_qte = item_qte_scene.instantiate()
	$FightHUD.add_child(item_qte)

func _on_run_button_pressed() -> void:
	$FightHUD.remove_child(buttons)
	add_child(fight_dialogue)
	fight_dialogue.change_text("...Você tentou achar uma brecha para fugir...")
	chance = rng.randi_range(1,20)
	chance = 1
	current_action = 3

func dragon_death():
	if dragon_phase == 0:
		dragon_phase = 1
		current_turn = 1
		await second_phase()
		
	elif dragon_phase == 1:
		Global.ending = 3
		fight_dialogue.change_dialogue("...O dragão mostrou-se muito fraco... Você venceu!","???",unknown_icon)

func second_phase():
	fight_dialogue.change_text("...O dragão caiu fraco no magma fervente... Porém voltou da morte?!")
	await confirm_pressed
	fight_dialogue.change_text("Ele parece irritado... A defesa e ataque do dragão subiram!")
	await confirm_pressed
	$FightHUD/DamagePlayer.modulate = Color.RED
	await $FightHUD/DragonHP.dragon_second_phase()
	
	var tween = create_tween()
	tween.tween_property($Enemy, "modulate", Color(1.0, 0.0, 0.0, 1.0), 0.0)
	tween.tween_interval(0.5)
	tween.tween_property($Enemy, "modulate", Color.WHITE, 0.0)
	await tween.finished

func fight_end():
	await confirm_pressed
	if TransitionScreen.transitioning: return
	TransitionScreen.transitioning = true
	TransitionScreen.transition()
	await TransitionScreen.on_transition_finished
	call_deferred("change_scene")

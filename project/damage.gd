class_name Damage
extends Object

const FLASH_COLOR := Color(2.4, 0.35, 0.35)
const FLASH_DURATION := 0.28


static func flash(sprite: SpriteBase3D) -> void:
	if sprite == null:
		return
	sprite.modulate = FLASH_COLOR
	var tween: Tween = sprite.create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, FLASH_DURATION)


static func play_sound(host: Node3D, stream: AudioStream) -> void:
	if host == null or stream == null:
		return
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.stream = stream
	player.autoplay = true
	host.add_child(player)
	player.finished.connect(player.queue_free)

tool
extends VBoxContainer

class_name WcfDock

signal reload_button_pressed
signal select_modules_root_pressed

# Shows which node the user has selected to analyze for modules.
onready var modules_root_label := find_node("ModulesRootLabel")
# Shows if there are any problems with the module root the user has selected.
onready var modules_root_status_label := find_node("ModulesRootStatus")

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func set_modules_root_name(root_name: String):
	modules_root_label.text = root_name

func set_modules_root_status(message: String, ok: bool):
	modules_root_status_label.text = message
	if ok:
		modules_root_status_label.add_color_override("font_color", Color.green)
	else:
		modules_root_status_label.add_color_override("font_color", Color.red)

func _on_ReloadPluginButton_pressed():
	emit_signal("reload_button_pressed")

func _on_SelectModulesRootTarget_pressed():
	emit_signal("select_modules_root_pressed")

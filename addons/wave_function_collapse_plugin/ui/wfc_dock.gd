tool
extends VBoxContainer

signal reload_button_pressed
signal select_modules_root_pressed

onready var modules_root_label := find_node("ModulesRootLabel")

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func set_modules_root(root: Node):
	modules_root_label.text = root.get_name()


func _on_ReloadPluginButton_pressed():
	emit_signal("reload_button_pressed")

func _on_SelectModulesRootTarget_pressed():
	emit_signal("select_modules_root_pressed")

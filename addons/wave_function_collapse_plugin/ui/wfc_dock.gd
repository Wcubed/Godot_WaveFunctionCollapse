tool
extends VBoxContainer

class_name WcfDock

signal reload_button_pressed
signal select_modules_source_pressed
signal extract_modules_pressed
signal select_modules_target_pressed

# Shows which node the user has selected to analyze for modules.
onready var modules_source_label := find_node("ModulesSourceLabel")
# Shows if there are any problems with the module root the user has selected.
onready var modules_source_status_label := find_node("ModulesSourceStatus")

# Shows which node the user has selected to put the found modules into.
onready var modules_target_label := find_node("ModulesTargetLabel")
# Shows if there are any problems with the module target the user has selected.
onready var modules_target_status_label := find_node("ModulesTargetStatus")

onready var extract_modules_button := find_node("ExtractModulesButton")

var modules_source_ok := false
var modules_target_ok := false


# Called when the node enters the scene tree for the first time.
func _ready():
	reset_source_and_target()


# Resets all the source and target fields to their defaults.
func reset_source_and_target():
	modules_source_label.text = ""
	modules_source_status_label.text = ""
	modules_target_label.text = ""
	modules_target_status_label.text = ""
	
	modules_source_ok = false
	modules_target_ok = false
	
	extract_modules_button.disabled = true


func set_modules_source_name(root_name: String):
	modules_source_label.text = root_name


func set_modules_source_status(message: String, ok: bool):
	modules_source_status_label.text = message
	modules_source_ok = ok
	if ok:
		modules_source_status_label.add_color_override("font_color", Color.green)
	else:
		modules_source_status_label.add_color_override("font_color", Color.red)
	
	# Can we enable the extract button?
	extract_modules_button.disabled = !(modules_source_ok && modules_target_ok)


func set_modules_target_name(target_name: String):
	modules_target_label.text = target_name


func set_modules_target_status(message: String, ok: bool):
	modules_target_status_label.text = message
	modules_target_ok = ok
	if ok:
		modules_target_status_label.add_color_override("font_color", Color.green)
	else:
		modules_target_status_label.add_color_override("font_color", Color.red)
	
	# Can we enable the extract button?
	extract_modules_button.disabled = !(modules_source_ok && modules_target_ok)


func _on_ReloadPluginButton_pressed():
	emit_signal("reload_button_pressed")

func _on_SelectModulesRootTarget_pressed():
	emit_signal("select_modules_source_pressed")

func _on_ExtractModulesButton_pressed():
	emit_signal("extract_modules_pressed")

func _on_SelectModulesTarget_pressed():
	emit_signal("select_modules_target_pressed")

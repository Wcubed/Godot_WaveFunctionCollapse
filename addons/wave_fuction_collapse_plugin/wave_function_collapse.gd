tool
extends EditorPlugin

var dock

func _enter_tree():
	# See if our dock is already there, that means this plugin was reloaded!
	var previous_dock = get_tree().get_root().find_node("WfcDock*", true, false)
	if previous_dock != null:
		print("Wave function collaps plugin reloaded.")
		# Hey look, our dock already exists, we got reloaded while we were active.
		remove_control_from_docks(previous_dock)
		previous_dock.free()
	else:
		print("Wave function collaps plugin loaded.")
	
	# Add our custom dock to the right-hand panel.
	dock = preload("./scenes/wfc_dock.tscn").instance()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Reload the plugin when the button is pressed.
	dock.find_node("ReloadPluginButton").connect("pressed", self, "_on_reload_button_pressed")


func _exit_tree():
	# Clean up the dock.
	remove_control_from_docks(dock)
	dock.free()

# Reloads this plugin.
func reload_plugin():
	# Enter tree can detect when we are doing a reload.
	# This fixes us trying to free the "dock" after the script got reloaded from disk,
	# because that resets all our variables which would therefore be null.
	_enter_tree()

func _on_reload_button_pressed():
	call_deferred("reload_plugin")

func _process(delta):
	print("Bla!")

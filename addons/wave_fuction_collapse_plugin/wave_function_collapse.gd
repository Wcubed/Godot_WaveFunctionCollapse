tool
extends EditorPlugin

const DOCK_NAME := "__RUNNING_WFC_DOCK"

var dock

func _enter_tree():
	# See if our dock is already there, that means this plugin was reloaded!
	var previous_dock = get_tree().get_root().find_node(DOCK_NAME + "*", true, false)
	if previous_dock != null:
		print("Wave function collaps plugin reloaded.")
		# Hey look, our dock already exists, we got reloaded while we were active.
		remove_control_from_docks(previous_dock)
		previous_dock.queue_free()
	else:
		print("Wave function collaps plugin loaded.")
	
	# Add our custom dock to the right-hand panel.
	dock = preload("./ui/wfc_dock.tscn").instance()
	# Set the name to something that can't be mistaken for something else.
	# If we used the default name, we could confuse our active dock and
	# the scene open in the editor.
	dock.name = DOCK_NAME
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Get the TabContainer of this panel.
	var tab_container = dock.get_parent()
	
	# Find the docks tab number, set the title, and focus on it.
	for i in range(0, tab_container.get_child_count()):
		if tab_container.get_children()[i] == dock:
			tab_container.set_tab_title(i, "WFC")
			tab_container.current_tab = i
			break
	
	# Reload the plugin when the button is pressed.
	dock.find_node("ReloadPluginButton").connect("pressed", self, "_on_reload_button_pressed")


func _exit_tree():
	# Clean up the dock.
	if dock == null:
		# We somehow lost our dock. Possibly due to a script update while we were running.
		# See if we can find it.
		var previous_dock = get_tree().get_root().find_node(DOCK_NAME + "*", true, false)
		if previous_dock != null:
			dock = previous_dock
		else:
			# Dock is not there. Nothing to do.
			return
	remove_control_from_docks(dock)
	dock.queue_free()

# Reloads this plugin.
func reload_plugin():
	# Enter tree can detect when we are doing a reload.
	# This fixes us trying to free the "dock" after the script got reloaded from disk,
	# because that resets all our variables which would therefore be null.
	_enter_tree()

func _on_reload_button_pressed():
	call_deferred("reload_plugin")

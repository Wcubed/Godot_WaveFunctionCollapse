tool
extends EditorPlugin

const DOCK_NAME := "__RUNNING_WFC_DOCK"

var dock

# Root node where we will place imported modules.
var modules_root : Node = null

func _enter_tree():
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
	dock.connect("reload_button_pressed", self, "_on_reload_button_pressed")
	
	# Connect the other events.
	dock.connect("select_modules_root_pressed", self, "_on_select_modules_root")


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
	var editor_interface := get_editor_interface()
	editor_interface.set_plugin_enabled("wave_function_collapse_plugin", false)
	editor_interface.set_plugin_enabled("wave_function_collapse_plugin", true)

func _on_reload_button_pressed():
	call_deferred("reload_plugin")

# Get's the current selected node, and sets it as the modules root.
func _on_select_modules_root():
	var selection := get_editor_interface().get_selection().get_selected_nodes()
	print(selection)
	
	if selection.size() != 0:
		# Use the first as the target.
		modules_root = selection[0]
		# Update the interface.
		dock.set_modules_root(modules_root)

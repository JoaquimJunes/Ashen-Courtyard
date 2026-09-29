extends VBoxContainer
## Scene-specific commands injected into a shared menu; no character manipulation.
const Style = preload("res://features/ui/ui_style.gd")
var lab: Node3D
var menu: CanvasLayer
var station: OptionButton
var falls: OptionButton
var mode_selector: OptionButton
var instructions: Label
var heights := [2.5,3.0,4.5,6.0,8.0,12.0,16.0]

func _ready() -> void:
	instructions = Style.paragraph(self,"Select a station or a focused test. Existing movement and saved controls apply.")
	station = OptionButton.new()
	for id in range(9): station.add_item("%02d  %s" % [id,LabStation.TITLES[id]],id)
	add_child(station)
	Style.button(self,"Go to station",run.bind(func(): lab.go_to_station(station.get_selected_id())))
	var ledges := HBoxContainer.new()
	add_child(ledges)
	Style.button(ledges,"Ledge tests",run.bind(func(): lab.start_ledge_test()))
	Style.button(ledges,"Corner tests",run.bind(func(): lab.start_ledge_corner_test()))
	Style.button(ledges,"Movement practice",func(): menu.navigate("Practice"))
	Style.button(self,"Item testing",func(): menu.navigate("Items"))
	add_child(Style.text("Fall testing",21))
	var fall_row := HBoxContainer.new()
	add_child(fall_row)
	falls = OptionButton.new()
	for height in heights: falls.add_item("%.1f m drop" % height)
	fall_row.add_child(falls)
	Style.button(fall_row,"Start fall test",run.bind(func(): lab.start_fall_test(heights[falls.selected])))
	Style.button(fall_row,"Drop + hit",run.bind(func(): lab.start_fall_test(heights[falls.selected],true)))
	var resets := HBoxContainer.new()
	add_child(resets)
	Style.button(resets,"Reset station",run.bind(lab.reset_station))
	Style.button(resets,"Reset entire lab",run.bind(lab.reset_all))
	Style.button(self,"Return to courtyard",lab.return_to_courtyard)

func run(command: Callable) -> void:
	command.call()
	menu.diagnostics.reset()
	menu.close_menu()

func open() -> void:
	station.select(lab.active_station)
	station.grab_focus()

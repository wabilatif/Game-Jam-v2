extends Control

signal restart_pressed
signal main_menu_pressed

const FADE_IN_DURATION := 1.5
const STAMP_RED := Color("8e1b17d9")
const STAMP_INK := Color("cfc8b8d9")

## Compte rendu par fin de partie : titre, constat, cause, tampon,
## note griffonnée par le patient, style de la note.
const REPORTS: Dictionary[String, Array] = {
	"caught_by_monster": ["DISPARU", "Le patient n'a jamais été retrouvé.", "inconnue", "DISPARU",
		"IL M'A TROUVÉ", "NoteLoud"],
	"player_died": ["DÉCÈS CONSTATÉ", "Le corps n'a pas été réclamé.", "non déterminée", "DÉCÉDÉ",
		"je n'ai pas eu le temps", "NoteQuiet"],
	"escaped": ["SORTI", "Le patient a quitté l'établissement.\nIl n'a rien emporté avec lui.", "sortie", "SORTIE AUTORISÉE",
		"[s]je suis libre[/s]\nqu'est-ce que j'ai laissé là-bas ?", "NoteQuiet"],
}
const UNKNOWN_REPORT: Array = ["DOSSIER CLOS", "Aucune observation.", "non renseignée", "CLASSÉ", "", "NoteQuiet"]

@onready var _title: Label = %Title
@onready var _statement: Label = %Statement
@onready var _cause_value: Label = %CauseValue
@onready var _stamp: PanelContainer = %Stamp
@onready var _stamp_label: Label = %StampLabel
@onready var _note: RichTextLabel = %Note
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	for button: Button in [_restart_button, _main_menu_button]:
		button.mouse_entered.connect(button.grab_focus)
	_restart_button.pressed.connect(restart_pressed.emit)
	_main_menu_button.pressed.connect(main_menu_pressed.emit)


func show_result(won: bool, reason: String) -> void:
	var report: Array = REPORTS["escaped"] if won else REPORTS.get(reason, UNKNOWN_REPORT)
	_title.text = report[0]
	_statement.text = report[1]
	_cause_value.text = report[2]
	_stamp_label.text = report[3]
	_stamp.modulate = STAMP_INK if won else STAMP_RED
	_note.text = report[4]
	_note.theme_type_variation = report[5]
	show()
	_note.write()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION)
	_restart_button.grab_focus()

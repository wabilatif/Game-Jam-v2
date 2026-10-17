
extends Node3D

# ============================================================
# LOST MEMORY - PERSONNE 7
# MAIN : ORCHESTRATION ET INTEGRATION DU JEU
# ============================================================

# Scenes des differents responsables.
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/Monster.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/PowerPickup.tscn")
const EXIT_SCENE: PackedScene = preload("res://scenes/ExitDoor.tscn")

# Identifiants officiels du contrat V3.
const POWER_IDS: Array[String] = [
    "shockwave",
    "spectral_vision",
    "speed_boost",
    "spectral_trap"
]

# References aux objets du monde.
@onready var hospital: Node3D = $Hospital

var player: CharacterBody3D
var monster: CharacterBody3D
var exit_door: Area3D

# Association entre chaque pouvoir et son pickup.
var pickups_by_power: Dictionary = {}


# ============================================================
# 1. INITIALISATION
# ============================================================

func _ready() -> void:
    if not _hospital_is_ready():
        push_warning(
            "Hospital n'est pas encore disponible ou complet."
        )
        return

    if not _spawn_world_objects():
        return

    _connect_signals()
    _initialize_world()

    GameManager.start_game()


func _hospital_is_ready() -> bool:
    if hospital == null:
        return false

    var required_methods: Array[String] = [
        "get_player_spawn_position",
        "get_monster_spawn_position",
        "get_power_spawn_points",
        "get_patrol_points",
        "get_exit_position"
    ]

    for method_name in required_methods:
        if not hospital.has_method(method_name):
            return false

    return true


# ============================================================
# 2. CREATION DU MONDE
# ============================================================

func _spawn_world_objects() -> bool:
    var points: Array[Vector3] = hospital.call(
        "get_power_spawn_points"
    )

    if points.size() < POWER_IDS.size():
        push_error("Hospital : quatre spawns de pouvoirs requis.")
        return false

    player = PLAYER_SCENE.instantiate() as CharacterBody3D
    monster = MONSTER_SCENE.instantiate() as CharacterBody3D
    exit_door = EXIT_SCENE.instantiate() as Area3D

    if player == null or monster == null or exit_door == null:
        push_error("Une scene principale est invalide.")
        return false

    # Groupes utilises par PowerManager.
    player.add_to_group("player")
    monster.add_to_group("monster")

    add_child(player)
    add_child(monster)

    player.global_position = hospital.call(
        "get_player_spawn_position"
    )

    monster.global_position = hospital.call(
        "get_monster_spawn_position"
    )

    # Creation des quatre pouvoirs.
    for i in range(POWER_IDS.size()):
        var pickup: Node3D = PICKUP_SCENE.instantiate() as Node3D

        if pickup == null:
            push_error("Impossible de creer un pickup.")
            return false

        var power_id: String = POWER_IDS[i]

        # Definir l'identifiant avant _ready du pickup.
        pickup.set("power_id", power_id)

        add_child(pickup)
        pickup.global_position = points[i]

        pickups_by_power[power_id] = pickup

    # Creation de la sortie.
    add_child(exit_door)

    exit_door.global_position = hospital.call(
        "get_exit_position"
    )

    return true


func _initialize_world() -> void:
    # Le monstre recoit le joueur comme cible.
    monster.call("set_target", player)

    # Les points de patrouille viennent de Hospital.
    monster.call(
        "start_patrol",
        hospital.call("get_patrol_points")
    )


# ============================================================
# 3. CONNEXIONS DES SIGNAUX
# ============================================================

func _connect_signals() -> void:
    # Joueur.
    _connect_once(
        player, "player_died", _on_player_died
    )

    _connect_once(
        player, "sacrifice_applied", _on_sacrifice_applied
    )

    # Monstre.
    _connect_once(
        monster, "monster_caught_player",
        _on_monster_caught_player
    )

    _connect_once(
        monster, "player_detected", _on_player_detected
    )

    _connect_once(
        monster, "player_lost", _on_player_lost
    )

    _connect_once(
        monster, "reveal_state_changed", _on_reveal_changed
    )

    # Pickups.
    for pickup in pickups_by_power.values():
        _connect_once(
            pickup, "power_discovered",
            _on_pickup_discovered
        )

    # Gestion des pouvoirs.
    _connect_once(
        PowerManager, "sacrifice_choice_requested",
        _on_sacrifice_choice_requested
    )

    _connect_once(
        PowerManager, "sacrifice_completed",
        _on_sacrifice_completed
    )

    _connect_once(
        PowerManager, "power_discovered",
        _on_power_discovered
    )

    _connect_once(
        PowerManager, "power_activated",
        _on_power_activated
    )

    _connect_once(
        PowerManager, "power_activation_failed",
        _on_power_activation_failed
    )

    # Sortie.
    _connect_once(
        exit_door, "player_reached_exit", _on_exit_reached
    )

    # Gestion de la partie.
    _connect_once(
        GameManager, "game_started", _on_game_started
    )

    _connect_once(
        GameManager, "game_over", _on_game_over
    )

    _connect_once(
        GameManager, "exit_opened", _on_exit_opened
    )

    # Interface.
    var ui := get_node_or_null("/root/UIManager")

    if ui != null:
        _connect_once(
            ui, "sacrifice_accepted", _on_sacrifice_accepted
        )

        _connect_once(
            ui, "sacrifice_rejected", _on_sacrifice_rejected
        )

        _connect_once(
            ui, "pause_requested", _on_pause_requested
        )

        _connect_once(
            ui, "restart_requested", _on_restart_requested
        )

        _connect_once(
            ui, "main_menu_requested", _on_main_menu_requested
        )


# Connecter un signal sans creer de doublons.
func _connect_once(
    source: Object,
    signal_name: StringName,
    callback: Callable
) -> void:
    if source == null:
        return

    if not source.has_signal(signal_name):
        push_warning(
            "Signal absent : " + str(signal_name)
        )
        return

    if not source.is_connected(signal_name, callback):
        source.connect(signal_name, callback)


# ============================================================
# 4. COMMUNICATION AVEC LES MANAGERS
# ============================================================

func _call_manager(
    manager_name: String,
    method_name: String,
    arguments: Array = []
) -> void:
    var manager := get_node_or_null(
        "/root/" + manager_name
    )

    if manager == null:
        return

    if manager.has_method(method_name):
        manager.callv(method_name, arguments)


func _set_gameplay_suspended(suspended: bool) -> void:
    if is_instance_valid(player):
        player.call(
            "set_controls_enabled", not suspended
        )

    if is_instance_valid(monster):
        monster.call(
            "set_menu_paused", suspended
        )


func _refresh_hud() -> void:
    _call_manager(
        "UIManager",
        "update_power_list",
        [PowerManager.get_unlocked_powers()]
    )

    if is_instance_valid(player):
        _call_manager(
            "UIManager",
            "update_sacrifice_list",
            [player.call("get_applied_sacrifices")]
        )


# ============================================================
# 5. EVENEMENTS DU JOUEUR
# ============================================================

func _on_player_died() -> void:
    GameManager.end_game(false, "player_died")


func _on_sacrifice_applied(sacrifice_id: String) -> void:
    match sacrifice_id:
        "hearing":
            _call_manager(
                "AudioManager",
                "set_hearing_effect",
                [true]
            )

        "vision":
            _call_manager(
                "EffectsManager",
                "set_vision_effect",
                [true]
            )

    _call_manager(
        "AudioManager",
        "play_sacrifice_effect",
        [sacrifice_id]
    )

    _refresh_hud()


# ============================================================
# 6. EVENEMENTS DU MONSTRE
# ============================================================

func _on_monster_caught_player() -> void:
    GameManager.end_game(false, "caught_by_monster")


func _on_player_detected() -> void:
    _call_manager(
        "AudioManager",
        "set_monster_audio_intensity",
        [1.0]
    )

    _call_manager(
        "AudioManager",
        "play_sfx",
        ["monster_detected"]
    )


func _on_player_lost() -> void:
    _call_manager(
        "AudioManager",
        "set_monster_audio_intensity",
        [0.0]
    )


func _on_reveal_changed(is_revealed: bool) -> void:
    _call_manager(
        "EffectsManager",
        "set_spectral_vision",
        [is_revealed]
    )


# ============================================================
# 7. DECOUVERTE ET SACRIFICES
# ============================================================

func _on_pickup_discovered(power_id: String) -> void:
    PowerManager.discover_power(power_id)


func _on_power_discovered(_power_id: String) -> void:
    _call_manager(
        "AudioManager",
        "play_sfx",
        ["power_found"]
    )


func _on_sacrifice_choice_requested(
    power_id: String,
    sacrifices: Array[String]
) -> void:
    var ui := get_node_or_null("/root/UIManager")

    if ui == null:
        push_warning("UIManager indisponible.")
        PowerManager.reject_sacrifice()
        return

    # Suspendre les controles et le monstre.
    _set_gameplay_suspended(true)

    _call_manager(
        "UIManager",
        "show_sacrifice_menu",
        [power_id, sacrifices]
    )


func _on_sacrifice_accepted(
    power_id: String,
    sacrifice_id: String
) -> void:
    PowerManager.accept_sacrifice(
        power_id, sacrifice_id
    )


func _on_sacrifice_rejected() -> void:
    PowerManager.reject_sacrifice()

    _call_manager(
        "UIManager",
        "hide_sacrifice_menu"
    )

    _set_gameplay_suspended(false)


func _on_sacrifice_completed(
    power_id: String,
    _sacrifice_id: String
) -> void:
    # UIManager gere deja le menu et les listes.
    # Main supprime uniquement le pickup du monde.
    if pickups_by_power.has(power_id):
        var pickup: Node = pickups_by_power[power_id]

        if is_instance_valid(pickup):
            pickup.queue_free()

        pickups_by_power.erase(power_id)

    _set_gameplay_suspended(false)


# ============================================================
# 8. ACTIVATION DES POUVOIRS
# ============================================================

func _on_power_activated(power_id: String) -> void:
    var position := Vector3.ZERO

    if is_instance_valid(player):
        position = player.global_position

        if player.has_method("get_aim_position"):
            position = player.call("get_aim_position")

    _call_manager(
        "AudioManager",
        "play_power_effect",
        [power_id, position]
    )


func _on_power_activation_failed(
    _power_id: String,
    reason: String
) -> void:
    _call_manager(
        "UIManager",
        "show_message",
        [reason, 2.5]
    )


# IMPORTANT :
# PowerManager connecte deja le signal monster_triggered
# de SpectralTrap et applique le ralentissement.
# Main ne doit PAS connecter une seconde fois ce signal.


# ============================================================
# 9. SORTIE ET VICTOIRE
# ============================================================

func _on_exit_reached() -> void:
    if GameManager.is_game_over():
        return

    if not GameManager.can_open_exit():
        _call_manager(
            "UIManager",
            "show_message",
            ["Il faut debloquer les quatre pouvoirs.", 3.0]
        )
        return

    GameManager.open_exit()
    GameManager.end_game(true, "escaped")


func _on_exit_opened() -> void:
    _call_manager(
        "AudioManager",
        "play_sfx",
        ["door_open"]
    )


# ============================================================
# 10. DEBUT ET FIN DE PARTIE
# ============================================================

func _on_game_started() -> void:
    _refresh_hud()


func _on_game_over(won: bool, reason: String) -> void:
    _set_gameplay_suspended(true)

    if won:
        _call_manager(
            "UIManager", "show_victory"
        )
    else:
        _call_manager(
            "UIManager", "show_game_over", [reason]
        )


# ============================================================
# 11. PAUSE ET REDEMARRAGE
# ============================================================

func _on_pause_requested() -> void:
    GameManager.toggle_pause()

    _call_manager(
        "UIManager",
        "set_pause_menu_visible",
        [get_tree().paused]
    )


func _on_restart_requested() -> void:
    GameManager.restart_game()


func _on_main_menu_requested() -> void:
    get_tree().paused = false

    var menu_path := "res://scenes/MainMenu.tscn"

    if ResourceLoader.exists(menu_path):
        get_tree().change_scene_to_file(menu_path)
    else:
        push_warning(
            "MainMenu.tscn n'est pas encore disponible."
        )

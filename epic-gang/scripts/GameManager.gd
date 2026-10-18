
extends Node

# ============================================================
# LOST MEMORY - PERSONNE 7
# GAMEMANAGER : GESTION GLOBALE DE LA PARTIE
# ============================================================

# Signaux publics du contrat V3.
signal game_started
signal game_over(won: bool, reason: String)
signal exit_opened
signal game_restarted
# Secrets a retrouver : la sortie ne s'ouvre qu'apres les avoir tous trouves.
signal secret_collected(found: int, total: int)
signal all_secrets_found


# ============================================================
# 1. ETAT INTERNE
# ============================================================

var _game_running: bool = false
var _game_over: bool = false
var _game_time: float = 0.0

var _exit_is_open: bool = false
var _restart_pending: bool = false

# Le total est fourni par Main a chaque chargement de la scene
# (set_secret_total) ; seul le nombre trouve est remis a zero.
var _secret_total: int = 0
var _secrets_found: int = 0


# ============================================================
# 2. INITIALISATION
# ============================================================

func _ready() -> void:
    # GameManager doit fonctionner meme pendant la pause.
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
    # Le chronometre avance seulement pendant le jeu.
    if not _game_running:
        return

    if _game_over or _restart_pending:
        return

    if get_tree().paused:
        return

    _game_time += delta


# ============================================================
# 3. DEMARRAGE
# ============================================================

func start_game() -> void:
    # Toujours repartir d'une session propre.
    get_tree().paused = false

    _game_running = false
    _game_over = false
    _game_time = 0.0

    _exit_is_open = false
    _restart_pending = false
    _secrets_found = 0

    # Les Autoloads persistent entre les scenes.
    _reset_persistent_systems()

    _game_running = true

    game_started.emit()


# ============================================================
# 4. FIN DE PARTIE
# ============================================================

func end_game(won: bool, reason: String = "") -> void:
    # Une partie deja terminee ne doit pas se terminer
    # une deuxieme fois.
    if not _game_running:
        return

    if _game_over or _restart_pending:
        return

    _game_over = true
    _game_running = false

    # Garantir que les menus de fin restent accessibles.
    get_tree().paused = false

    game_over.emit(won, reason)


func is_game_over() -> bool:
    return _game_over


## Quitter la session sans declencher d'ecran de victoire ou de defaite.
func stop_game() -> void:
    _game_running = false
    _game_over = false
    _game_time = 0.0
    _exit_is_open = false
    _restart_pending = false
    _secret_total = 0
    _secrets_found = 0
    get_tree().paused = false
    _reset_persistent_systems()


# ============================================================
# 5. CHRONOMETRE
# ============================================================

func get_game_time() -> float:
    return _game_time


# ============================================================
# 6. CONDITION DE VICTOIRE
# ============================================================

func can_open_exit() -> bool:
    if not _game_running or _game_over:
        return false

    # Les pouvoirs sont une aide (ils ne conditionnent plus la victoire) :
    # il faut avoir retrouve tous les secrets.
    return are_all_secrets_found()


# Nombre de secrets de la partie (appele par Main apres leur creation).
func set_secret_total(total: int) -> void:
    _secret_total = maxi(total, 0)
    _secrets_found = mini(_secrets_found, _secret_total)


# Un secret vient d'etre ramasse. Renvoie false si la partie n'est pas
# en cours ou si tous les secrets sont deja trouves.
func collect_secret() -> bool:
    if not _game_running or _game_over:
        return false

    if _secrets_found >= _secret_total:
        return false

    _secrets_found += 1
    secret_collected.emit(_secrets_found, _secret_total)

    if _secrets_found >= _secret_total:
        all_secrets_found.emit()

    return true


func get_secrets_found() -> int:
    return _secrets_found


func get_secret_total() -> int:
    return _secret_total


func get_secrets_remaining() -> int:
    return maxi(_secret_total - _secrets_found, 0)


func are_all_secrets_found() -> bool:
    return _secrets_found >= _secret_total


func open_exit() -> void:
    if _exit_is_open:
        return

    if not can_open_exit():
        return

    _exit_is_open = true

    exit_opened.emit()


# ============================================================
# 7. PAUSE
# ============================================================

func toggle_pause() -> void:
    if not _game_running or _game_over:
        return

    if _restart_pending:
        return

    get_tree().paused = not get_tree().paused


# ============================================================
# 8. REDEMARRAGE
# ============================================================

func restart_game() -> void:
    # Empêcher plusieurs rechargements simultanes.
    if _restart_pending:
        return

    _restart_pending = true

    # Sortir obligatoirement de la pause.
    get_tree().paused = false

    # Remettre les informations de partie a zero.
    _game_running = false
    _game_over = false
    _game_time = 0.0
    _exit_is_open = false
    _secrets_found = 0

    # Nettoyer les gestionnaires persistants.
    _reset_persistent_systems()

    # UIManager ecoute ce signal et reinitialise les menus.
    game_restarted.emit()

    # Recharger la scene apres les callbacks.
    _reload_scene.call_deferred()


# ============================================================
# 9. REINITIALISATION DES AUTOLOADS
# ============================================================

func _reset_persistent_systems() -> void:
    _reset_autoload(
        "PowerManager",
        "reset_powers"
    )

    _reset_autoload(
        "AudioManager",
        "reset_audio"
    )

    _reset_autoload(
        "EffectsManager",
        "reset_effects"
    )


func _reset_autoload(
    manager_name: String,
    method_name: String
) -> void:
    var manager := get_node_or_null(
        "/root/" + manager_name
    )

    # Certains gestionnaires ne sont pas encore livres.
    if manager == null:
        return

    if not manager.has_method(method_name):
        push_warning(
            "Methode manquante : " + method_name
        )
        return

    manager.call(method_name)


# ============================================================
# 10. RECHARGEMENT DE LA SCENE
# ============================================================

func _reload_scene() -> void:
    if get_tree().current_scene == null:
        push_error(
            "GameManager : aucune scene a recharger."
        )

        _restart_pending = false
        return

    var error: Error = get_tree().reload_current_scene()

    if error != OK:
        push_error(
            "GameManager : echec du rechargement."
        )

    _restart_pending = false

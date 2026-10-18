# LOST MEMORY

A 3D first-person horror game developed in Godot 4 during a 24-hour game jam by a team of 7 people.

The player is trapped in an abandoned hospital, hunted by a monster. To escape, they must find every **secret** hidden in the hospital (5 per game); the exit only works once all of them have been found. Along the way, the player can pick up four **powers** that help against the monster. Each power demands a permanent sacrifice. Powers are an aid, they are not required to win.

Powers and secrets are placed **randomly at every launch** (inside the rooms, never in furniture, never too close to the start or to the exit).

A **mini-map** (top-left) is revealed progressively as the player explores: walls hide what lies behind them, and the exit only shows up once it has been spotted. Press **M** to open the large map (the game keeps running). **Brightness** is adjustable (see Controls) and saved between games.

## Doors and noise

Some doorways (5 per game, drawn at random, never all of them) have a hinged door. **E** opens / closes it, and the noise depends on how you open it:


| Action                  | Sound      | Noise radius |
| ----------------------- | ---------- | ------------ |
| Open while**sprinting** | Loud slam  | 22 m         |
| Open while walking      | Slow creak | 7 m          |
| Close                   | Soft creak | 5 m          |

The monster opens doors by itself (a closed door never blocks it), and the player hears it through the 3D sound.

### Noise API for the monster (`NoiseManager` autoload)

`Monster.gd` listens to `NoiseManager` on every physics tick (`_listen_to_world_noises`): it only reacts to a fresh noise (< 0.5 s old), with the hearing of its difficulty, and goes to investigate it (or tracks it by sound while chasing). The monster starts at a random point of its patrol route (`Hospital.get_random_monster_spawn_position()`), far from the player. Under the hood, it asks what it hears **from where it stands**:

```gdscript
var heard: Dictionary = NoiseManager.get_noise_heard_at(global_position)
if not heard.is_empty():
    # heard.position  : where the noise was made (point to investigate)
    # heard.intensity : 0..1 (1 = right next to it)
    # heard.distance, heard.age, heard.source ("door_slam", "door_creak"...)
    pass
# consume_noise_heard_at(global_position) returns a noise only once.
```

Difficulty is tuned in one place: `NoiseManager.set_difficulty(NoiseManager.Difficulty.HARD)` (or `hearing_multiplier = 1.5`) extends how far the monster hears; base radii are the `RADIUS_*` constants. New noises: `NoiseManager.emit_noise(position, radius, &"source")`.

## Languages

The game is available in **French** (default) and **English**: the "Langue / Language" button in the main menu and the pause menu switches instantly, and the choice is saved. The French text is the translation key; to translate a new sentence, use `tr("texte français")` in code and add one line to `epic-gang/scripts/TranslationsEN.gd`.

## Powers


| Key | Power           | Effect                                                       | Cooldown |
| --- | --------------- | ------------------------------------------------------------ | -------- |
| 1   | Shockwave       | Stuns the monster for 3s (8m range)                          | 12s      |
| 2   | Spectral Vision | Reveals the monster for 5s                                   | 15s      |
| 3   | Speed Boost     | 1.5x movement speed for 5s                                   | 12s      |
| 4   | Spectral Trap   | Placed at the player's feet, slows the monster by 50% for 5s | 15s      |

## Sacrifices

Each power offers 5 sacrifices drawn at random among those still available (9 in total). A sacrifice can only be given once per game.


| Sacrifice | Permanent Effect                                          |
| --------- | --------------------------------------------------------- |
| Hearing   | Audio cues used to locate the monster are heavily muffled |
| Leg       | Movement speed reduced by 25%                             |
| Sight     | Impaired vision                                           |
| Stamina   | Sprint duration reduced by half                           |
| Arm       | Powers recharge 50% slower                                |
| Heart     | Stamina recovers twice as slowly                          |
| Reflexes  | Camera responds worse (lower mouse sensitivity)           |
| Light     | The flashlight is much weaker                             |
| Memory    | The mini-map is lost for good                             |

## Controls


| Action                    | Key                                                                                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Move                      | W A S D (Z Q S D on AZERTY keyboards)                                                                                                                               |
| Look                      | Mouse                                                                                                                                                               |
| Sprint                    | Shift                                                                                                                                                               |
| Powers                    | 1, 2, 3, 4 (top row)                                                                                                                                                |
| Map                       | M (large map; small map is always top-left)                                                                                                                         |
| Open / close a door, hide | E                                                                                                                                                                   |
| Fullscreen                | F11, Alt+Enter, or the "Fullscreen" button in the menus (not available when the game runs inside the Godot editor's embedded Game tab: launch it in its own window) |
| Brightness                | `+` / `-` in game, or the slider in the main menu and pause menu                                                                                                    |

## Installation

The project only requires **Git** and **Godot 4.7.2** (standard version, not the "mono" / .NET edition). The entire team must use the exact same version of Godot.

### Git

```sh
# Ubuntu / Debian
sudo apt install git
# Fedora
sudo dnf install git
# macOS
xcode-select --install
```

On Windows: install [Git for Windows](https://git-scm.com/download/win).

### Godot 4.7.2

**Linux (x86_64)**, without root privileges:

```sh
mkdir -p ~/.local/opt/godot ~/.local/bin && cd ~/.local/opt/godot
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip && rm Godot_v4.7.2-stable_linux.x86_64.zip
chmod +x Godot_v4.7.2-stable_linux.x86_64
ln -sf ~/.local/opt/godot/Godot_v4.7.2-stable_linux.x86_64 ~/.local/bin/godot
godot --version
```

The last command should display `4.7.2.stable.official`. If `godot` is not found, add `~/.local/bin` to your `PATH`.

**Windows and macOS**: download the corresponding archive from the [version 4.7.2 release page](https://github.com/godotengine/godot/releases/tag/4.7.2-stable), extract it, and launch the executable.

## Running the Project

```sh
git clone git@github.com:wabilatif/Game-Jam-v2.git
cd Game-Jam-v2
```

1. Open Godot.
2. Click **Import** and select `epic-gang/project.godot`.
3. Open the project, then run the game with **F5**.

## Structure

```
epic-gang/            Godot project (res://)
├── project.godot
├── scenes/           scenes (.tscn)
└── scripts/          GDScript scripts (.gd)
```

## Team


| Person | Role                                                  |
| ------ | ----------------------------------------------------- |
| 1      | FPS Player, movement, sprint, permanent sacrifices    |
| 2      | Level design, collisions, spawns, patrol points       |
| 3      | Monster AI, detection, chase, capture                 |
| 4      | PowerManager, sacrifices, pickups, and spectral trap  |
| 5      | HUD, sacrifice menu, pause, victory, and defeat       |
| 6      | Audio, deafness, impaired vision, and spectral vision |
| 7      | Main, GameManager, integration, exit, and restart     |

## Credits

- Adrien Grégoire
- Ilann Amimer
- Marc-Antoine Sadio THE ULTIMATE BOSS NO NEED TO BE FIRST TO PROVE SOMETHING YOU GET ME BROOO
- Abdoul Latif Wabi
- Donata Contant
- Mahammad Abdourahman Mohamed
- Deniz Demir

## Assets tiers

- Monstre : [Smily horror monster](https://sketchfab.com/3d-models/smily-horror-monster-3d3fc31eddaa409a8f2df564823154e1) par [Bento (gostbento)](https://sketchfab.com/gostbento), sous licence [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/). Animation de marche ajoutée dans le jeu.
- Secret : [Voodoo Doll](https://sketchfab.com/3d-models/voodoo-doll-e0245d6f01f141f9812582a9487c3062) par [Sophie](https://sketchfab.com/Sofi_EX) , sous licence  [CC Attribution](https://creativecommons.org/licenses/by/4.0/)
- Torch : [Torch](https://sketchfab.com/3d-models/torch-78a40e36444b4ae79814a9965cbd0c1b) par [Oliver D](https://sketchfab.com/OliverD) , sous licence [CC Attribution](https://creativecommons.org/licenses/by/4.0/)

## Sounds

- All the audio sounds are free and they come from [PixaBay](https://pixabay.com/sound-effects/search/item%20found/).

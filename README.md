# LOST MEMORY

A 3D first-person horror game developed in Godot 4 during a 24-hour game jam by a team of 7 people.

The player is trapped in an abandoned hospital, hunted by a monster. To escape, they must acquire four powers. Each power demands a permanent sacrifice: hearing, a leg, sight, or stamina. The exit only unlocks once all four powers are obtained.

## Powers

| Key | Power | Effect | Cooldown |
|---|---|---|---|
| 1 | Shockwave | Stuns the monster for 3s (8m range) | 12s |
| 2 | Spectral Vision | Reveals the monster for 5s | 15s |
| 3 | Speed Boost | 1.5x movement speed for 5s | 12s |
| 4 | Spectral Trap | Placed at the player's feet, slows the monster by 50% for 5s | 15s |

## Sacrifices

| Sacrifice | Permanent Effect |
|---|---|
| Hearing | Audio cues used to locate the monster are heavily muffled |
| Leg | Movement speed reduced by 25% |
| Sight | Impaired vision |
| Stamina | Sprint duration reduced by half |

## Controls

| Action | Key |
|---|---|
| Move | W A S D (Z Q S D on AZERTY keyboards) |
| Look | Mouse |
| Sprint | Shift |
| Powers | 1, 2, 3, 4 (top row) |

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

| Person | Role |
|---|---|
| 1 | FPS Player, movement, sprint, permanent sacrifices |
| 2 | Level design, collisions, spawns, patrol points |
| 3 | Monster AI, detection, chase, capture |
| 4 | PowerManager, sacrifices, pickups, and spectral trap |
| 5 | HUD, sacrifice menu, pause, victory, and defeat |
| 6 | Audio, deafness, impaired vision, and spectral vision |
| 7 | Main, GameManager, integration, exit, and restart |

## Credits

- Adrien Grégoire

- Ilann Amimer

- Marc-Antoine Sadio THE ULTIMATE BOSS NO NEED TO BE FIRST TO PROVE SOMETHING YOU GET ME BROOO

- Abdoul Latif Wabi

- Donata Contant

- Mahammad Abdourahman Mohamed

- Deniz Demir

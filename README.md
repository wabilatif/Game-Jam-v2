# LOST MEMORY

Jeu d'horreur 3D à la première personne réalisé sous Godot 4 en 24 h, lors d'une game jam, par une équipe de 7 personnes.

Le joueur est piégé dans un hôpital abandonné, poursuivi par un monstre. Pour s'échapper, il doit trouver quatre pouvoirs. Chaque pouvoir exige un sacrifice permanent : l'ouïe, une jambe, la vue ou l'endurance. La sortie ne s'ouvre qu'une fois les quatre pouvoirs débloqués.

## Pouvoirs

| Touche | Pouvoir | Effet | Recharge |
|---|---|---|---|
| 1 | Onde de choc | Étourdit le monstre 3 s (portée 8 m) | 12 s |
| 2 | Vision spectrale | Révèle le monstre 5 s | 15 s |
| 3 | Accélération | Vitesse x1.5 pendant 5 s | 12 s |
| 4 | Piège spectral | Posé aux pieds du joueur, ralentit le monstre de 50 % pendant 5 s | 15 s |

## Sacrifices

| Sacrifice | Effet permanent |
|---|---|
| Ouïe | Les sons permettant de localiser le monstre sont fortement atténués |
| Jambe | Vitesse réduite de 25 % |
| Vue | Vision altérée |
| Endurance | Durée du sprint divisée par deux |

## Contrôles

| Action | Touche |
|---|---|
| Se déplacer | W A S D (Z Q S D sur clavier AZERTY) |
| Regarder | Souris |
| Sprinter | Maj |
| Pouvoirs | 1, 2, 3, 4 (rangée du haut) |

## Installation

Le projet n'a besoin que de **Git** et de **Godot 4.7.2** (version standard, pas la version « mono » / .NET). Toute l'équipe doit utiliser exactement la même version de Godot.

### Git

```sh
# Ubuntu / Debian
sudo apt install git
# Fedora
sudo dnf install git
# macOS
xcode-select --install
```

Sous Windows : installer [Git for Windows](https://git-scm.com/download/win).

### Godot 4.7.2

**Linux (x86_64)**, sans droits administrateur :

```sh
mkdir -p ~/.local/opt/godot ~/.local/bin && cd ~/.local/opt/godot
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip && rm Godot_v4.7.2-stable_linux.x86_64.zip
chmod +x Godot_v4.7.2-stable_linux.x86_64
ln -sf ~/.local/opt/godot/Godot_v4.7.2-stable_linux.x86_64 ~/.local/bin/godot
godot --version
```

La dernière commande doit afficher `4.7.2.stable.official`. Si `godot` est introuvable, ajouter `~/.local/bin` au `PATH`.

**Windows et macOS** : télécharger l'archive correspondante sur la [page de la version 4.7.2](https://github.com/godotengine/godot/releases/tag/4.7.2-stable), l'extraire et lancer l'exécutable.

## Lancer le projet

```sh
git clone git@github.com:wabilatif/Game-Jam-v2.git
cd Game-Jam-v2
```

1. Ouvrir Godot.
2. Cliquer sur **Import** et sélectionner `epic-gang/project.godot`.
3. Ouvrir le projet, puis lancer le jeu avec **F5**.

## Structure

```
epic-gang/            projet Godot (res://)
├── project.godot
├── scenes/           scènes (.tscn)
└── scripts/          scripts GDScript (.gd)
```

## Équipe

| Personne | Rôle |
|---|---|
| 1 | Joueur FPS, déplacement, sprint, sacrifices permanents |
| 2 | Niveau, collisions, spawns, points de patrouille |
| 3 | IA du monstre, détection, poursuite, capture |
| 4 | PowerManager, sacrifices, pickups et piège spectral |
| 5 | HUD, menu de sacrifice, pause, victoire et défaite |
| 6 | Audio, surdité, vision altérée et vision spectrale |
| 7 | Main, GameManager, intégration, sortie et redémarrage |

## Crédits

- Adrien Grégoire
- Ilann Amimer
- Marc-Antoine Sadio LE BOSS ULTIME PAS LA PEINE D'ETRE PREMIER POUR PROUVER QUELQUE CHOSE T'AS CAPTEEEER
- Abdoul Latif Wabi
- Donata Contant
- Mahammad Abdourahman Mohamed
- Deniz Demir

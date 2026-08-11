# Space Shooter Project

Central repository for Space Shooter, an action 2D arcade space defense game, mechanics prototypes, and web builds.

---

## Active Game Directory

| Game Title | Engine / Target | Web Demo | Asset Downloads (Itch.io) | Source Repository |
| :--- | :--- | :--- | :--- | :--- |
| **Space Shooter** | Godot 4.x (Web / Desktop) | Pending Deployment | Pending Upload | [View Source Code](https://github.com/KernelVoltage/space_shooter) |
| **2D Starter Kit** | Godot 4.x (Template) | N/A | Pending Upload | In Progress |

---

## Game Overview & Features

Space Shooter is built using Godot Engine 4.x, featuring smooth UI transitions, responsive controls, an upgrade system, and 11 distinct levels with changing environmental conditions.

### User Interface & Scenes

- **Main Menu:** Home hub with Play, Setting, and Shop buttons, integrated with black screen fade transition overlays.
- **Shop System:** In-game shop allowing players to spend collected coins on Laser Damage, Thruster Speed, and Max Health upgrades.
- **Settings Screen:** Dedicated options menu with audio sliders for Background Music (BGM) and Sound Effects (SFX).
- **Pause Menu:** Mid-game pause overlay tracking current coins, score, and offering instant resume or menu navigation options.

### Gameplay Mechanics & Controls

- **Movement Controls:** Supports Touch/Drag input for mobile/web touch interfaces, Mouse drag tracking, and Keyboard Arrow Keys (Up, Down, Left, Right). WASD movement is disabled.
- **Auto-Firing Lasers:** Main cannon continuously auto-fires project beams to maintain smooth combat flow.
- **Enemy Classes:**
  - Standard Vanguard Fighters: Move in straight downward lines.
  - Heavy Asteroids: Massive rotating space hazards requiring high firepower to shatter.
  - Zigzag Raiders: Aggressive tracking units that follow player position in horizontal zigzag patterns.
  - Mega Bosses: Large boss units with high health pools and complex attack patterns appearing at key levels.
- **Power-Up System:** Dynamic collectible drops including Magnet, Energy Shield, Rapid Fire, Star Triple-Shot, Purple Crystal, Quantum Clock, and Nano Repair.

---

## Architecture & Development Standards

Projects hosted inside this directory adhere to strict software development standards:

- **Godot 4.x GDScript Focus:** Clean node structure, signal-driven communications, and decoupled script logic.
- **Web Platform Compliance:** Zero external link calls, strict WebAudio driver usage, and standard cursor handling.
- **Procedural Asset Pipeline:** Dynamic color modulation, runtime scaling, and behavior math to keep HTML5 export sizes small.
- **Memory Garbage Collection:** Explicit signal cleanup on tree exit and automated boundary destruction for off-screen projectiles.

---

## Target Distribution Channels

- **Web HTML5 Platforms:** Optimized for web distribution on browser portals.
- **Asset Packages:** Sprites, Godot project templates, and UI layouts distributed via Itch.io.
- **Open Source Repositories:** Full project codebases hosted on GitHub for public inspection and learning.

---

## Request Custom Game Components

If you need a specific Godot script, 2D player controller, UI menu template, or game mechanics prototype, submit a request through the main hub.

1. Open a request ticket on the central repository.
2. Detail your target Godot version and requested mechanics.
3. The component will be built and released inside this repository.

- **Request a Game Component:** [Open a Request Ticket](https://github.com/KernelVoltage/KernelVoltage/issues/new)

---

## Local Project Setup

1. Clone the desired game repository:
   git clone https://github.com/KernelVoltage/space_shooter.git

2. Open Godot Engine 4.x and import the cloned folder.
3. Select the main scene and run the project.

---

## Network Navigation & Cross-Links

- **Central Request Hub:** [KernelVoltage Main Repository](https://github.com/KernelVoltage/KernelVoltage)
- **Web Applications Hub:** [Web Projects Repository](https://github.com/KernelVoltage/web-projects)
- **Space Shooter Game:** [Space Shooter Repository](https://github.com/KernelVoltage/space_shooter)
- **Public Codebase Directory:** [Browse All Repositories](https://github.com/KernelVoltage?tab=repositories)

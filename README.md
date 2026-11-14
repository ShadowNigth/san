# CS2GO — Port a Godot 4 (GDScript)

Port nativo a **Godot 4.3+** (100% GDScript) basado en el código fuente, física, tablas de armas y assets de [`3kh0/cs2go`](https://github.com/3kh0/cs2go.git), enfocado en **Singleplayer / Práctica contra Bots** sobre **de_dust2**.

---

## Características incluidas

- **Simulación Source a 128 Hz (`project.godot` + `src/simulation/MovementMath.gd`)**
  - Aceleración en suelo (`5.5`), fricción (`5.2`), *air-strafing* (`air_accel = 12.0`, `air_wish_speed = 30u`), límite de velocidad al saltar (`1.1x`), gravedad Source (`800u`) y transición suave de altura de ojos (`64u` de pie ↔ `46u` agachado).
  - Pasos espaciales diferenciados por superficie (`sand` vs `concrete`).
- **37 Armas + Cuchillos + Balística (`src/simulation/{RecoilSystem,AccuracySystem,BallisticsSystem}.gd`)**
  - Catálogo completo IDs `0–36` desde `assets/data/weapon_stats.json` (rifles, francotiradores con zoom dual, subfusiles, escopetas con recarga por cartucho, ametralladoras, pistolas, silenciador desmontable en M4A1-S/USP-S y ráfaga en Glock/FAMAS).
  - Tablas deterministas Park–Miller de 64 disparos por arma y modo (`recoil.json`), recuperación de precisión y dispersión por movimiento/salto (`accuracy.json`).
  - Hitboxes por región (`head` 4x, `stomach` 1.25x, `chest`/`arm` 1x, `leg` 0.75x), reducción por Chaleco/Casco y penetración multicapa a través de madera, metal, cristal y hormigón (`dust2_physics_meta.json`, respetando capas `passbullets` y `playerclip`).
  - Combate cuerpo a cuerpo con bayoneta (`180` / `90` por la espalda, `65` / `40` frontal).
- **6 Granadas + C4 + Modos de Juego (`src/world/`, `autoload/MatchManager.gd`)**
  - HE, Flashbang (ceguera según distancia y ángulo de visión), Smoke (20s, bloquea la línea de visión de bots y apaga fuegos), Molotov / Incendiaria (solo detonan sobre pendientes `<= 30°`, daño cada `0.2s`) y Decoy.
  - Planta (`3.2s`), temporizador (`40s` con curva de pitidos y explosión) y desactivación (`10s` / `5s` con kit) dentro de los volúmenes convexos exactos de Bombsite A/B (`dust2_buy_zones.json`).
  - Modos **Competitivo 5v5** (24 rondas, cambio de bando en ronda 13, fuego amigo, economía completa), **Casual 10v10**, **Deathmatch** (arma bonus cada 30s + Healthshot cada 3 bajas) y **Práctica**.
- **IA Táctica de Bots (`src/actors/BotController.gd` + `src/simulation/NavGraph.gd`)**
  - Compra inteligente según dinero disponible, navegación A* sobre el grafo real de `dust2_nav.json` (3,600+ áreas y portales), rutas de ataque/defensa/retake en Dust II, detección de humos y 4 niveles de dificultad.
- **HUD, Radar, Menú de Compra y Configuración (`src/ui/`)**
  - Mira dinámica o estática configurable, visor de francotirador, radar rotatorio y mapa completo (`M` / `H`) usando `dust2_overview.json` y `dust2_radar.png`, *killfeed*, marcador (`Tab`) y menú de compra con iconos SVG.

---

## Estructura del proyecto

```text
├── project.godot                  # Configuración Godot 4.3+ (128 Hz physics, inputs)
├── autoload/
│   ├── GameData.gd                # Carga JSONs, armas, zonas, navgraph, modelos
│   ├── SettingsManager.gd         # Sensibilidad, FOV, mira, volúmenes, dificultad
│   ├── AudioManager.gd            # Pool 2D/3D OGG para armas, pasos, C4 y UI
│   └── MatchManager.gd            # Reglas Casual/Comp/DM/Práctica, C4, economía
├── src/
│   ├── simulation/                # Lógica pura independiente de escena
│   │   ├── MovementMath.gd
│   │   ├── RecoilSystem.gd
│   │   ├── AccuracySystem.gd
│   │   ├── BallisticsSystem.gd
│   │   ├── EconomySystem.gd
│   │   ├── TriggerVolumes.gd
│   │   ├── GrenadeMath.gd
│   │   └── NavGraph.gd
│   ├── world/
│   │   ├── Dust2World.gd          # Carga dust2.glb + colliders + cielo HDR + humo/fuego
│   │   └── GrenadeProjectile.gd   # Trayectoria y rebotes de granadas a 128 Hz
│   ├── actors/
│   │   ├── CombatantBase.gd       # Base compartida jugador/bot
│   │   ├── PlayerController.gd    # Cámara FPS, sway/kickback y viewmodels
│   │   └── BotController.gd       # Compra, A*, combate y objetivos C4
│   └── ui/
│       ├── MainMenu.gd
│       ├── MatchScene.gd
│       ├── GameHUD.gd
│       ├── CrosshairOverlay.gd
│       ├── RadarOverlay.gd
│       ├── BuyMenu.gd
│       ├── ScoreboardOverlay.gd
│       └── SettingsPanel.gd
├── scenes/
│   ├── MainMenu.tscn
│   └── Dust2Match.tscn
├── assets/                        # ~115 MB listos para Godot 4 (KTX2/WebP/OGG/WOFF2/SVG)
├── scripts/
│   └── import_cs2go_assets.mjs    # Importador local de armas, mapas y skins extra
└── tests/
    └── run_simulation_tests.gd    # Suite headless de simulación para Godot 4
```

---

## Cómo ejecutar en Godot

1. Abre **Godot 4.3 o superior** (Standard GDScript; no requiere .NET/C#).
2. Importa `project.godot` en el Project Manager y espera a que Godot importe las texturas KTX2/WebP y archivos `.glb`.
3. Pulsa **F5** para iniciar desde `res://scenes/MainMenu.tscn`.

### Ejecutar pruebas de simulación (headless)

```bash
godot --headless --path . -s tests/run_simulation_tests.gd
```

---

## Importar mapas, armas y skins adicionales

Para mantener el repositorio por debajo del límite de 128 MB, se incluyen `de_dust2`, las 8 armas insignia (`ak-47`, `m4a1_s`, `m4a4`, `awp`, `mp9`, `glock`, `usp-s`, `deagle`, con fallback automático por clase para el resto del arsenal), las 6 granadas, `c4`, `bayonet`, los agentes base (`ctm-sas`, `ground-rebel`) y todo el banco de audio `.ogg`.

Para importar localmente **todas** las 34 armas, cuchillos adicionales, mapas extra (`mirage`, `inferno`, `nuke`, `ancient`, `anubis`, `overpass`, `vertigo`, `train`), agentes y *music kits* desde `3kh0/cs2go`:

```bash
npm install --no-save @gltf-transform/core @gltf-transform/extensions @gltf-transform/functions meshoptimizer
node scripts/import_cs2go_assets.mjs --all
```

El script decodifica automáticamente `EXT_meshopt_compression` y `KHR_mesh_quantization` para garantizar compatibilidad nativa con Godot 4.

---

## Controles por defecto

| Acción | Tecla |
| --- | --- |
| Movimiento | `W` `A` `S` `D` |
| Caminar / Agacharse / Saltar | `Shift` / `Ctrl` / `Espacio` |
| Disparar / Secundario (Zoom, Silenciador, Ráfaga, Estocada) | `Click Izq` / `Click Der` |
| Recargar / Inspeccionar / Soltar arma | `R` / `F` / `G` |
| Plantar o Desactivar C4 | `E` |
| Armas / Cuchillo / Granadas / C4 / Anterior | `1` `2` `3` `4` `5` / `Q` |
| Healthshot (Deathmatch) | `X` |
| Menú de Compra / Marcador | `B` / `Tab` |
| Zoom Radar / Mapa Completo | `H` / `M` |
| Pausa / Configuración | `Esc` |

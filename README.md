# Radar ATC

**Minetest Mod** — Air surveillance, air traffic control and airport management for the [laptop](https://content.minetest.net/packages/mt-mods/laptop/) mod.

---

## Dependencies

| Mod | Role |
|-----|------|
| `laptop` | Provides the app interface and the laptop computer |
| `airutils` | Provides aircraft detectable by the radar |

---

## Installation

1. Place the `radar_atc/` folder in `<minetest>/mods/`
2. Enable the mod in the game settings
3. Craft the application from the laptop

---

## Overview

Radar ATC is an application that runs on the **laptop** (`laptop` mod). It allows an operator to:

- **Monitor air traffic** in real time on a radar display
- **Manage airports** (create airports, configure runways, define approach coordinates)
- **Process ATC requests** from pilots (landing, takeoff, flyover, approach)
- **Communicate by radio** with pilots
- **Remotely control** another airport via password or link antenna
- **Publish NOTAMs** (notices to airmen) per airport

---

## Application Tabs

### 🟢 Radar

Displays a real-time radar view centered on the computer's position (or the remotely controlled airport).

**Displayed elements:**
- Radar circle with distance rings
- Aircraft as blips with trails (position history)
- Altitude in meters and feet on hover
- Aircraft list with detailed info: owner, pilot, heading, speed, altitude, throttle, HP, fuel, range
- Linked airport indicator and active range

**Available ranges:** 500 m, 750 m, 1,000 m, 1,500 m, 2,000 m, 3,000 m, 5,000 m

> ⚠️ Ranges above **1,000 m** require an **ASR Transponder** placed within 75 blocks of the active airport. Without a transponder, only ranges ≤ 1,000 m are available in the menu.

---

### ✈️ Airports

Lists all registered airports and allows **taking control** of a remote airport.

**Information displayed per airport:**
- ICAO identifier, full name, position
- Runways: designation, length, width, approach coordinates per direction

**Taking control of a remote airport:**

A computer can control an airport other than its linked airport. Two methods:
1. **Remote password** — enter the defined password to switch airports (default: `"airport"`)
2. **Link antenna** — if an `ATC Link Antenna` is present within 75 blocks of the computer, the connection is authorized without a password

Once in remote control, the radar centers on the target airport and the transponder searched is the one for that airport.

**Independent runways:** list of runways without an associated ATC airport, visible to all pilots.

---

### 📡 ATC

Air traffic control interface for the active airport.

**Requests sub-tab:**
- List of pending pilot requests (landing, takeoff, flyover, approach)
- Each request shows: pilot, aircraft model, type, altitude (flyover), timestamp
- Actions: **Authorize** (with runway and optional instructions), **Hold**, **Refuse**
- Requests become "stale" after 90 seconds (grayed out) — the pilot can send a new one
- Pagination: 3 requests per page

**Radio sub-tab:**
- Free radio messages sent by pilots via `/atc <ID> msg <text>`
- Conversations grouped by pilot

**NOTAM sub-tab:**
- Notices to airmen published by the ATC operator
- Maximum 10 lines per airport
- Consultable by pilots via the `/notam ID` command

**Log sub-tab:**
- History of the last 10 ATC decisions (authorization/refusal)

---

### 🔒 Admin

Access protected by password (default: `admin`).

**Airport management:**
- Create an airport (ICAO identifier, name, position)
- Add/remove runways (automatic designation from coordinates, width, approach coordinates per direction)
- Delete an airport
- Pagination: 10 airports per page

**Password management** *(requires `atc` privilege)*:
- `🔑 Passwords` button visible only to players with the `atc` privilege
- Displays current passwords in plain text (admin and remote)
- Allows changing them — new passwords are **persistent** (survive restarts) and are never stored in plain text in the code!

---

## Nodes

### ASR Radar Antenna (`radar_atc:transponder`)

Realistic rotating radar tower (3D mesh) that extends radar range beyond 1,000 m.

- Must be placed within **75 blocks** of the airport it serves (within `airport_link_r` radius)
- Its presence is **stored** in the airport's data — the chunk does not need to be loaded for the radar to recognize its existence
- The antenna rotates automatically when a player is within 48 blocks (standby otherwise)

**Craft:**

```
[ Dish      ]  [ Magnetron ]  [ Dish      ]
[ Waveguide ]  [ Rotator   ]  [ Waveguide ]
[ Steel Blk ]  [ Com Mod.  ]  [ Steel Blk ]
```

---

### ATC Link Antenna (`radar_atc:link_antenna`)

Telecommunications tower (~6 blocks tall) that allows a radar computer to take control of **any airport without a password**.

- Must be placed within **75 blocks** of the radar computer
- No configuration required — its mere presence is sufficient
- Can be oriented according to the placement direction (`facedir`)

**Craft:**

```
[    empty   ]  [ Dish      ]  [    empty   ]
[ Waveguide  ]  [ Com Mod.  ]  [ Waveguide  ]
[ Steel Blk  ]  [ Magnetron ]  [ Steel Blk  ]
```

---

### Craft Components (non-placeable)

| Item | Craft | Usage |
|------|-------|-------|
| **Communication Module** | 2× gold + 2× mese + 2× copper + steel | Transponder + Antenna |
| **Reception Dish** | 4× steel + diamond | Transponder + Antenna |
| **Microwave Waveguide** ×2 | 4× copper + 2× gold | Transponder + Antenna |
| **Radar Magnetron** | 4× obsidian + 2× steel + mese (block) | Transponder + Antenna |
| **Azimuth Rotator Motor** | 4× steel + 4× copper + mese | Transponder only |

---

## Chat Commands

### `/atc <ID|airport> <action> [param]`

Pilot → control tower communication. **Requires being on board an aircraft** (except `airport`).

| Sub-command | Description |
|-------------|-------------|
| `airport` | Shows the nearest airport with distance and direction (N, NNE, NE…) |
| `<ID> landing` | Requests landing clearance |
| `<ID> takeoff` | Requests takeoff clearance |
| `<ID> flyover <alt_m>` | Requests flyover at the given altitude (in meters) |
| `<ID> approach` | Requests approach instructions |
| `<ID> msg <text>` | Free radio message to the tower |

**Anti-duplicate:** a pilot cannot resend the same request within 15 seconds.

**Examples:**
```
/atc airport
/atc LFPG landing
/atc LFPG flyover 500
/atc LFPG msg On short final runway 27
```

---

### `/notam <ID|nearest>`

Consults pilot notices for an airport.

```
/notam LFPG
/notam nearest
```

---

## `atc` Privilege

The `atc` privilege is intended for administrators and chief controllers.

**Grant:**
```
/grant <player> atc
```

**What this privilege allows:**
- View and modify admin and remote passwords from the interface (`🔑 Passwords` button in Admin)
- Changes are persistent (stored in mod storage)

**What this privilege does NOT allow:**
- Bypassing the admin password to unlock the Admin tab
- Taking control of an airport without a password or antenna

---

## ⚠️ Security — Default Passwords

Default passwords are intentionally simple for easy setup. **On a public or multi-player server, they must be changed immediately.**

| Role | Default | Change via |
|------|---------|------------|
| Admin tab access | `admin` | `atc` priv → 🔑 button in Admin |
| Remote airport control | `airport` | `atc` priv → 🔑 button in Admin |

New passwords are **persistent** — they survive server restarts and are never written in plain text in the code.

It is also possible to completely disable the remote password requirement by deploying an **ATC Link Antenna** near each authorized control station.

---

## Configuration (`minetest.conf`)

All parameters can be defined in `minetest.conf` with the prefix `radar_atc.`:

```ini
# Radar refresh interval (seconds, default: 3)
radar_atc.timer_interval = 3

# Default radar range at startup (meters, default: 1000)
radar_atc.default_radius = 1000

# Radar trail length (stored positions, default: 5)
radar_atc.trail_len = 5

# Automatic computer → airport link distance (meters, default: 500)
radar_atc.airport_link_r = 500

# Enable the transponder system (true/false, default: true)
radar_atc.transponder_enabled = true

# Maximum range without transponder (meters, default: 1000)
radar_atc.transponder_free_radius = 1000

# Transponder / antenna detection distance around the airport (blocks, default: 75)
radar_atc.transponder_link_r = 75

# ASR antenna rotation speed (rad/s, default: 0.55)
radar_atc.transponder_rotation_speed = 0.55

# Duration before an ATC request becomes "stale" (seconds, default: 90)
radar_atc.req_stale_age = 90

# /atc command anti-duplicate (seconds, default: 15)
radar_atc.req_cmd_cooldown = 15

# Maximum number of NOTAM lines per airport (default: 10)
radar_atc.notam_max_lines = 10

# Number of decisions kept in the ATC log (default: 10)
radar_atc.atc_log_max = 10
```

---

## Typical Workflow

### Setting Up an Airport

1. Place a **laptop** near the airport (within 500 m of the center)
2. Open the Radar ATC app → **Admin** tab → password `admin`
3. Create an airport: ICAO identifier (e.g. `LFPG`), name, center position
4. Add runways with their coordinates and designations
5. Place an **ASR Transponder** within 75 blocks of the center to unlock ranges > 1,000 m

### Controlling a Remote Airport

**Option A — Password:**
1. Airports tab → select the target airport
2. Click `⊕ Take control`
3. Enter the remote password (default: `airport`)

**Option B — Link Antenna:**
1. Place an **ATC Link Antenna** within 75 blocks of the computer
2. The interface directly shows `📡 Link antenna [ID] Name` and a direct connect button

### Pilot Workflow

1. `/atc airport` — find the identifier and direction of the nearest airport
2. `/atc LFPG landing` — send a landing request
3. Wait for the ATC response (in-game, via chat or radio)
4. `/atc LFPG msg <text>` — communicate freely with the tower

---

## Technical Architecture

```
radar_atc/
├── init.lua          — Entry point, laptop app registration, atc privilege
├── config.lua        — Global parameters (CFG), reading from minetest.conf
├── storage.lua       — Persistence: airports, ATC state, passwords, NOTAMs, logs
├── utils.lua         — Utility functions (distances, runway names, UI helpers)
├── scan.lua          — Aircraft detection within radar range
├── transponder.lua   — ASR node + link antenna, has_transponder flag per airport
├── ui_tabs.lua       — Formspec construction (4 tabs)
├── fields.lua        — User interaction handling (all fields)
├── commands.lua      — Chat commands /atc and /notam
├── models/           — 3D OBJ meshes (ASR antenna, base, link tower)
└── textures/         — PNG textures (icons, palettes, craft items)
```

**Storage (mod_storage):**
- `airports_v5` — airport list (id, name, pos, runways, has_transponder)
- `atc_<ID>` — ATC state per airport (requests, radio conversations)
- `atclog_<ID>` — decision log per airport
- `notam_<ID>` — NOTAMs per airport
- `indep_strips_v1` — independent runways
- `passwords_v1` — persistent passwords

---

## License

| Content | License |
|---------|---------|
| Source code (`.lua`) | [MIT](https://opensource.org/licenses/MIT) |
| 3D models and textures | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) |

Author: **Luffy0805**

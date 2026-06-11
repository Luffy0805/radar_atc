# Radar ATC

**Minetest mod** — Air traffic surveillance, airport management and ATC communication for the [laptop](https://content.minetest.net/packages/mt-mods/laptop/) mod.

---

## Dependencies

| Mod | Role |
|-----|------|
| `laptop` | Provides the app framework and the laptop node |
| `airutils` | Provides detectable aircraft |

---

## Overview

Radar ATC runs as an application on the **laptop** mod. It allows an operator to:

- **Monitor air traffic** in real time (aircraft only — cars are not shown on radar)
- **Manage airports** (create airports, configure runways, set approach coordinates)
- **Handle ATC requests** from pilots (landing, takeoff, flyover, approach)
- **Communicate by radio** with pilots
- **Remote-control** another airport via password or link antenna
- **Publish NOTAMs** per airport

> ⚠️ Ghost aircraft (no pilot, owner offline) are automatically filtered from the radar.

---

## Tabs

### 🟢 Radar

Real-time radar view centred on the computer (or the remotely controlled airport).

- Aircraft blips with position trail
- Altitude in metres and feet on click
- Full aircraft details: owner, pilot, heading, speed, altitude, throttle, HP, fuel, range, distance
- `UPD: HH:MM:SS` refresh indicator at the bottom

Ranges: 500 m, 750 m, 1 000 m, 1 500 m, 2 000 m, 3 000 m, 5 000 m

> ⚠️ Ranges above **1 000 m** require an **ASR Transponder** within 75 blocks of the active airport.

---

### ✈️ Airports

Lists all registered airports. Shows per runway: designation, length, width, **approach coordinates sorted by threshold** (closest to threshold 1 shown first), and endpoint coordinates.

Badges:
- `← linked`: this computer is linked to this airport
- `← controlled`: this computer controls this airport remotely

Independent runways (no ATC tower) are also listed in this tab.

---

### 📡 ATC

- **Requests tab**: handle pending requests. Approach buttons are **green** if approach coordinates exist for that threshold, **pink** if not. Radio messages display in full with no truncation.
- **Radio tab**: free radio conversations per pilot
- **NOTAM tab**: publish pilot notices (max 10 lines)
- **Log tab**: last 10 ATC decisions

---

### 🔒 Admin

Password-protected (default: `admin`). Form labels are **coloured in dark blue** for readability.

Manage airports, runways and passwords (`radar_atc` privilege required for password changes).

---

## Nodes

### ASR Transponder (`radar_atc:transponder`)

Extends radar range beyond 1 000 m. Place within 75 blocks of the airport.

```
[ Dish   ]  [ Magnetron ]  [ Dish   ]
[ Waveguide ]  [ Rotator ]  [ Waveguide ]
[ Iron block ]  [ Com module ]  [ Iron block ]
```

### ATC Link Antenna (`radar_atc:link_antenna`)

Allows connecting to any airport without a password from a radar within 75 blocks.

```
[   empty   ]  [ Dish   ]  [   empty   ]
[ Waveguide ]  [ Com module ]  [ Waveguide ]
[ Iron block ]  [ Magnetron ]  [ Iron block ]
```

---

## Chat commands

All commands except `airport` and `navigate` **require being on board an aircraft**.

| Command | Description |
|---------|-------------|
| `/atc airport` | Nearest registered airport **and** nearest independent runway, with distance, direction and coordinates |
| `/atc navigate [ID]` | Full navigation info for an airport: position, runways, headings, approach coords, NOTAMs. If no ID given, uses nearest airport. |
| `/atc navigate IR` | Numbered list of the **10 nearest independent runways** (name + distance) |
| `/atc navigate IR <n>` | Full details for independent runway number `<n>` from the nearest-first ordering |
| `/atc navigate RIR` | Mixed numbered list of the **10 nearest locations** (airports and independent runways combined) |
| `/atc <ID> landing` | Request landing clearance |
| `/atc <ID> takeoff` | Request takeoff clearance |
| `/atc <ID> flyover <alt_m>` | Request flyover at given altitude (metres) |
| `/atc <ID> approach` | Request approach instructions |
| `/atc <ID> msg <text>` | Free radio message to the tower |
| `/notam <ID\|nearest>` | Consult NOTAMs for an airport |

### Independent Runways (IR)

Independent runways are landing strips without an associated ATC tower.

```
/atc navigate IR          → numbered list of 10 nearest IR (name + distance)
/atc navigate IR 3        → full details of runway #3 (name, coords, heading, length)
/atc navigate RIR         → mixed list: airports [AP] and IR [IR] by distance
```

`/atc navigate IR <n>` always sorts by current distance, so it works at any time — no need to call the list first.

---

## `radar_atc` privilege

```
/grant <player> radar_atc
```

Grants access to the password management panel in the Admin tab.

---

## Configuration

```ini
radar_atc.timer_interval = 3
radar_atc.default_radius = 1000
radar_atc.trail_len = 5
radar_atc.airport_link_r = 500
radar_atc.transponder_enabled = true
radar_atc.transponder_free_radius = 1000
radar_atc.transponder_link_r = 75
radar_atc.transponder_rotation_speed = 0.55
radar_atc.req_stale_age = 90
radar_atc.req_cmd_cooldown = 15
radar_atc.notam_max_lines = 10
radar_atc.atc_log_max = 10
```

---

## License

| Content | License |
|---------|---------|
| Source code (`.lua`) | MIT |
| 3D models and textures | CC BY-SA 4.0 |

Author: **Luffy0805**

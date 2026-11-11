-- =============================================================
-- radar_atc/config.lua  —  Global parameters and constants
--
-- All parameters marked [SETTING] can be defined in
-- minetest.conf with the prefix "radar_atc." :
--   Ex : radar_atc.default_radius = 2000
-- They are also listed in settingtypes.txt (Settings → All settings → Mods).
-- Keep defaults and bounds identical in both files: tools/check.py meta
-- compares them.
-- =============================================================

local function setting(key, default)
    local v = minetest.settings:get("radar_atc." .. key)
    return (v and v ~= "") and v or default
end

-- Numeric setting: falls back to the default if the value is not a number,
-- then clamps it to [min, max] (an invalid value used to give nil → crash).
local function num(key, default, min, max)
    local v = tonumber(setting(key, tostring(default))) or default
    return math.max(min, math.min(max, v))
end

local function bool(key, default)
    return minetest.settings:get_bool("radar_atc." .. key, default)
end

CFG = {

    -- =========================================================
    --  SECURITY / PASSWORDS
    -- =========================================================

    -- [SETTING] Password to access the Admin tab
    -- (a password changed in the Admin tab is stored and takes priority)
    radar_password_admin  = setting("radar_password_admin",  "admin"),

    -- [SETTING] Password to take remote control of an airport
    radar_password_remote = setting("radar_password_remote", "airport"),


    -- =========================================================
    --  RADAR
    -- =========================================================

    -- [SETTING] Radar refresh interval (seconds)
    timer_interval  = num("timer_interval",  3, 1, 60),

    -- Available range values in dropdown (meters) — not a setting: scan()
    -- cost grows with the range. Ranges > transponder_free_radius require
    -- a transponder.
    radius_values   = {500, 750, 1000, 1500, 2000, 3000, 5000},

    -- [SETTING] Default radar range at startup (meters)
    default_radius  = num("default_radius",  1000, 500, 5000),

    -- [SETTING] Aircraft trail length (number of stored positions)
    trail_len       = num("trail_len",       5, 0, 50),

    -- Radar display (not settings)
    lead_time  = 30,    -- s: the speed vector ends at the position in 30 s
    conflict_h = 150,   -- m: two moving aircraft closer than this horizontally…
    conflict_v = 50,    -- m: …and than this vertically are shown in conflict


    -- =========================================================
    --  AIRPORTS
    -- =========================================================

    -- [SETTING] Maximum distance (meters) for a computer to automatically link
    -- to an airport at startup
    airport_link_r  = num("airport_link_r",  500, 0, 10000),


    -- =========================================================
    --  TRANSPONDER
    -- =========================================================

    -- [SETTING] Enable or disable the transponder system (true/false)
    -- If false, all ranges are available without hardware restriction
    transponder_enabled     = bool("transponder_enabled", true),

    -- [SETTING] Maximum radar range WITHOUT transponder (meters)
    -- Beyond this, a radar_atc:transponder node must be present nearby
    transponder_free_radius = num("transponder_free_radius", 1000, 0, 5000),

    -- [SETTING] Maximum distance (blocks) between the radar computer and the
    -- transponder for it to be considered active.
    -- Capped at 79: find_nodes_in_area() searches a cube of (2r+1)³ nodes and
    -- Luanti refuses more than 4 096 000 (= 160³) — r = 80 crashed the server.
    transponder_link_r      = num("transponder_link_r", 75, 1, 79),

    -- [SETTING] Radar antenna rotation speed (radians/second)
    -- 0.4 ≈ 1 tour toutes les 16s  |  1.0 ≈ 1 tour toutes les 6s
    transponder_rotation_speed = num("transponder_rotation_speed", 0.55, 0, 5),


    -- =========================================================
    --  ATC — REQUESTS
    -- =========================================================

    -- [SETTING] Duration (seconds) after which a request becomes "stale"
    -- (grayed in the interface, and the pilot can send a new one)
    req_stale_age    = num("req_stale_age",    90, 10, 3600),

    -- [SETTING] Anti-duplicate for /atc chat command: minimum delay between
    -- two identical sends from the same command (seconds)
    req_cmd_cooldown = num("req_cmd_cooldown", 15, 0, 600),


    -- =========================================================
    --  ATC — NOTAM
    -- =========================================================

    -- [SETTING] Maximum number of NOTAM lines per airport
    notam_max_lines = num("notam_max_lines", 10, 1, 50),


    -- =========================================================
    --  ATC — LOG
    -- =========================================================

    -- [SETTING] Number of decisions kept in the log per airport
    atc_log_max     = num("atc_log_max",     10, 1, 100),


    -- =========================================================
    --  UI LAYOUT  (do not modify unless you change the target resolution)
    --  Values measured on native laptop apps, standard resolution
    -- =========================================================
    TAB_Y  = 0.32,
    TAB_H  = 0.55,
    CY     = 0.97,
    Y_MAX  = 9.62,
    X_MAX  = 14.80,
    RX     = 0.05,
    RH     = 7.60,
}

CFG.RY      = CFG.CY
CFG.RW      = 6.80
CFG.PX      = CFG.RX + CFG.RW + 0.30
CFG.PW      = CFG.X_MAX - CFG.PX
CFG.TAB_END = CFG.TAB_Y + CFG.TAB_H

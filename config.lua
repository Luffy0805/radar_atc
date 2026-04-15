-- =============================================================
-- radar_atc/config.lua  —  Global parameters and constants
--
-- All parameters marked [SETTING] can be defined in
-- minetest.conf with the prefix "radar_atc." :
--   Ex : radar_atc.default_radius = 2000
-- =============================================================

local function setting(key, default)
    local v = minetest.settings:get("radar_atc." .. key)
    return (v and v ~= "") and v or default
end

CFG = {

    -- =========================================================
    --  SECURITY / PASSWORDS
    -- =========================================================

    -- [SETTING] Password to access the Admin tab
    radar_password_admin  = "admin",

    -- [SETTING] Password to take remote control of an airport
    radar_password_remote = "airport",


    -- =========================================================
    --  RADAR
    -- =========================================================

    -- [SETTING] Radar refresh interval (seconds)
    timer_interval  = tonumber(setting("timer_interval",  "3")),

    -- [SETTING] Available range values in dropdown (meters)
    -- Note : ranges > transponder_free_radius require a transponder
    radius_values   = {500, 750, 1000, 1500, 2000, 3000, 5000},

    -- [SETTING] Default radar range at startup (meters)
    default_radius  = tonumber(setting("default_radius",  "1000")),

    -- [SETTING] Aircraft trail length (number of stored positions)
    trail_len       = tonumber(setting("trail_len",       "5")),


    -- =========================================================
    --  AIRPORTS
    -- =========================================================

    -- [SETTING] Maximum distance (meters) for a computer to automatically link
    -- to an airport at startup
    airport_link_r  = tonumber(setting("airport_link_r",  "500")),


    -- =========================================================
    --  TRANSPONDER
    -- =========================================================

    -- [SETTING] Enable or disable the transponder system (true/false)
    -- If false, all ranges are available without hardware restriction
    transponder_enabled     = (setting("transponder_enabled",     "true") == "true"),

    -- [SETTING] Maximum radar range WITHOUT transponder (meters)
    -- Beyond this, a radar_atc:transponder node must be present nearby
    transponder_free_radius = tonumber(setting("transponder_free_radius", "1000")),

    -- [SETTING] Maximum distance (blocks) between the radar computer and the
    -- transponder for it to be considered active
    transponder_link_r      = tonumber(setting("transponder_link_r",      "75")),

    -- [SETTING] Radar antenna rotation speed (radians/second)
    -- 0.4 ≈ 1 tour toutes les 16s  |  1.0 ≈ 1 tour toutes les 6s
    transponder_rotation_speed = tonumber(setting("transponder_rotation_speed", "0.55")),


    -- =========================================================
    --  ATC — REQUESTS
    -- =========================================================

    -- [SETTING] Duration (seconds) after which a request becomes "stale"
    -- (grayed in the interface, and the pilot can send a new one)
    req_stale_age    = tonumber(setting("req_stale_age",    "90")),

    -- [SETTING] Anti-duplicate for /atc chat command: minimum delay between
    -- two identical sends from the same command (seconds)
    req_cmd_cooldown = tonumber(setting("req_cmd_cooldown", "15")),


    -- =========================================================
    --  ATC — NOTAM
    -- =========================================================

    -- [SETTING] Maximum number of NOTAM lines per airport
    notam_max_lines = tonumber(setting("notam_max_lines", "10")),


    -- =========================================================
    --  ATC — LOG
    -- =========================================================

    -- [SETTING] Number of decisions kept in the log per airport
    atc_log_max     = tonumber(setting("atc_log_max",     "10")),


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

-- Alias for compatibility with can_send_request in ui_tabs.lua
REQ_STALE_AGE = CFG.req_stale_age

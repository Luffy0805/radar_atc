-- =============================================================
-- radar_atc/config.lua  —  Paramètres et constantes globales
-- =============================================================

local function setting(key, default)
    local v = minetest.settings:get("radar_atc." .. key)
    return (v and v ~= "") and v or default
end



CFG = {
    radar_password_admin  = "admin",
    radar_password_remote = "airport",
    timer_interval  = 3,
    airport_link_r  = 500,
    trail_len       = 5,
    radius_values   = {500, 750, 1000, 1500, 2000, 3000, 5000},
    default_radius  = 1000,
    -- Layout constants (mesurés sur apps natives laptop)
    TAB_Y  = 0.32,   -- y début barre onglets
    TAB_H  = 0.55,   -- hauteur onglets
    CY     = 0.97,   -- y début contenu
    Y_MAX  = 9.62,   -- y maximum safe
    X_MAX  = 14.80,  -- x maximum safe
    -- Radar
    RX = 0.05,       -- radar origine x
    RH = 7.60,       -- radar hauteur
}
CFG.RY      = CFG.CY
CFG.RW      = 6.80
CFG.PX      = CFG.RX + CFG.RW + 0.30   -- panneau droit x
CFG.PW      = CFG.X_MAX - CFG.PX       -- panneau droit largeur
CFG.TAB_END = CFG.TAB_Y + CFG.TAB_H

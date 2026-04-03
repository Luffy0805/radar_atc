-- =============================================================
-- radar_atc/config.lua  —  Paramètres et constantes globales
--
-- Tous les paramètres marqués [SETTING] peuvent être définis dans
-- minetest.conf avec le préfixe "radar_atc." :
--   Ex : radar_atc.default_radius = 2000
-- =============================================================

local function setting(key, default)
    local v = minetest.settings:get("radar_atc." .. key)
    return (v and v ~= "") and v or default
end

CFG = {

    -- =========================================================
    --  SÉCURITÉ / MOTS DE PASSE
    -- =========================================================

    -- [SETTING] Mot de passe pour accéder à l'onglet Admin
    radar_password_admin  = "admin",

    -- [SETTING] Mot de passe pour prendre le contrôle distant d'un aéroport
    radar_password_remote = "airport",


    -- =========================================================
    --  RADAR
    -- =========================================================

    -- [SETTING] Intervalle de rafraîchissement du radar (secondes)
    timer_interval  = tonumber(setting("timer_interval",  "3")),

    -- [SETTING] Valeurs de portée disponibles dans le menu déroulant (mètres)
    -- Note : les portées > transponder_free_radius nécessitent un transpondeur
    radius_values   = {500, 750, 1000, 1500, 2000, 3000, 5000},

    -- [SETTING] Portée radar par défaut au démarrage (mètres)
    default_radius  = tonumber(setting("default_radius",  "1000")),

    -- [SETTING] Longueur des traînées des avions (nombre de positions mémorisées)
    trail_len       = tonumber(setting("trail_len",       "5")),


    -- =========================================================
    --  AÉROPORTS
    -- =========================================================

    -- [SETTING] Distance maximale (mètres) pour qu'un ordinateur se lie
    -- automatiquement à un aéroport au démarrage
    airport_link_r  = tonumber(setting("airport_link_r",  "500")),


    -- =========================================================
    --  TRANSPONDEUR
    -- =========================================================

    -- [SETTING] Activer ou non le système de transpondeur (true/false)
    -- Si false, toutes les portées sont disponibles sans restriction matérielle
    transponder_enabled     = (setting("transponder_enabled",     "true") == "true"),

    -- [SETTING] Portée radar maximale SANS transpondeur (mètres)
    -- Au-delà, un nœud radar_atc:transponder doit être présent à proximité
    transponder_free_radius = tonumber(setting("transponder_free_radius", "1000")),

    -- [SETTING] Distance maximale (blocs) entre l'ordinateur radar et le
    -- transpondeur pour que celui-ci soit considéré comme actif
    transponder_link_r      = tonumber(setting("transponder_link_r",      "75")),

    -- [SETTING] Vitesse de rotation de l'antenne radar (radians/seconde)
    -- 0.4 ≈ 1 tour toutes les 16s  |  1.0 ≈ 1 tour toutes les 6s
    transponder_rotation_speed = tonumber(setting("transponder_rotation_speed", "0.55")),


    -- =========================================================
    --  ATC — REQUÊTES
    -- =========================================================

    -- [SETTING] Durée (secondes) après laquelle une requête devient "ancienne"
    -- (grisée dans l'interface, et l'avion peut en envoyer une nouvelle)
    req_stale_age    = tonumber(setting("req_stale_age",    "90")),

    -- [SETTING] Anti-doublon côté commande chat /atc : délai minimum entre
    -- deux envois identiques depuis la même commande (secondes)
    req_cmd_cooldown = tonumber(setting("req_cmd_cooldown", "15")),


    -- =========================================================
    --  ATC — NOTAM
    -- =========================================================

    -- [SETTING] Nombre maximum de lignes NOTAM par aéroport
    notam_max_lines = tonumber(setting("notam_max_lines", "10")),


    -- =========================================================
    --  ATC — LOG
    -- =========================================================

    -- [SETTING] Nombre de décisions conservées dans le log par aéroport
    atc_log_max     = tonumber(setting("atc_log_max",     "10")),


    -- =========================================================
    --  LAYOUT UI  (ne pas modifier sauf si vous changez la résolution cible)
    --  Valeurs mesurées sur apps natives laptop, résolution standard
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

-- Alias pour compatibilité avec can_send_request dans ui_tabs.lua
REQ_STALE_AGE = CFG.req_stale_age

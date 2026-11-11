-- =============================================================
-- radar_atc/init.lua  —  Mod entry point
-- Layout confirmed by analysis of native laptop apps:
--   Launcher bar : y = -0.31 to +0.30 (DO NOT touch)
--   Tabs         : y = 0.32, h = 0.55  → ends at 0.87
--   Content      : y = 0.97  →  y_max = 9.62
--   x_max safe   : 14.80
-- =============================================================

-- Important load order: dependencies first
local S = minetest.get_translator("radar_atc")

dofile(minetest.get_modpath("radar_atc") .. "/config.lua")

-- =============================================================
--  ATC PRIVILEGE
--  Allows admin access without password,
--  and to view/modify passwords from the interface.
-- =============================================================
minetest.register_privilege("radar_atc", {
    description = S("ATC access: radar admin without password, password management"),
    give_to_singleplayer = false,
})

-- Mod namespace (shared state that is not a plain function, e.g. the
-- aircraft tracker of scan.lua)
radar_atc = {}

-- Laptops running the app: [pk(pos)] = {pos, airport_id, t = os.time() of the
-- last timer tick or click}. Referenced by storage.lua, commands.lua, ui_tabs.lua.
active_nodes = {}

dofile(minetest.get_modpath("radar_atc") .. "/storage.lua")
-- Load persisted passwords (overwrite default values from config.lua)
load_passwords_into_cfg()
dofile(minetest.get_modpath("radar_atc") .. "/utils.lua")
dofile(minetest.get_modpath("radar_atc") .. "/transponder.lua")
dofile(minetest.get_modpath("radar_atc") .. "/scan.lua")
dofile(minetest.get_modpath("radar_atc") .. "/ui_tabs.lua")
dofile(minetest.get_modpath("radar_atc") .. "/fields.lua")
dofile(minetest.get_modpath("radar_atc") .. "/commands.lua")

-- =============================================================
--  APP REGISTRATION
--
--  laptop calls on_timer every CFG.timer_interval s, then formspec_func,
--  then writes the result into the node metadata; Luanti sends metadata to
--  the players around only when its value changes. Hence:
--   - nobody near the laptop → the timer does nothing (no scan, no redraw);
--   - nothing that changes by itself in the radar/ATC screens (no clock, ages
--     in minutes), so an unchanged screen costs no network;
--   - Admin tab: no automatic redraw (it would also disturb typing).
-- =============================================================
local VIEW_RADIUS  = 16    -- blocks: beyond, nobody can be looking at the laptop
local ACTIVE_KEEP  = 600   -- s: active_nodes entries older than this are removed

local skip_redraw = {}     -- [pk(pos)] = get_us_time() set by on_timer, read by formspec_func
local last_prune  = 0

local function viewer_near(pos)
    local r2 = VIEW_RADIUS * VIEW_RADIUS
    for _, pl in ipairs(minetest.get_connected_players()) do
        local pp = pl:get_pos()
        if pp then
            local dx, dy, dz = pp.x - pos.x, pp.y - pos.y, pp.z - pos.z
            if dx * dx + dy * dy + dz * dz <= r2 then return true end
        end
    end
    return false
end

local function mark_active(mtos, data)
    local now = os.time()
    active_nodes[pk(mtos.pos)] = {
        pos        = {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z},
        airport_id = data.active_airport or data.linked_airport,
        t          = now,
    }
    if now - last_prune >= 60 then
        last_prune = now
        for key, info in pairs(active_nodes) do
            if now - (info.t or 0) > ACTIVE_KEEP then active_nodes[key] = nil end
        end
    end
end

-- data.planes ← aircraft in range (shared tracker, cheap); the selected
-- aircraft stays selected even if the list order changes
local function refresh_planes(data, mtos)
    local old = data.selected and data.selected > 0 and data.planes and data.planes[data.selected]
    data.planes = scan(data.remote_center or data.center_pos or mtos.pos,
        data.radius or CFG.default_radius, nil, nil, data.active_airport or data.linked_airport)
    data.trails = nil   -- trails live in the tracker now (not saved with the laptop)
    data.selected = 0
    if old then
        for i, p in ipairs(data.planes) do
            if p.obj_id == old.obj_id then data.selected = i; break end
        end
    end
end

laptop.register_app("radar_atc", {
    app_name = "Radar ATC",
    app_icon = "radar_atc_icon.png",
    app_info = S("Air Surveillance"),

    formspec_func = function(app, mtos)
        local data = mtos.bdev:get_app_storage('ram', 'radar')
        local key  = pk(mtos.pos)
        -- Timer tick with nothing to show: keep the current screen, send nothing.
        -- (Only honoured right after on_timer, in the same laptop call.)
        local skip = skip_redraw[key]
        skip_redraw[key] = nil
        local since = skip and minetest.get_us_time() - skip   -- get_us_time() may wrap
        if since and since >= 0 and since < 100000 then return false end

        if not data.init then
            data.init       = true
            data.tab        = "radar"
            data.radius     = CFG.default_radius
            data.planes     = {}
            data.center_pos = {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
            data.selected   = 0
            data.av         = "list"
            data.atc_sub    = "requests"
            local la = linked_ap(mtos.pos)
            data.linked_airport = la and la.id or nil
            data.active_airport = data.linked_airport
        end
        mark_active(mtos, data)
        local timer = app:get_timer()
        if not timer:is_started() then timer:start(CFG.timer_interval) end
        if (data.tab or "radar") == "radar" then refresh_planes(data, mtos) end
        data._atc_dirty = nil
        return build_fs(app, mtos)
    end,

    receive_fields_func = function(app, mtos, sender, fields)
        local data = mtos.bdev:get_app_storage('ram', 'radar')
        data._player_name = sender:get_player_name()  -- for priv check in tab_admin
        data.center_pos = data.center_pos or {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
        mark_active(mtos, data)
        return do_fields(app, mtos, sender, fields)
    end,

    on_timer = function(app, mtos)
        local data = mtos.bdev:get_app_storage('ram', 'radar')
        mark_active(mtos, data)
        local tab = data.tab or "radar"
        local idle = not viewer_near(mtos.pos)
            or tab == "admin"
            or (tab == "myap" and not data._atc_dirty)
        if idle then skip_redraw[pk(mtos.pos)] = minetest.get_us_time() end
        return true  -- keep the timer running
    end,
})

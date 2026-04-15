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
minetest.register_privilege("atc", {
    description = "ATC access: radar admin without password, password management",
    give_to_singleplayer = false,
})

-- Active radar nodes table (global, referenced by storage.lua and commands.lua)
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
-- =============================================================
laptop.register_app("radar_atc", {
    app_name = S("Air Traffic Control Radar"),
    app_icon = "radar_atc_icon.png",
    app_info = S("Air Surveillance"),

    formspec_func = function(app, mtos)
        local data = mtos.bdev:get_app_storage('ram', 'radar')
        if not data.init then
            data.init       = true
            data.tab        = "radar"
            data.radius     = CFG.default_radius
            data.planes     = {}
            data.trails     = {}
            data.center_pos = {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
            data.selected   = 0
            data.av         = "list"
            data.atc_sub    = "requests"
            local la = linked_ap(mtos.pos)
            data.linked_airport = la and la.id or nil
            data.active_airport = data.linked_airport
        end
        active_nodes[pk(mtos.pos)] = {
            pos        = {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z},
            airport_id = data.active_airport or data.linked_airport,
        }
        local timer = app:get_timer()
        if not timer:is_started() then timer:start(CFG.timer_interval) end
        return build_fs(app, mtos)
    end,

    receive_fields_func = function(app, mtos, sender, fields)
        local data = mtos.bdev:get_app_storage('ram', 'radar')
        data._player_name = sender:get_player_name()  -- for priv check in tab_admin
        data.center_pos = data.center_pos or {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
        active_nodes[pk(mtos.pos)] = {
            pos        = {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z},
            airport_id = data.active_airport or data.linked_airport,
        }
        return do_fields(app, mtos, sender, fields)
    end,

    on_timer = function(app, mtos)
        local data  = mtos.bdev:get_app_storage('ram', 'radar')
        local cpos  = data.remote_center or data.center_pos
                   or {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
        data.center_pos = data.center_pos or {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
        data.radius     = data.radius or CFG.default_radius
        local linked    = data.active_airport or data.linked_airport

        local old_sel = (data.selected and data.selected > 0 and data.planes)
                        and data.planes[data.selected] or nil
        local new_planes, new_trails = scan(cpos, data.radius, data.planes, data.trails, linked)

        -- Only rebuild formspec IF something changed
        local changed = (#new_planes ~= #(data.planes or {}))
        if not changed then
            for i, p in ipairs(new_planes) do
                local op = data.planes and data.planes[i]
                if not op or op.model ~= p.model or op.owner ~= p.owner
                   or math.abs(op.alt_m - p.alt_m) > 2 or op.has_req ~= p.has_req then
                    changed = true; break
                end
            end
        end
        if data._atc_dirty then changed = true; data._atc_dirty = false end

        data.planes = new_planes; data.trails = new_trails

        if old_sel then
            data.selected = 0
            for i, p in ipairs(data.planes) do
                -- Priority to obj_id (unique), fallback on model+owner for compatibility
                if (old_sel.obj_id and p.obj_id == old_sel.obj_id)
                   or (not old_sel.obj_id and p.model == old_sel.model and p.owner == old_sel.owner) then
                    data.selected = i; break
                end
            end
        end

        return true  -- always true: stopping the timer would kill the trails
    end,
})

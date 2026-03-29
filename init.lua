-- =============================================================
-- radar_atc/init.lua  —  Point d'entrée du mod
-- Layout confirmé par analyse des apps natives laptop :
--   Barre launcher : y = -0.31 à +0.30 (NE PAS toucher)
--   Onglets        : y = 0.32, h = 0.55  → fin à 0.87
--   Contenu        : y = 0.97  →  y_max = 9.62
--   x_max safe     : 14.80
-- =============================================================

-- Ordre de chargement important : les dépendances en premier
dofile(minetest.get_modpath("radar_atc") .. "/config.lua")

-- Table des radars actifs (globale, référencée par storage.lua et commands.lua)
active_nodes = {}

dofile(minetest.get_modpath("radar_atc") .. "/storage.lua")
dofile(minetest.get_modpath("radar_atc") .. "/utils.lua")
dofile(minetest.get_modpath("radar_atc") .. "/scan.lua")
dofile(minetest.get_modpath("radar_atc") .. "/ui_tabs.lua")
dofile(minetest.get_modpath("radar_atc") .. "/fields.lua")
dofile(minetest.get_modpath("radar_atc") .. "/commands.lua")

-- =============================================================
--  ENREGISTREMENT APP
-- =============================================================
laptop.register_app("radar_atc", {
    app_name = "Radar ATC",
    app_icon = "radar_atc_icon.png",
    app_info = "Surveillance aérienne",

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

        -- Scan avions
        local old_sel = (data.selected and data.selected > 0 and data.planes)
                        and data.planes[data.selected] or nil
        local new_planes, new_trails = scan(cpos, data.radius, data.planes, data.trails, linked)

        -- Ne rebuild le formspec QUE si quelque chose a changé
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
                -- Priorité à obj_id (unique), fallback sur model+owner pour compatibilité
                if (old_sel.obj_id and p.obj_id == old_sel.obj_id)
                   or (not old_sel.obj_id and p.model == old_sel.model and p.owner == old_sel.owner) then
                    data.selected = i; break
                end
            end
        end

        return true  -- toujours true : arrêter le timer tuerait les trails
    end,
})

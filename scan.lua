-- =============================================================
-- radar_atc/scan.lua  —  Détection et suivi des avions
-- =============================================================

-- uid basé sur l'ID interne de l'objet Lua :
--   - stable pendant toute la durée de vie de l'entité (ne change pas avec la position)
--   - unique même si deux avions identiques appartiennent au même owner
--   - stocké dans p.obj_id pour la comparaison inter-ticks
local function uid_from_obj(obj)
    if obj.get_id then
        return tostring(obj:get_id())
    end
    return tostring(obj)
end

local function has_atc_request(player_name, airport_id)
    if not airport_id then return false end
    local state = get_shared_atc(airport_id)
    for _, r in ipairs(state.requests or {}) do
        if r.player == player_name then return true end
    end
    return false
end

function scan(cpos, radius, old, trails, active_ap)
    trails = trails or {}
    -- Index des anciennes données par obj_id pour lookup O(1)
    local old_by_id = {}
    if old then
        for _, op in ipairs(old) do
            if op.obj_id then old_by_id[op.obj_id] = op end
        end
    end

    local res = {}
    local objs = core.get_objects_inside_radius(cpos, radius)
    for _, obj in ipairs(objs) do
        if not obj:is_player() then
            local e = obj:get_luaentity()
            if e and e._vehicle_name then
                local pilot = (e.driver_name and e.driver_name ~= "") and e.driver_name or nil
                if pilot or e.isonground == false then
                    local pos   = obj:get_pos()
                    local vel   = obj:get_velocity() or {x=0, y=0, z=0}
                    local sp    = hspd(vel)
                    local obj_id = uid_from_obj(obj)   -- clé stable unique par entité
                    local p = {
                        obj_id   = obj_id,
                        model    = e._vehicle_name,
                        owner    = e.owner or "?",
                        pilot    = pilot,
                        pos      = {x=pos.x, y=pos.y, z=pos.z},
                        heading  = yaw2head(e._yaw or 0),
                        spd_ms   = sp,
                        climb    = e._climb_rate or 0,
                        alt_m    = math.floor(pos.y + 0.5),
                        hp       = math.floor((e.hp_max or 0) * 100) / 100,
                        hp_max   = math.floor((e._max_plane_hp or e.hp_max or 0) * 100) / 100,
                        fuel     = (e._max_fuel and e._max_fuel > 0)
                                    and math.floor((e._energy or 0) * 100 / e._max_fuel) or nil,
                        energy   = e._energy or 0,
                        max_fuel = e._max_fuel or 0,
                        throttle = e._power_lever and math.floor(e._power_lever + 0.5) or nil,
                        -- -------------------------------------------------------
                        -- AUTONOMIE : comment ça marche pour le PA-28
                        -- -------------------------------------------------------
                        -- e._energy      = carburant restant (unité interne)
                        -- e._max_fuel    = capacité maximale (même unité)
                        -- e._power_lever = position des gaz (0 à 100)
                        -- Consommation/seconde = power_lever / 700000 * 20
                        --   (700000 = diviseur du mod airutils pour la PA-28,
                        --    20 = ticks/seconde approximatif du moteur physique)
                        -- Pour adapter à un autre avion :
                        --   1. Trouver son diviseur dans le code airutils
                        --      (chercher "_energy" et le chiffre qui le divise)
                        --   2. Remplacer "PA-28" par le nom _vehicle_name de l'avion
                        --   3. Remplacer 700000 par le diviseur trouvé
                        -- -------------------------------------------------------
                        autonomy_min = (e._vehicle_name == "PA-28"
                                       and e._power_lever and e._power_lever > 0.5
                                       and e._max_fuel and e._max_fuel > 0
                                       and e._energy and e._energy > 0)
                            and math.floor((e._energy / (e._power_lever / 700000 * 20)) / 60 + 0.5)
                            or nil,
                        dist    = d2d(cpos, pos),
                        has_req = (pilot and has_atc_request(pilot, active_ap)) or false,
                    }
                    -- Traînée : ajoute un point seulement si l'avion est en mouvement
                    local src = trails[obj_id] or {}
                    local tr  = {}
                    for i = 1, #src do tr[i] = src[i] end
                    if sp > 0.5 then
                        -- En mouvement : ajoute la position précédente en tête
                        local op = old_by_id[obj_id]
                        if op then
                            table.insert(tr, 1, {x=op.pos.x, y=op.pos.y, z=op.pos.z})
                        end
                    else
                        -- À l'arrêt : efface la traînée
                        tr = {}
                    end
                    while #tr > CFG.trail_len do table.remove(tr, #tr) end
                    p.trail = tr
                    table.insert(res, p)
                end
            end
        end
    end
    table.sort(res, function(a, b) return a.dist < b.dist end)
    local nt = {}
    for _, p in ipairs(res) do nt[p.obj_id] = p.trail end
    return res, nt
end

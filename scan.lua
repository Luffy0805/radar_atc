-- =============================================================
-- radar_atc/scan.lua  —  Détection et suivi des avions
-- =============================================================

local function uid(p)
    -- Identifiant stable : model + owner uniquement (ne change pas quand l'avion bouge)
    return string.format("%s__%s", p.model or "", p.owner or "")
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
    local res = {}
    local objs = core.get_objects_inside_radius(cpos, radius)
    for _, obj in ipairs(objs) do
        if not obj:is_player() then
            local e = obj:get_luaentity()
            if e and e._vehicle_name then
                local pilot = (e.driver_name and e.driver_name ~= "") and e.driver_name or nil
                if pilot or e.isonground == false then
                    local pos = obj:get_pos()
                    local vel = obj:get_velocity() or {x=0, y=0, z=0}
                    local sp  = hspd(vel)
                    local p = {
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
                        -- Autonomie PA28 (divisor=700000, ~20fps, lever 0-100)
                        autonomy_min = (e._vehicle_name == "PA-28"
                                       and e._power_lever and e._power_lever > 0.5
                                       and e._max_fuel and e._max_fuel > 0
                                       and e._energy and e._energy > 0)
                            and math.floor((e._energy / (e._power_lever / 700000 * 20)) / 60 + 0.5)
                            or nil,
                        dist    = d2d(cpos, pos),
                        has_req = (pilot and has_atc_request(pilot, active_ap)) or false,
                    }
                    -- Traînée (Lua 5.1) : on ajoute un point seulement si l'avion est en mouvement
                    local u   = uid(p)
                    local src = trails[u] or {}
                    local tr  = {}
                    for i = 1, #src do tr[i] = src[i] end
                    if old and sp > 0.5 then   -- n'ajoute le point précédent que si en mouvement
                        for _, op in ipairs(old) do
                            if uid(op) == u then
                                table.insert(tr, 1, {x=op.pos.x, y=op.pos.y, z=op.pos.z})
                                break
                            end
                        end
                    elseif sp <= 0.5 then
                        -- Avion à l'arrêt : vide la traînée progressivement
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
    for _, p in ipairs(res) do nt[uid(p)] = p.trail end
    return res, nt
end

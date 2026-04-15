-- =============================================================
-- radar_atc/scan.lua  --  Aircraft detection and tracking
-- =============================================================

-- uid based on the internal Lua object ID:
--   - stable for the entire lifetime of the entity
--   - unique even if two identical aircraft have the same owner
local function uid_from_obj(obj)
    if obj.get_id then
        return tostring(obj:get_id())
    end
    return tostring(obj)
end

-- =============================================================
--  RANGE / AUTONOMY -- generic airutils formula
--  consumption/sec = power_lever / DIVISOR * 20
--  autonomy (min) = energy / conso_sec / 60
--
--  DIVISORS per model (_fuel_consumption_divisor):
--    PA-28                 -> 700000  (airutils default, not defined in mod)
--    Super Cub             -> 700000  (airutils default, not defined in mod)
--    Super Duck Hydroplane -> 700000  (copy of supercub)
--    Ju 52 3M              -> 500000  (defined in ju52/init.lua)
--    Ju52 3M Hydroplane    -> 500000  (copy of ju52)
--    trike                 -> 1200000 (defined in trike/init.lua)
--
--  To add an aircraft: look for _fuel_consumption_divisor in
--  its init.lua. If absent, use 700000 (airutils default).
-- =============================================================
local AUTONOMY_DIVISORS = {
    ["PA-28"]                  = 700000,
    ["Super Cub"]              = 700000,
    ["Super Duck Hydroplane"]  = 700000,
    ["Ju 52 3M"]               = 500000,
    ["Ju52 3M Hydroplane"]     = 500000,
    ["trike"]                  = 1200000,
}

local function calc_autonomy(e)
    local div = AUTONOMY_DIVISORS[e._vehicle_name]
    if not div then return nil end
    if not e._power_lever or e._power_lever <= 0.5 then return nil end
    if not e._max_fuel or e._max_fuel <= 0 then return nil end
    if not e._energy or e._energy <= 0 then return nil end
    local conso_sec = e._power_lever / div * 20
    return math.floor(e._energy / conso_sec / 60 + 0.5)
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
                -- If commands were transferred to the co-pilot, they are the active pilot
                local active_pilot = pilot
                if e._command_is_given and e.co_pilot and e.co_pilot ~= "" then
                    active_pilot = e.co_pilot
                end
                if pilot or e.isonground == false then
                    local pos    = obj:get_pos()
                    local vel    = obj:get_velocity() or {x=0, y=0, z=0}
                    local sp     = hspd(vel)
                    local obj_id = uid_from_obj(obj)
                    local p = {
                        obj_id   = obj_id,
                        model    = e._vehicle_name,
                        owner    = e.owner or "?",
                        pilot    = active_pilot,
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
                        autonomy_min = calc_autonomy(e),
                        dist     = d2d(cpos, pos),
                        has_req  = (active_pilot and has_atc_request(active_pilot, active_ap)) or false,
                    }
                    local src = trails[obj_id] or {}
                    local tr  = {}
                    for i = 1, #src do tr[i] = src[i] end
                    if sp > 0.5 then
                        local op = old_by_id[obj_id]
                        if op then
                            table.insert(tr, 1, {x=op.pos.x, y=op.pos.y, z=op.pos.z})
                        end
                    else
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

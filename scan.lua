-- =============================================================
-- radar_atc/scan.lua  --  Aircraft detection and tracking
-- =============================================================

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

-- Players who have a request at the airport, read once per scan
local function players_with_request(airport_id)
    local set = {}
    if not airport_id then return set end
    for _, r in ipairs(get_shared_atc(airport_id).requests or {}) do
        if r.player then set[r.player] = true end
    end
    return set
end

-- =============================================================
--  GLOBAL AIRCRAFT TRACKER
--  One pass over the active entities (minetest.luaentities) at most every
--  TRACK_INTERVAL seconds, shared by every laptop. Until 1.1.1, each open
--  laptop called get_objects_inside_radius(5000) on every timer tick, which
--  handed every object of the area (dropped items, mobs…) to Lua, laptop
--  after laptop. No globalstep: nothing runs while nobody uses a radar.
--  Trails also live here (shared, not saved in every laptop's RAM).
-- =============================================================
local TRACK_INTERVAL = 1   -- seconds: data shown is at most this old

local tracker = {
    sampled_at = nil,   -- time (s) of the last sample
    trail_at   = nil,   -- time (s) of the last trail point
    list       = {},    -- aircraft of the last sample (plain, serializable tables)
    trails     = {},    -- [obj_id] = {pos, pos…}, most recent first
    last_pos   = {},    -- [obj_id] = position at the last trail point
}
radar_atc.tracker = tracker

local function now_s()
    return minetest.get_us_time() / 1000000
end

local function sample(now)
    local list, alive = {}, {}
    local push_trail = not tracker.trail_at or now - tracker.trail_at >= CFG.timer_interval
    if push_trail then tracker.trail_at = now end
    for id, e in pairs(minetest.luaentities) do
        if e._vehicle_name and (e._max_plane_hp or e._climb_rate ~= nil) then
            -- Only aircraft with a pilot are shown (filters parked/ghost aircraft)
            local pilot = (e.driver_name and e.driver_name ~= "") and e.driver_name or nil
            local obj = pilot and e.object
            local pos = obj and obj:get_pos()
            if pos then
                local active_pilot = pilot
                if e._command_is_given and e.co_pilot and e.co_pilot ~= "" then
                    active_pilot = e.co_pilot
                end
                local vel    = obj:get_velocity() or {x=0, y=0, z=0}
                local sp     = hspd(vel)
                local obj_id = tostring(id)
                list[#list + 1] = {
                    obj_id   = obj_id,
                    model    = e._vehicle_name,
                    owner    = e.owner or "?",
                    pilot    = active_pilot,
                    pos      = {x=pos.x, y=pos.y, z=pos.z},
                    vx       = vel.x,
                    vz       = vel.z,
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
                    autonomy_min   = calc_autonomy(e),
                    autonomy_known = AUTONOMY_DIVISORS[e._vehicle_name] ~= nil,
                }
                alive[obj_id] = true
                -- Trail: one point every timer_interval while moving, cleared when stopped
                if sp <= 0.5 then
                    tracker.trails[obj_id] = nil
                    tracker.last_pos[obj_id] = nil
                elseif push_trail then
                    local tr = tracker.trails[obj_id] or {}
                    local lp = tracker.last_pos[obj_id]
                    if lp then table.insert(tr, 1, lp) end
                    while #tr > CFG.trail_len do tr[#tr] = nil end
                    tracker.trails[obj_id] = tr
                    tracker.last_pos[obj_id] = {x=pos.x, y=pos.y, z=pos.z}
                end
            end
        end
    end
    -- Forget aircraft that left (unloaded, removed, pilot gone)
    for id in pairs(tracker.trails) do if not alive[id] then tracker.trails[id] = nil end end
    for id in pairs(tracker.last_pos) do if not alive[id] then tracker.last_pos[id] = nil end end
    tracker.list = list
    tracker.sampled_at = now
end

-- Aircraft within `radius` of cpos, nearest first, with dist and has_req.
-- Uses the shared sample (taken again if older than TRACK_INTERVAL).
-- The 3rd and 4th parameters are ignored (old signature: old planes, trails).
function scan(cpos, radius, _, _, active_ap)
    local now = now_s()
    if not tracker.sampled_at or now - tracker.sampled_at >= TRACK_INTERVAL then
        sample(now)
    end
    local res = {}
    local requesters = players_with_request(active_ap)
    local r2 = radius * radius
    for _, a in ipairs(tracker.list) do
        local dx, dy, dz = a.pos.x - cpos.x, a.pos.y - cpos.y, a.pos.z - cpos.z
        if dx * dx + dy * dy + dz * dz <= r2 then
            local p = {}
            for k, v in pairs(a) do p[k] = v end
            p.dist    = d2d(cpos, a.pos)
            p.has_req = requesters[a.pilot] or false
            res[#res + 1] = p
        end
    end
    table.sort(res, function(a, b) return a.dist < b.dist end)
    return res
end

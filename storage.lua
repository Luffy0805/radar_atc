-- =============================================================
-- radar_atc/storage.lua  —  Persistent storage (airports + ATC)
-- =============================================================

local ST = minetest.get_mod_storage()
local _ap_cache = nil

function get_airports()
    if not _ap_cache then
        local r = ST:get_string("airports_v5")
        _ap_cache = (r ~= "" and minetest.deserialize(r)) or {}
    end
    return _ap_cache
end

function save_airports()
    ST:set_string("airports_v5", minetest.serialize(_ap_cache or {}))
end

-- ATC state shared between all nodes of the same airport
function get_shared_atc(airport_id)
    if not airport_id then return {requests={}, conversations={}} end
    local r = ST:get_string("atc_" .. airport_id)
    return (r ~= "" and minetest.deserialize(r))
        or {requests={}, conversations={}}
end

function save_shared_atc(airport_id, state)
    if not airport_id then return end
    ST:set_string("atc_" .. airport_id, minetest.serialize(state))
    -- Notify all active nodes for this airport
    for _, info in pairs(active_nodes or {}) do
        if info.airport_id == airport_id then
            local mt = laptop.os_get(info.pos)
            if mt then
                local data = mt.bdev:get_app_storage('ram', 'radar')
                data._atc_dirty = true
                if not data._save_scheduled then
                    data._save_scheduled = true
                    minetest.after(1.5, function()
                        local mt2 = laptop.os_get(info.pos)
                        if mt2 then
                            local d2 = mt2.bdev:get_app_storage('ram', 'radar')
                            d2._save_scheduled = false
                            d2._atc_dirty = false
                            mt2:save()
                        end
                    end)
                end
            end
        end
    end
end

function find_ap(id)
    if not id then return nil end
    for i, a in ipairs(get_airports()) do
        if a.id == id then return a, i end
    end
end

-- =============================================================
--  One-time fix of runway names (radar_atc ≤ 1.1.0)
--  bearing() used to flip north and south, so diagonal runways were
--  named as their mirror image (a 030°/210° runway became "15/33").
--  Renames those runways and moves each approach point and L/R/C
--  suffix along with its physical runway end. Runways whose numbers do
--  not change (north-south, east-west) and names that do not match the
--  old automatic name (edited by hand) are left untouched.
-- =============================================================
local RWY_FIX_FLAG = "rwy_names_fixed_v1"

local function old_bearing(p1, p2)
    return math.deg(math.atan2(p2.x - p1.x, -(p2.z - p1.z))) % 360
end

-- Name token ("03L") of the runway end whose number is `num`
local function token_for(name, num)
    for tok in name:gmatch("[^/]+") do
        if tonumber(tok:match("^(%d+)")) == num then return tok end
    end
end

-- Returns the corrected name and the old→new end token map, or nil
local function fixed_runway_name(p1, p2, name)
    local ob = old_bearing(p1, p2)
    local suffix
    for _, s in ipairs({"", "L", "R", "C"}) do
        if rwy_name(p1, p2, s, ob) == name then suffix = s; break end
    end
    if not suffix then return nil end                  -- edited by hand: leave it
    local nb = bearing(p1, p2)
    local o1 = rwy_num(ob); local o2 = (o1 + 17) % 36 + 1
    local n1 = rwy_num(nb); local n2 = (n1 + 17) % 36 + 1
    if (o1 == n1 and o2 == n2) or (o1 == n2 and o2 == n1) then
        return nil                                     -- same numbers (N-S, E-W): unchanged
    end
    local new_name = rwy_name(p1, p2, suffix)
    -- o1/n1 = end p1→p2, o2/n2 = end p2→p1: each keeps its physical end
    return new_name, {
        [token_for(name, o1)] = token_for(new_name, n1),
        [token_for(name, o2)] = token_for(new_name, n2),
    }
end

local function fix_runway(rw)
    if not (rw.p1 and rw.p2 and type(rw.name) == "string") then return false end
    local new_name, ends = fixed_runway_name(rw.p1, rw.p2, rw.name)
    if not new_name then return false end
    if rw.approaches then
        local moved = {}
        for key, coords in pairs(rw.approaches) do
            moved[ends[key] or key] = coords
        end
        rw.approaches = moved
    end
    minetest.log("action", "[radar_atc] runway renamed " .. rw.name .. " → " .. new_name
        .. " (heading fix)")
    rw.name = new_name
    return true
end

minetest.register_on_mods_loaded(function()
    if ST:get_int(RWY_FIX_FLAG) == 1 then return end
    local changed = false
    for _, ap in ipairs(get_airports()) do
        for _, rw in ipairs(ap.runways or {}) do
            if fix_runway(rw) then changed = true end
        end
    end
    if changed then save_airports() end
    ST:set_int(RWY_FIX_FLAG, 1)
end)

-- =============================================================
--  INDEPENDENT RUNWAYS (no dedicated ATC)
--  Structure: {name=str, p1={x,y,z}, p2={x,y,z}, width=int, note=str}
-- =============================================================
local _strip_cache = nil

function get_strips()
    if not _strip_cache then
        local r = ST:get_string("indep_strips_v1")
        _strip_cache = (r ~= "" and minetest.deserialize(r)) or {}
    end
    return _strip_cache
end

function save_strips()
    ST:set_string("indep_strips_v1", minetest.serialize(_strip_cache or {}))
end

-- =============================================================
--  NOTAM  (pilot notices, per airport)
--  Structure : liste de strings, une par ligne
-- =============================================================
function get_notam(airport_id)
    if not airport_id then return {} end
    local r = ST:get_string("notam_" .. airport_id)
    return (r ~= "" and minetest.deserialize(r)) or {}
end

function save_notam(airport_id, lines)
    if not airport_id then return end
    ST:set_string("notam_" .. airport_id, minetest.serialize(lines or {}))
end

-- =============================================================
--  ATC LOG  (latest authorizations/refusals, per airport)
--  Structure : {time, player, model, req_type, decision, runway}
-- =============================================================
function get_atc_log(airport_id)
    if not airport_id then return {} end
    local r = ST:get_string("atclog_" .. airport_id)
    return (r ~= "" and minetest.deserialize(r)) or {}
end

function push_atc_log(airport_id, entry)
    if not airport_id then return end
    local log = get_atc_log(airport_id)
    table.insert(log, 1, entry)  -- most recent first
    while #log > (CFG.atc_log_max or 10) do table.remove(log) end
    ST:set_string("atclog_" .. airport_id, minetest.serialize(log))
end

-- =============================================================
--  PASSWORDS  (persistent, modifiable without restart)
--  Stored in mod_storage, take priority over config.lua
-- =============================================================
function get_passwords()
    local r = ST:get_string("passwords_v1")
    return (r ~= "" and minetest.deserialize(r)) or {}
end

function save_passwords(pw_table)
    ST:set_string("passwords_v1", minetest.serialize(pw_table))
end

-- Called from init.lua at startup: loads persisted passwords into CFG
function load_passwords_into_cfg()
    local pw = get_passwords()
    if pw.admin  and pw.admin  ~= "" then CFG.radar_password_admin  = pw.admin  end
    if pw.remote and pw.remote ~= "" then CFG.radar_password_remote = pw.remote end
end

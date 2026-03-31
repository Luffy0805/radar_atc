-- =============================================================
-- radar_atc/storage.lua  —  Stockage persistant (aéroports + ATC)
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

-- État ATC partagé entre tous les nœuds d'un même aéroport
function get_shared_atc(airport_id)
    if not airport_id then return {requests={}, conversations={}} end
    local r = ST:get_string("atc_" .. airport_id)
    return (r ~= "" and minetest.deserialize(r))
        or {requests={}, conversations={}}
end

function save_shared_atc(airport_id, state)
    if not airport_id then return end
    ST:set_string("atc_" .. airport_id, minetest.serialize(state))
    -- Notifie tous les nœuds actifs de cet aéroport
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
--  PISTES INDÉPENDANTES (sans ATC dédié)
--  Structure : {name=str, p1={x,y,z}, p2={x,y,z}, width=int, note=str}
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

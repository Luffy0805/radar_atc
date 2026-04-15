-- =============================================================
-- radar_atc/commands.lua  —  Chat commands /atc
-- =============================================================

local S = minetest.get_translator("radar_atc")

local function in_aircraft(name)
    local p = minetest.get_player_by_name(name)
    if not p then return false, nil, nil end
    local seat = p:get_attach()
    if not seat then return false, nil, nil end
    local function ck(o)
        if not o then return false, nil, nil end
        local e = o:get_luaentity()
        if e and e._vehicle_name then
            return true, e._vehicle_name, e.owner
        end
        return false, nil, nil
    end
    local ok, model, owner = ck(seat)
    if ok then return ok, model, owner end
    return ck(seat:get_attach())
end

local function push_req(airport_id, req)
    for _, info in pairs(active_nodes) do
        if info.airport_id == airport_id then
            local mt = laptop.os_get(info.pos)
            if mt then
                local d = mt.bdev:get_app_storage('ram', 'radar')
                d._atc_dirty = true
                if not d._save_scheduled then
                    d._save_scheduled = true
                    minetest.after(1.5, function()
                        local mt2 = laptop.os_get(info.pos)
                        if mt2 then
                            local d2 = mt2.bdev:get_app_storage('ram', 'radar')
                            d2._save_scheduled = false; mt2:save()
                        end
                    end)
                end
            end
        end
    end
end

local function push_radio(airport_id, from, txt)
    local state = get_shared_atc(airport_id)
    state.conversations = state.conversations or {}
    local idx = nil
    for ci, c in ipairs(state.conversations) do
        if c.pilot == from then idx = ci; break end
    end
    if not idx then
        table.insert(state.conversations, {pilot=from, messages={}})
        idx = #state.conversations
    end
    table.insert(state.conversations[idx].messages, {from=from, text=txt, time=os.time()})
    save_shared_atc(airport_id, state)
end

minetest.register_chatcommand("atc", {
    params = "<airport_ID|airport> <landing|takeoff|flyover|approach|msg> [param]",
    description = table.concat({
        "ATC tower communication.",
        "  /atc airport               — shows the nearest registered airport",
        "  /atc <ID> landing          — request landing clearance",
        "  /atc <ID> takeoff          — request takeoff clearance",
        "  /atc <ID> flyover <alt_m>  — request flyover at given altitude (meters)",
        "  /atc <ID> approach         — request approach instructions",
        "  /atc <ID> msg <text>       — free radio message to the tower",
        "All commands (except 'airport') require being on board an aircraft.",
    }, "\n"),
    func = function(name, param)
        local args = {}
        for w in param:gmatch("%S+") do table.insert(args, w) end
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end

        -- /atc airport
        if args[1] and args[1]:lower() == "airport" then
            local ppos = player:get_pos()
            local ap, d = nearest_ap(ppos)
            if ap and ap.pos then
                -- Cardinal direction calculation
                local dx = ap.pos.x - ppos.x
                local dz = ap.pos.z - ppos.z
                local angle = math.deg(math.atan2(dx, dz)) % 360
                local dirs = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                              "S","SSO","SO","OSO","O","ONO","NO","NNO"}
                local dir = dirs[math.floor((angle + 11.25) / 22.5) % 16 + 1]
                return true, clr("#88CCFF",
                    string.format("[ATC] Nearest: [%s] %s — %dm — %s",
                        ap.id, ap.name, math.floor(d), dir))
            elseif ap then
                return true, clr("#88CCFF",
                    string.format("[ATC] Nearest: [%s] %s — %dm", ap.id, ap.name, math.floor(d)))
            end
            return true, clr("#FFAA44", "[ATC] No airport registered.")
        end

        local aid    = args[1] and args[1]:upper()
        local action = args[2] and args[2]:lower()
        if not aid or not action then
            return false, "Usage: /atc <ID|airport> <landing|takeoff|flyover|approach|msg> [param]"
        end

        local ap = find_ap(aid)
        if not ap then
            return false, clr("#FF4444", "[ATC] '" .. aid .. "' unknown. Try /atc airport")
        end

        local ok, model, owner = in_aircraft(name)
        if not ok then
            return false, clr("#FF4444", "[ATC] You must be on board an aircraft.")
        end

        if action == "msg" then
            local txt = table.concat(args, " ", 3):match("^%s*(.-)%s*$")
            if txt == "" then return false, "Usage: /atc " .. aid .. " msg <text>" end
            push_radio(aid, name, txt)
            return true, clr("#FFFF44", "[ATC " .. aid .. "] Radio message sent.")
        end

        local valid = {landing=true, takeoff=true, flyover=true, approach=true}
        if not valid[action] then
            return false, "Invalid action: landing, takeoff, flyover, approach, msg"
        end

        local alt = tonumber(args[3])
        if action == "flyover" and not alt then
            return false, "Specify altitude: /atc " .. aid .. " flyover 500"
        end

        local state = get_shared_atc(aid)
        state.requests = state.requests or {}

        -- Anti-doublon
        for _, r in ipairs(state.requests) do
            if r.player == name and r.req_type == action and (os.time() - (r.time or 0)) < CFG.req_cmd_cooldown then
                return false, clr("#FFAA44", "[ATC] Request already sent, please wait.")
            end
        end

        local req = {
            player   = name, airport = aid, req_type = action,
            alt      = alt,  time    = os.time(), status = nil,
            model    = model, owner  = owner,
        }
        table.insert(state.requests, req)
        save_shared_atc(aid, state)
        push_req(aid, req)

        local has = false
        for _, info in pairs(active_nodes) do
            if info.airport_id == aid then has = true; break end
        end

        local tf = {
            landing  = "landing request",
            takeoff  = "takeoff request",
            flyover  = "flyover at " .. (alt and (alt .. "m/" .. to_ft(alt) .. "ft") or ""),
            approach = "approach request",
        }
        return true, clr("#FFFF44",
            "[ATC " .. aid .. "] " .. tf[action] .. " sent"
            .. (has and "" or " (no active tower)") .. ".")
    end,
})

-- =============================================================
--  COMMAND /notam  —  Consult pilot notices
-- =============================================================
minetest.register_chatcommand("notam", {
    params = "<airport_ID>",
    description = table.concat({
        "Consult pilot notices (NOTAM) for an airport.",
        "  /notam <ID>     — shows NOTAM for the airport",
        "  /notam nearest  — shows NOTAM for the nearest airport",
    }, "\n"),
    func = function(name, param)
        local arg = param:match("^%s*(.-)%s*$")
        if arg == "" then
            return false, "Usage: /notam <airport_ID> or /notam nearest"
        end

        local ap
        if arg:lower() == "nearest" then
            local player = minetest.get_player_by_name(name)
            if not player then return false, "Player not found." end
            ap = nearest_ap(player:get_pos())
            if not ap then
                return true, clr("#FFAA44", "[NOTAM] No airport registered.")
            end
        else
            ap = find_ap(arg:upper())
            if not ap then
                return false, clr("#FF4444", "[NOTAM] Airport '" .. arg:upper() .. "' unknown.")
            end
        end

        local lines = get_notam(ap.id)
        local header = clr("#88CCFF", "=== NOTAM [" .. ap.id .. "] " .. ap.name .. " ===")
        minetest.chat_send_player(name, header)
        if #lines == 0 then
            minetest.chat_send_player(name, clr("#888888", "  Aucun NOTAM actif."))
        else
            for i, line in ipairs(lines) do
                minetest.chat_send_player(name,
                    clr("#FFFF88", string.format("  %d. %s", i, line)))
            end
        end
        return true
    end,
})

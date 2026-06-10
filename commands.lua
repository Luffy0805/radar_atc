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
        -- Only accept airutils-based aircraft (not automobiles)
        if e and e._vehicle_name and (e._max_plane_hp or e._climb_rate ~= nil) then
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
    params = "<airport_ID|airport|navigate> <landing|takeoff|flyover|approach|msg> [param]",
    description = table.concat({
        "ATC tower communication.",
        "  /atc airport               — shows the nearest registered airport",
        "  /atc navigate [ID]         — navigation info for an airport (runways, heading, coords)",
        "  /atc <ID> landing          — request landing clearance",
        "  /atc <ID> takeoff          — request takeoff clearance",
        "  /atc <ID> flyover <alt_m>  — request flyover at given altitude (meters)",
        "  /atc <ID> approach         — request approach instructions",
        "  /atc <ID> msg <text>       — free radio message to the tower",
        "All commands (except 'airport' and 'navigate') require being on board an aircraft.",
    }, "\n"),
    func = function(name, param)
        local args = {}
        for w in param:gmatch("%S+") do table.insert(args, w) end
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end

        -- /atc airport
        if args[1] and args[1]:lower() == "airport" then
            local ppos = player:get_pos()

            -- Helper: cardinal direction from ppos to a target position
            local dir_labels = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                                 "S","SSO","SO","OSO","O","ONO","NO","NNO"}
            local function card_dir(target)
                local angle = math.deg(math.atan2(target.x - ppos.x, target.z - ppos.z)) % 360
                return dir_labels[math.floor((angle + 11.25) / 22.5) % 16 + 1]
            end

            -- Nearest registered airport
            local ap, d_ap = nearest_ap(ppos)

            -- Nearest independent strip (centre = midpoint of p1/p2)
            local nearest_st, d_st = nil, math.huge
            for _, st in ipairs(get_strips()) do
                if st.p1 and st.p2 then
                    local cx = (st.p1.x + st.p2.x) / 2
                    local cy = (st.p1.y + st.p2.y) / 2
                    local cz = (st.p1.z + st.p2.z) / 2
                    local d  = d2d(ppos, {x=cx, y=cy, z=cz})
                    if d < d_st then
                        nearest_st = st
                        nearest_st._center = {x=cx, y=cy, z=cz}
                        d_st = d
                    end
                end
            end

            local lines = {}

            -- Always show nearest airport
            if ap and ap.pos then
                local coords = string.format("(%.0f, %.0f, %.0f)", ap.pos.x, ap.pos.y, ap.pos.z)
                lines[#lines+1] = clr("#88CCFF",
                    S("[ATC] Nearest: [@1] @2 — @3m — @4",
                        ap.id, ap.name, tostring(math.floor(d_ap)), card_dir(ap.pos))
                    .. "  " .. clr("#446688", coords))
            elseif ap then
                lines[#lines+1] = clr("#88CCFF",
                    S("[ATC] Nearest: [@1] @2 — @3m", ap.id, ap.name, tostring(math.floor(d_ap))))
            else
                lines[#lines+1] = clr("#FFAA44", S("[ATC] No airport registered."))
            end

            -- Show nearest independent strip if it exists AND is closer than the airport
            if nearest_st and d_st < (d_ap or math.huge) then
                local sc = nearest_st._center
                local coords = string.format("(%.0f, %.0f, %.0f)", sc.x, sc.y, sc.z)
                local strip_name = nearest_st.name or "?"
                local d_str = tostring(math.floor(d_st))
                lines[#lines+1] = clr("#FFAA44",
                    S("[ATC] Nearest independent runway: @1 — @2m — @3",
                        strip_name, d_str, card_dir(sc))
                    .. "  " .. clr("#664422", coords))
            end

            for _, l in ipairs(lines) do minetest.chat_send_player(name, l) end
            return true
        end

        -- /atc navigate <ID>
        if args[1] and args[1]:lower() == "navigate" then
            local nav_id = args[2] and args[2]:upper()
            local ppos = player:get_pos()
            local nav_ap
            if nav_id then
                nav_ap = find_ap(nav_id)
                if not nav_ap then
                    return false, clr("#FF4444", S("[ATC] Airport '@1' unknown.", nav_id))
                end
            else
                nav_ap = nearest_ap(ppos)
                if not nav_ap then
                    return true, clr("#FFAA44", S("[ATC] No airport registered."))
                end
            end
            local lines = {}
            table.insert(lines, clr("#88CCFF", "══ [" .. nav_ap.id .. "] " .. nav_ap.name .. " ══"))
            if nav_ap.pos then
                local d = d2d(ppos, nav_ap.pos)
                local dx = nav_ap.pos.x - ppos.x
                local dz = nav_ap.pos.z - ppos.z
                local angle = math.deg(math.atan2(dx, dz)) % 360
                local dirs = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                              "S","SSO","SO","OSO","O","ONO","NO","NNO"}
                local dir = dirs[math.floor((angle + 11.25) / 22.5) % 16 + 1]
                table.insert(lines, clr("#AADDFF",
                    S("Position") .. string.format(": (%.0f, %.0f, %.0f)", nav_ap.pos.x, nav_ap.pos.y, nav_ap.pos.z)
                    .. "  |  " .. S("Distance") .. string.format(": %.0fm %s", d, dir)))
            end
            if nav_ap.runways and #nav_ap.runways > 0 then
                table.insert(lines, clr("#FFAA44", S("Runways") .. ":"))
                for _, rw in ipairs(nav_ap.runways) do
                    local len = rw_len(rw)
                    local app_info = ""
                    if rw.approaches then
                        local parts = {}
                        for rn, c in pairs(rw.approaches) do table.insert(parts, rn..":"..c) end
                        if #parts > 0 then app_info = "  [" .. S("App") .. ": " .. table.concat(parts, " ") .. "]" end
                    end
                    -- Heading from p1→p2
                    local hdg_str = ""
                    if rw.p1 and rw.p2 then
                        local dx2 = rw.p2.x - rw.p1.x
                        local dz2 = rw.p2.z - rw.p1.z
                        local hdg = math.floor(math.deg(math.atan2(dx2, dz2)) % 360 + 0.5)
                        hdg_str = string.format("  %03d°→%03d°", hdg, (hdg+180)%360)
                    end
                    table.insert(lines, clr("#FFFFFF",
                        string.format("  %-6s  %dm × %dm%s%s", rw.name or "?", len, rw.width or 30, hdg_str, app_info)))
                end
            else
                table.insert(lines, clr("#888888", "  " .. S("No runway registered.")))
            end
            local notams = get_notam(nav_ap.id)
            if #notams > 0 then
                table.insert(lines, clr("#FFFF88", "NOTAM:"))
                for i, l in ipairs(notams) do
                    table.insert(lines, clr("#FFFF88", string.format("  %d. %s", i, l)))
                end
            end
            for _, l in ipairs(lines) do minetest.chat_send_player(name, l) end
            return true
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
            return false, clr("#FF4444", S("[ATC] You must be on board an aircraft."))
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
            landing  = S("landing request"),
            takeoff  = S("takeoff request"),
            flyover  = S("flyover at @1", alt and (alt .. "m/" .. to_ft(alt) .. "ft") or ""),
            approach = S("approach request"),
        }
        return true, clr("#FFFF44",
            "[ATC " .. aid .. "] " .. tf[action] .. " " .. S("sent")
            .. (has and "" or " " .. S("(no active tower)")) .. ".")
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
        local header = clr("#88CCFF", S("NOTAM header @1 @2", "[" .. ap.id .. "]", ap.name))
        minetest.chat_send_player(name, header)
        if #lines == 0 then
            minetest.chat_send_player(name, clr("#888888", "  " .. S("No active NOTAM.")))
        else
            for i, line in ipairs(lines) do
                minetest.chat_send_player(name,
                    clr("#FFFF88", string.format("  %d. %s", i, line)))
            end
        end
        return true
    end,
})

-- =============================================================
-- radar_atc/commands.lua  —  Chat commands /atc and /notam
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

-- =============================================================
--  Helper: strip center + dist computation
-- =============================================================
local function strip_with_center(st, ppos)
    if not (st.p1 and st.p2) then return nil end
    local cx = (st.p1.x + st.p2.x) / 2
    local cy = (st.p1.y + st.p2.y) / 2
    local cz = (st.p1.z + st.p2.z) / 2
    local center = {x=cx, y=cy, z=cz}
    local copy = {}
    for k,v in pairs(st) do copy[k] = v end
    copy._center = center
    copy._dist   = d2d(ppos, center)
    return copy
end

-- Helper: heading string from p1→p2
local function hdg_str(p1, p2)
    if not (p1 and p2) then return "" end
    local dx = p2.x - p1.x
    local dz = p2.z - p1.z
    local h = math.floor(math.deg(math.atan2(dx, dz)) % 360 + 0.5)
    return string.format("%03d°↔%03d°", h, (h+180)%360)
end

-- Helper: cardinal direction from ppos to target
local _dir_labels = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                     "S","SSO","SO","OSO","O","ONO","NO","NNO"}
local function card_dir(ppos, target)
    local angle = math.deg(math.atan2(target.x - ppos.x, target.z - ppos.z)) % 360
    return _dir_labels[math.floor((angle + 11.25) / 22.5) % 16 + 1]
end

-- =============================================================
--  Stored IR list per player (for /atc navigate IR <n>)
--  We always recompute sorted-by-distance on demand,
--  so /atc navigate IR <n> works even without prior list call.
-- =============================================================
local function get_sorted_strips(ppos)
    local result = {}
    for _, st in ipairs(get_strips()) do
        local s = strip_with_center(st, ppos)
        if s then table.insert(result, s) end
    end
    table.sort(result, function(a,b) return a._dist < b._dist end)
    return result
end

-- =============================================================
--  /atc command
-- =============================================================
minetest.register_chatcommand("atc", {
    params = "<airport_ID|airport|navigate> <landing|takeoff|flyover|approach|msg> [param]",
    description = S("ATC tower communication.\n  /atc airport -- nearest registered airport and independent runway\n  /atc navigate [ID] -- navigation info for an airport (runways, headings, coords)\n  /atc navigate IR -- list the 10 nearest independent runways (numbered)\n  /atc navigate IR <n> -- full details for independent runway number <n>\n  /atc navigate RIR -- mixed list: airports and independent runways (10 nearest)\n  /atc <ID> landing -- request landing clearance\n  /atc <ID> takeoff -- request takeoff clearance\n  /atc <ID> flyover <alt_m> -- request flyover at given altitude (metres)\n  /atc <ID> approach -- request approach instructions\n  /atc <ID> msg <text> -- free radio message to the tower\n  All commands except airport and navigate require being on board an aircraft."),
    func = function(name, param)
        local args = {}
        for w in param:gmatch("%S+") do table.insert(args, w) end
        local player = minetest.get_player_by_name(name)
        if not player then return false, S("Player not found.") end
        local ppos = player:get_pos()

        -- ── /atc airport ────────────────────────────────────────
        if args[1] and args[1]:lower() == "airport" then
            local ap, d_ap = nearest_ap(ppos)

            local nearest_st, d_st = nil, math.huge
            for _, st in ipairs(get_strips()) do
                local s = strip_with_center(st, ppos)
                if s and s._dist < d_st then
                    nearest_st = s; d_st = s._dist
                end
            end

            local lines = {}
            if ap and ap.pos then
                local coords = string.format("(%.0f, %.0f, %.0f)", ap.pos.x, ap.pos.y, ap.pos.z)
                lines[#lines+1] = clr("#88CCFF",
                    S("[ATC] Nearest: [@1] @2 — @3m — @4",
                        ap.id, ap.name, tostring(math.floor(d_ap)), card_dir(ppos, ap.pos))
                    .. "  " .. clr("#446688", coords))
            elseif ap then
                lines[#lines+1] = clr("#88CCFF",
                    S("[ATC] Nearest: [@1] @2 — @3m", ap.id, ap.name, tostring(math.floor(d_ap))))
            else
                lines[#lines+1] = clr("#FFAA44", S("[ATC] No airport registered."))
            end

            if nearest_st then
                local sc = nearest_st._center
                local coords = string.format("(%.0f, %.0f, %.0f)", sc.x, sc.y, sc.z)
                lines[#lines+1] = clr("#FFAA44",
                    S("[ATC] Nearest independent runway: @1 — @2m — @3",
                        nearest_st.name or "?", tostring(math.floor(d_st)), card_dir(ppos, sc))
                    .. "  " .. clr("#664422", coords))
            end

            for _, l in ipairs(lines) do minetest.chat_send_player(name, l) end
            return true
        end

        -- ── /atc navigate ────────────────────────────────────────
        if args[1] and args[1]:lower() == "navigate" then
            local sub = args[2] and args[2]:upper()

            -- ── /atc navigate IR [n] ─────────────────────────────
            if sub == "IR" then
                local num = tonumber(args[3])
                local sorted = get_sorted_strips(ppos)

                -- /atc navigate IR <n>  →  full details of strip #n
                if num then
                    if #sorted == 0 then
                        return true, clr("#FFAA44", S("[ATC] No independent runway registered."))
                    end
                    if num < 1 or num > #sorted then
                        return false, clr("#FF4444",
                            S("[ATC] IR number out of range. Use 1 to @1.", tostring(#sorted)))
                    end
                    local st = sorted[num]
                    local sc = st._center
                    local lines = {}
                    local title = (st.name or ("IR #"..num))
                    table.insert(lines, clr("#FFAA44",
                        "══ IR #" .. num .. " — " .. title .. " ══"))
                    -- distance & direction
                    local d = d2d(ppos, sc)
                    local dx = sc.x - ppos.x
                    local dz = sc.z - ppos.z
                    local ang = math.deg(math.atan2(dx, dz)) % 360
                    local dir = _dir_labels[math.floor((ang + 11.25) / 22.5) % 16 + 1]
                    table.insert(lines, clr("#AAFFCC",
                        S("Position") .. string.format(": (%.0f, %.0f, %.0f)", sc.x, sc.y, sc.z)
                        .. "  |  " .. S("Distance") .. string.format(": %.0fm %s", d, dir)))
                    -- geometry
                    if st.p1 and st.p2 then
                        local len = rw_len(st)
                        local w   = st.width or 30
                        local hs  = hdg_str(st.p1, st.p2)
                        table.insert(lines, clr("#FFFFFF",
                            string.format("  %s: %dm  |  %s: %dm  |  %s: %s",
                                S("Length"), len, S("Width"), w, S("Heading"), hs)))
                        table.insert(lines, clr("#AAAAAA",
                            string.format("  P1: (%.0f, %.0f, %.0f)  →  P2: (%.0f, %.0f, %.0f)",
                                st.p1.x, st.p1.y, st.p1.z, st.p2.x, st.p2.y, st.p2.z)))
                    end
                    if st.note and st.note ~= "" then
                        table.insert(lines, clr("#FFFF88", "  " .. S("Note") .. ": " .. st.note))
                    end
                    for _, l in ipairs(lines) do minetest.chat_send_player(name, l) end
                    return true
                end

                -- /atc navigate IR  →  numbered list of up to 10 nearest strips
                if #sorted == 0 then
                    return true, clr("#FFAA44", S("[ATC] No independent runway registered."))
                end
                local top = math.min(10, #sorted)
                minetest.chat_send_player(name, clr("#FFAA44",
                    S("[ATC] Independent runways — @1 nearest:", tostring(top))))
                minetest.chat_send_player(name, clr("#888888",
                    S("  Use /atc navigate IR <n> for full details.")))
                for i = 1, top do
                    local st = sorted[i]
                    local hs = hdg_str(st.p1, st.p2)
                    local note_s = (st.note and st.note ~= "") and ("  [" .. st.note .. "]") or ""
                    minetest.chat_send_player(name, clr("#FFCC88",
                        string.format("  %2d. %-20s  %5dm  %s  %s%s",
                            i, (st.name or "?"), st._dist,
                            card_dir(ppos, st._center), hs, note_s)))
                end
                return true
            end

            -- ── /atc navigate RIR ─────────────────────────────────
            -- Mixed list: airports + independent runways, sorted by distance
            if sub == "RIR" then
                local entries = {}

                -- Airports
                for _, ap in ipairs(get_airports()) do
                    if ap.pos then
                        local d = d2d(ppos, ap.pos)
                        table.insert(entries, {
                            kind  = "AP",
                            name  = "[" .. ap.id .. "] " .. (ap.name or ap.id),
                            dist  = d,
                            pos   = ap.pos,
                            id    = ap.id,
                        })
                    end
                end

                -- Independent strips
                for _, st in ipairs(get_sorted_strips(ppos)) do
                    table.insert(entries, {
                        kind  = "IR",
                        name  = st.name or "?",
                        dist  = st._dist,
                        pos   = st._center,
                        hdg   = (st.p1 and st.p2) and hdg_str(st.p1, st.p2) or "",
                        len   = rw_len(st),
                        note  = st.note or "",
                    })
                end

                table.sort(entries, function(a,b) return a.dist < b.dist end)

                if #entries == 0 then
                    return true, clr("#FFAA44", S("[ATC] No airport or independent runway registered."))
                end

                local top = math.min(10, #entries)
                minetest.chat_send_player(name, clr("#88CCFF",
                    S("[ATC] Nearest airports and runways — @1 results:", tostring(top))))
                minetest.chat_send_player(name, clr("#888888",
                    S("  [AP] = registered airport  |  [IR] = independent runway")))

                for i = 1, top do
                    local e = entries[i]
                    local tag_clr = (e.kind == "AP") and "#88CCFF" or "#FFAA44"
                    local tag = "[" .. e.kind .. "]"
                    local dir = card_dir(ppos, e.pos)
                    local extra = ""
                    if e.kind == "IR" then
                        extra = "  " .. e.hdg
                        if e.note and e.note ~= "" then extra = extra .. "  [" .. e.note .. "]" end
                    end
                    minetest.chat_send_player(name,
                        clr(tag_clr, string.format("  %2d. %s %-28s  %5dm  %s%s",
                            i, tag, e.name, e.dist, dir, extra)))
                end
                return true
            end

            -- ── /atc navigate [ID]  →  full airport nav info ──────
            local nav_id = sub  -- already :upper()'d
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
                local ang = math.deg(math.atan2(nav_ap.pos.x - ppos.x, nav_ap.pos.z - ppos.z)) % 360
                local dirs = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                              "S","SSO","SO","OSO","O","ONO","NO","NNO"}
                local dir = dirs[math.floor((ang + 11.25) / 22.5) % 16 + 1]
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
                    local hs = hdg_str(rw.p1, rw.p2)
                    table.insert(lines, clr("#FFFFFF",
                        string.format("  %-6s  %dm × %dm  %s%s",
                            rw.name or "?", len, rw.width or 30, hs, app_info)))
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

        -- ── /atc <ID> <action> ───────────────────────────────────
        local aid    = args[1] and args[1]:upper()
        local action = args[2] and args[2]:lower()
        if not aid or not action then
            return false, S("Usage: /atc <ID|airport|navigate> <action> [param]")
        end

        local ap = find_ap(aid)
        if not ap then
            return false, clr("#FF4444", S("[ATC] Airport '@1' unknown. Try /atc airport", aid))
        end

        local ok, model, owner = in_aircraft(name)
        if not ok then
            return false, clr("#FF4444", S("[ATC] You must be on board an aircraft."))
        end

        if action == "msg" then
            local txt = table.concat(args, " ", 3):match("^%s*(.-)%s*$")
            if txt == "" then
                return false, S("Usage: /atc @1 msg <text>", aid)
            end
            push_radio(aid, name, txt)
            return true, clr("#FFFF44", S("[ATC @1] Radio message sent.", aid))
        end

        local valid = {landing=true, takeoff=true, flyover=true, approach=true}
        if not valid[action] then
            return false, S("Invalid action. Valid: landing, takeoff, flyover, approach, msg")
        end

        local alt = tonumber(args[3])
        if action == "flyover" and not alt then
            return false, S("Specify altitude: /atc @1 flyover 500", aid)
        end

        local state = get_shared_atc(aid)
        state.requests = state.requests or {}

        for _, r in ipairs(state.requests) do
            if r.player == name and r.req_type == action and (os.time() - (r.time or 0)) < CFG.req_cmd_cooldown then
                return false, clr("#FFAA44", S("[ATC] Request already sent, please wait."))
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
--  /notam command
-- =============================================================
minetest.register_chatcommand("notam", {
    params = "<airport_ID|nearest>",
    description = S("Consult pilot notices (NOTAM) for an airport.\n  /notam <ID> -- shows NOTAM for the airport\n  /notam nearest -- shows NOTAM for the nearest airport"),
    func = function(name, param)
        local arg = param:match("^%s*(.-)%s*$")
        if arg == "" then
            return false, S("Usage: /notam <airport_ID> or /notam nearest")
        end

        local ap
        if arg:lower() == "nearest" then
            local player = minetest.get_player_by_name(name)
            if not player then return false, S("Player not found.") end
            ap = nearest_ap(player:get_pos())
            if not ap then
                return true, clr("#FFAA44", S("[NOTAM] No airport registered."))
            end
        else
            ap = find_ap(arg:upper())
            if not ap then
                return false, clr("#FF4444", S("[NOTAM] Airport '@1' unknown.", arg:upper()))
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

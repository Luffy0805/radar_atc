-- =============================================================
-- radar_atc/commands.lua  —  Commandes chat /atc
-- =============================================================

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
    params = "<ID_aéroport|airport> <landing|takeoff|flyover|approach|msg> [param]",
    description = table.concat({
        "Communication avec la tour de contrôle ATC.",
        "  /atc airport               — affiche l'aéroport enregistré le plus proche",
        "  /atc <ID> landing          — demande d'autorisation d'atterrissage",
        "  /atc <ID> takeoff          — demande d'autorisation de décollage",
        "  /atc <ID> flyover <alt_m>  — demande de survol à l'altitude indiquée (en mètres)",
        "  /atc <ID> approach         — demande d'instructions d'approche",
        "  /atc <ID> msg <texte>      — message radio libre vers la tour",
        "Toutes les commandes (sauf 'airport') nécessitent d'être à bord d'un avion.",
    }, "\n"),
    func = function(name, param)
        local args = {}
        for w in param:gmatch("%S+") do table.insert(args, w) end
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Joueur introuvable." end

        -- /atc airport
        if args[1] and args[1]:lower() == "airport" then
            local ap, d = nearest_ap(player:get_pos())
            if ap then
                return true, clr("#88CCFF",
                    string.format("[ATC] Plus proche : [%s] %s — %dm", ap.id, ap.name, math.floor(d)))
            end
            return true, clr("#FFAA44", "[ATC] Aucun aéroport enregistré.")
        end

        local aid    = args[1] and args[1]:upper()
        local action = args[2] and args[2]:lower()
        if not aid or not action then
            return false, "Usage : /atc <ID|airport> <landing|takeoff|flyover|approach|msg> [param]"
        end

        local ap = find_ap(aid)
        if not ap then
            return false, clr("#FF4444", "[ATC] '" .. aid .. "' inconnu. Essayez /atc airport")
        end

        local ok, model, owner = in_aircraft(name)
        if not ok then
            return false, clr("#FF4444", "[ATC] Vous devez être à bord d'un avion.")
        end

        if action == "msg" then
            local txt = table.concat(args, " ", 3):match("^%s*(.-)%s*$")
            if txt == "" then return false, "Usage : /atc " .. aid .. " msg <texte>" end
            push_radio(aid, name, txt)
            return true, clr("#FFFF44", "[ATC " .. aid .. "] Message radio envoyé.")
        end

        local valid = {landing=true, takeoff=true, flyover=true, approach=true}
        if not valid[action] then
            return false, "Action invalide : landing, takeoff, flyover, approach, msg"
        end

        local alt = tonumber(args[3])
        if action == "flyover" and not alt then
            return false, "Précisez l'altitude : /atc " .. aid .. " flyover 500"
        end

        local state = get_shared_atc(aid)
        state.requests = state.requests or {}

        -- Anti-doublon
        for _, r in ipairs(state.requests) do
            if r.player == name and r.req_type == action and (os.time() - (r.time or 0)) < CFG.req_cmd_cooldown then
                return false, clr("#FFAA44", "[ATC] Demande déjà envoyée, patientez.")
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
            landing  = "d'atterrissage",
            takeoff  = "de décollage",
            flyover  = "de survol" .. (alt and (" à " .. alt .. "m/" .. to_ft(alt) .. "ft") or ""),
            approach = "d'approche",
        }
        return true, clr("#FFFF44",
            "[ATC " .. aid .. "] Demande " .. tf[action] .. " envoyée"
            .. (has and "" or " (aucune tour active)") .. ".")
    end,
})

-- =============================================================
--  COMMANDE /notam  —  Consultation des avis aux pilotes
-- =============================================================
minetest.register_chatcommand("notam", {
    params = "<ID_aéroport>",
    description = table.concat({
        "Consulter les NOTAM (avis aux pilotes) d'un aéroport.",
        "  /notam <ID>     — affiche les NOTAM de l'aéroport",
        "  /notam nearest  — affiche les NOTAM de l'aéroport le plus proche",
    }, "\n"),
    func = function(name, param)
        local arg = param:match("^%s*(.-)%s*$")
        if arg == "" then
            return false, "Usage : /notam <ID_aéroport> ou /notam nearest"
        end

        local ap
        if arg:lower() == "nearest" then
            local player = minetest.get_player_by_name(name)
            if not player then return false, "Joueur introuvable." end
            ap = nearest_ap(player:get_pos())
            if not ap then
                return true, clr("#FFAA44", "[NOTAM] Aucun aéroport enregistré.")
            end
        else
            ap = find_ap(arg:upper())
            if not ap then
                return false, clr("#FF4444", "[NOTAM] Aéroport '" .. arg:upper() .. "' inconnu.")
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

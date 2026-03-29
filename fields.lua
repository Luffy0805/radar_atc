-- =============================================================
-- radar_atc/fields.lua  —  Gestion des événements formspec (receive_fields)
-- =============================================================

function do_fields(app, mtos, sender, fields)
    local data = mtos.bdev:get_app_storage('ram', 'radar')
    data.tab        = data.tab        or "radar"
    data.radius     = data.radius     or CFG.default_radius
    data.planes     = data.planes     or {}
    data.trails     = data.trails     or {}
    data.center_pos = data.center_pos or {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
    data.selected   = data.selected   or 0
    data.av         = data.av         or "list"
    data.atc_sub    = data.atc_sub    or "requests"

    local linked = data.active_airport or data.linked_airport

    -- Onglets
    for _, t in ipairs({"radar","myap","atc","admin"}) do
        if fields["tab_" .. t] then
            if data.tab == "admin" and t ~= "admin" then
                data.admin_ok = false; data.admin_err = nil
            end
            if t == "admin" then data.admin_ok = false; data.admin_err = nil end
            data.tab = t
            return true
        end
    end

    -- ===== RADAR =====
    if data.tab == "radar" then
        for i = 1, #data.planes + 1 do
            if fields["btn_sel_" .. i] then
                data.selected = (data.selected == i) and 0 or i
                return true
            end
        end
        if fields.dd_radius then
            local v = tonumber(fields.dd_radius)
            if v then
                data.radius = v; data.selected = 0
                data.planes, data.trails = scan(
                    data.remote_center or data.center_pos,
                    data.radius, data.planes, data.trails, linked)
            end
            return true
        end
    end

    -- ===== AÉROPORTS =====
    if data.tab == "myap" then
        -- Initialiser myap_view si absent
        if not data.myap_view then
            local airports = get_airports()
            local linked_id = data.linked_airport
            data.myap_view = linked_id or (airports[1] and airports[1].id)
        end

        -- IMPORTANT : traiter les actions de contrôle EN PREMIER,
        -- avant myap_sel qui fait return true et coupe le traitement.
        -- Minetest envoie TOUS les fields en même temps, donc si on
        -- traite myap_sel en premier avec return true, ctrl_request
        -- n'est jamais vu.

        if fields.ctrl_request then
            -- Ouvre le formulaire mot de passe pour l'aéroport affiché
            -- Mettre à jour myap_view depuis le dropdown s'il est envoyé simultanément
            if fields.myap_sel then
                local raw = fields.myap_sel or ""
                local nv  = raw:match("^([A-Z0-9%-]+)") or raw:match("^(.-)%s*%—") or raw:sub(1,6)
                nv = nv:match("^%s*(.-)%s*$")  -- trim
                if nv ~= "" then data.myap_view = nv:upper() end
            end
            data.myap_ctrl_mode = data.myap_view
            data.myap_ctrl_err  = nil
            return true
        end

        if fields.ctrl_cancel then
            data.myap_ctrl_mode = nil
            data.myap_ctrl_err  = nil
            return true
        end

        if fields.ctrl_confirm then
            if fields.ctrl_pw == CFG.radar_password_remote then
                local view = data.myap_ctrl_mode
                local ap   = find_ap(view)
                if ap and ap.pos then
                    data.active_airport = view
                    data.remote_center  = {x=ap.pos.x, y=ap.pos.y, z=ap.pos.z}
                    active_nodes[pk(mtos.pos)] = {
                        pos        = {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z},
                        airport_id = view,
                    }
                end
                data.myap_ctrl_mode = nil
                data.myap_ctrl_err  = nil
                data.tab = "radar"
            else
                data.myap_ctrl_err = "Mot de passe incorrect."
            end
            return true
        end

        if fields.ctrl_return then
            data.active_airport = data.linked_airport
            data.remote_center  = nil
            active_nodes[pk(mtos.pos)] = {
                pos        = {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z},
                airport_id = data.linked_airport,
            }
            data.tab = "radar"
            return true
        end

        -- Changement de dropdown (traité en dernier dans ce bloc)
        if fields.myap_sel then
            local raw = fields.myap_sel or ""
            -- Le dropdown envoie "LFPG — Nom..." : extraire l'ID avant " — "
            local nv = raw:match("^([A-Z0-9%-]+)") or raw:match("^(.-)%s*%—") or raw:sub(1,6)
            nv = nv:match("^%s*(.-)%s*$"):upper()
            if nv ~= data.myap_view then
                data.myap_ctrl_mode = nil
                data.myap_ctrl_err  = nil
            end
            data.myap_view = nv
            return true
        end
    end

    -- ===== ADMIN =====
    if data.tab == "admin" then
        if fields.admin_login then
            if fields.admin_pw == CFG.radar_password_admin then
                data.admin_ok = true; data.admin_err = nil; data.av = "list"
            else data.admin_err = "Mot de passe incorrect." end
            return true
        end
        if not data.admin_ok then return true end

        if fields.av_back then
            if     data.av == "new_ap"  then data.av = "list"; data.ai = nil
            elseif data.av == "rw_list" then data.av = "list"; data.ai = nil
            elseif data.av == "new_rw"  then data.av = "rw_list"
            else   data.av = "list" end
            return true
        end
        if fields.new_ap then
            data.av = "new_ap"
            data.n_ap_id = ""; data.n_ap_name = ""
            data.n_ap_x = ""; data.n_ap_y = ""; data.n_ap_z = ""
            data.n_ap_err = nil
            return true
        end
        if fields.ap_create then
            data.n_ap_id   = fields.ap_id   or data.n_ap_id   or ""
            data.n_ap_name = fields.ap_name or data.n_ap_name or ""
            data.n_ap_x    = fields.ap_px   or data.n_ap_x    or ""
            data.n_ap_y    = fields.ap_py   or data.n_ap_y    or ""
            data.n_ap_z    = fields.ap_pz   or data.n_ap_z    or ""
            local id = (data.n_ap_id):upper():gsub("[^A-Z0-9]", ""):sub(1, 6)
            if #id == 0 then data.n_ap_err = "Identifiant obligatoire."; return true end
            if #(data.n_ap_name or "") == 0 then data.n_ap_err = "Nom obligatoire."; return true end
            if find_ap(id) then data.n_ap_err = "ID '" .. id .. "' déjà utilisé."; return true end
            local px = tonumber(data.n_ap_x); local pv = tonumber(data.n_ap_y); local pz = tonumber(data.n_ap_z)
            local pos = (px and pv and pz) and {x=px, y=pv, z=pz}
                       or {x=mtos.pos.x, y=mtos.pos.y, z=mtos.pos.z}
            local airports = get_airports()
            table.insert(airports, {id=id, name=data.n_ap_name, pos=pos, runways={}})
            save_airports()
            data.av = "list"; data.n_ap_err = nil
            return true
        end
        for i = 1, 60 do
            if fields["ap_del_" .. i] then
                local airports = get_airports()
                if airports[i] then table.remove(airports, i); save_airports() end
                data.av = "list"; return true
            end
            if fields["ap_rw_" .. i] then
                data.av = "rw_list"; data.ai = i; return true
            end
        end
        if fields.new_rw then
            data.av = "new_rw"; data.n_rw_err = nil
            data.n_rw_suf = ""; data.n_rw_wid = "30"
            data.n_rw_app1 = ""; data.n_rw_app2 = ""
            for _, k in ipairs({"p1x","p1y","p1z","p2x","p2y","p2z"}) do data["n_rw_" .. k] = "" end
            return true
        end
        if fields.rw_create and data.ai then
            data.n_rw_suf  = fields.rw_suf  or data.n_rw_suf  or ""
            data.n_rw_wid  = fields.rw_wid  or data.n_rw_wid  or "30"
            data.n_rw_app1 = fields.rw_app1 or data.n_rw_app1 or ""
            data.n_rw_app2 = fields.rw_app2 or data.n_rw_app2 or ""
            for _, k in ipairs({"p1x","p1y","p1z","p2x","p2y","p2z"}) do
                data["n_rw_" .. k] = fields["rw_" .. k] or data["n_rw_" .. k] or ""
            end
            local function rn(k) return tonumber(data["n_rw_" .. k]) end
            local p1x, p1y, p1z = rn("p1x"), rn("p1y"), rn("p1z")
            local p2x, p2y, p2z = rn("p2x"), rn("p2y"), rn("p2z")
            if not (p1x and p1y and p1z and p2x and p2y and p2z) then
                data.n_rw_err = "Toutes les coordonnées sont requises."; return true
            end
            local p1 = {x=p1x, y=p1y, z=p1z}; local p2 = {x=p2x, y=p2y, z=p2z}
            local suf  = (data.n_rw_suf or ""):upper():gsub("[^LRC]", ""):sub(1, 1)
            local name = rwy_name(p1, p2, suf)
            local parts = {}
            for pn in name:gmatch("[^/]+") do table.insert(parts, pn) end
            local approaches = {}
            local app1 = (data.n_rw_app1 or ""):match("^%s*(.-)%s*$")
            local app2 = (data.n_rw_app2 or ""):match("^%s*(.-)%s*$")
            if app1 ~= "" and parts[1] then approaches[parts[1]] = app1 end
            if app2 ~= "" and parts[2] then approaches[parts[2]] = app2 end
            local airports = get_airports()
            local ap = airports[data.ai]
            if not ap then data.av = "list"; return true end
            ap.runways = ap.runways or {}
            table.insert(ap.runways, {
                name = name, width = tonumber(data.n_rw_wid) or 30,
                p1 = p1, p2 = p2,
                approaches = (next(approaches) and approaches or nil),
            })
            save_airports()
            data.av = "rw_list"; data.n_rw_err = nil
            return true
        end
        if data.ai then
            for ri = 1, 40 do
                if fields["rw_del_" .. ri] then
                    local airports = get_airports()
                    local ap = airports[data.ai]
                    if ap and ap.runways and ap.runways[ri] then
                        table.remove(ap.runways, ri); save_airports()
                    end
                    return true
                end
            end
        end
    end

    -- ===== ATC =====
    if data.tab == "atc" then
        if fields.atcsub_req then data.atc_sub = "requests"; return true end
        if fields.atcsub_rad then data.atc_sub = "radio";    return true end

        local state = get_shared_atc(linked)
        local reqs  = state.requests or {}
        local convs = state.conversations or {}

        -- Helper : préfixe ATC court pour les messages chat joueurs
        local atc_prefix = "[ATC " .. (linked or "?") .. "]"

        -- Requêtes
        for ri = 1, #reqs do
            local req = reqs[ri]
            if not req then break end

            if fields["atc_alt_set_" .. ri] then
                local v = tonumber(fields["atc_alt_" .. ri])
                if v and v > 0 then req.alt = math.floor(v) end
                save_shared_atc(linked, state)
                return true
            end

            -- Auth piste individuelle
            local rw_done = false
            for rwi = 1, 20 do
                local ap = linked and find_ap(linked)
                local rw = ap and ap.runways and ap.runways[rwi]
                if rw then
                    local parts = {}
                    for pn in (rw.name or ""):gmatch("[^/]+") do table.insert(parts, pn) end
                    for _, pn in ipairs(parts) do
                        if fields["atc_rw_" .. ri .. "_" .. rwi .. "_" .. pn] then
                            local verb = req.req_type == "landing" and "Atterrissage" or "Décollage"
                            minetest.chat_send_player(req.player,
                                clr("#00FF88", atc_prefix .. " " .. verb .. " autorisé — Piste " .. pn))
                            table.remove(reqs, ri)
                            state.requests = reqs
                            save_shared_atc(linked, state)
                            rw_done = true; break
                        end
                    end
                    if rw_done then break end
                end
            end
            if rw_done then return true end

            -- Auth approche
            for rwi = 1, 20 do
                local ap = linked and find_ap(linked)
                local rw = ap and ap.runways and ap.runways[rwi]
                if rw then
                    local parts = {}
                    for pn in (rw.name or ""):gmatch("[^/]+") do table.insert(parts, pn) end
                    for _, pn in ipairs(parts) do
                        if fields["atc_app_" .. ri .. "_" .. rwi .. "_" .. pn] then
                            local coords = rw.approaches and rw.approaches[pn]
                            local msg
                            if coords then
                                local pn_num = tonumber(pn:match("%d+")) or 0
                                local cap_deg = pn_num * 10
                                local dir = cap_to_dir(cap_deg)
                                msg = string.format(
                                    "%s Approche piste %s : cap %s (%.0f°), coords approche %s. "..
                                    "Contactez la tour à l'approche.",
                                    atc_prefix, pn, dir, cap_deg, coords)
                            else
                                local pp = rw.p1 and
                                    string.format("%.0f,%.0f", rw.p1.x, rw.p1.z) or "?"
                                msg = string.format(
                                    "%s Approche piste %s : aucune approche programmée, "..
                                    "référez-vous aux coords de la piste (%s).",
                                    atc_prefix, pn, pp)
                            end
                            minetest.chat_send_player(req.player, clr("#44FFCC", msg))
                            table.remove(reqs, ri)
                            state.requests = reqs
                            save_shared_atc(linked, state)
                            return true
                        end
                    end
                end
            end

            if fields["atc_auth_" .. ri] then
                if req.req_type == "flyover" then
                    local alt = req.alt or 500
                    minetest.chat_send_player(req.player,
                        clr("#00FF88", atc_prefix .. " Survol autorisé à "
                            .. alt .. "m / " .. to_ft(alt) .. "ft"))
                else
                    minetest.chat_send_player(req.player,
                        clr("#00FF88", atc_prefix .. " Autorisé(e)"))
                end
                table.remove(reqs, ri); state.requests = reqs
                save_shared_atc(linked, state)
                return true
            end
            if fields["atc_ref_" .. ri] then
                minetest.chat_send_player(req.player,
                    clr("#FF4444", atc_prefix .. " Refusé — Contactez la tour."))
                table.remove(reqs, ri); state.requests = reqs
                save_shared_atc(linked, state)
                return true
            end
            if fields["atc_hold_" .. ri] then
                if req.status ~= "hold" then
                    req.status = "hold"
                    minetest.chat_send_player(req.player,
                        clr("#FFAA00", atc_prefix .. " En attente — Maintenez votre position."))
                    save_shared_atc(linked, state)
                end
                return true
            end
            if fields["atc_del_" .. ri] then
                table.remove(reqs, ri); state.requests = reqs
                save_shared_atc(linked, state)
                return true
            end
        end

        -- Radio
        for ci = 1, #convs + 1 do
            if fields["radio_sel_" .. ci] then
                data.radio_sel = ci; data.radio_new_mode = false; data.radio_draft = ""
                return true
            end
            if fields["radio_close_" .. ci] then
                table.remove(convs, ci); state.conversations = convs
                save_shared_atc(linked, state)
                if data.radio_sel and data.radio_sel >= ci then
                    data.radio_sel = #convs > 0 and math.max(1, ci - 1) or nil
                end
                return true
            end
            if fields["radio_send_" .. ci] then
                local conv = convs[ci]
                if conv then
                    local txt = (fields["radio_rep_" .. ci] or data.radio_draft or ""):match("^%s*(.-)%s*$")
                    if txt ~= "" then
                        conv.messages = conv.messages or {}
                        table.insert(conv.messages, {from="atc", text=txt, time=os.time()})
                        minetest.chat_send_player(conv.pilot,
                            clr("#00FFFF", atc_prefix .. " " .. txt
                                .. "  (Répondre: /atc " .. (linked or "?") .. " msg <texte>)"))
                        save_shared_atc(linked, state)
                        data.radio_draft = ""
                    end
                end
                return true
            end
        end
        for ci = 1, #convs do
            if fields["radio_rep_" .. ci] then data.radio_draft = fields["radio_rep_" .. ci] end
        end
        if fields.radio_new then
            data.radio_new_mode = true; data.radio_new_target = ""; return true
        end
        if fields.radio_new_cancel then data.radio_new_mode = false; return true end
        if fields.radio_new_target then data.radio_new_target = fields.radio_new_target end
        if fields.radio_new_open then
            local target = (fields.radio_new_target or data.radio_new_target or ""):match("^%s*(.-)%s*$")
            if target ~= "" then
                local idx = nil
                for ci, c in ipairs(convs) do if c.pilot == target then idx = ci; break end end
                if not idx then
                    table.insert(convs, {pilot=target, messages={}})
                    idx = #convs
                    state.conversations = convs
                    save_shared_atc(linked, state)
                end
                data.radio_sel = idx; data.radio_new_mode = false; data.radio_draft = ""
            end
            return true
        end
    end

    return false
end

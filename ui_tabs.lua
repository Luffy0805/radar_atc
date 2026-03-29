-- =============================================================
-- radar_atc/ui_tabs.lua  —  Construction du formspec (onglets + barre)
-- =============================================================

-- =============================================================
--  ONGLET RADAR
-- =============================================================
function tab_radar(data, mtos)
    local cpos   = data.remote_center or data.center_pos or mtos.pos
    local radius = data.radius or CFG.default_radius
    local planes = data.planes or {}
    local sel    = data.selected or 0
    local linked = data.active_airport or data.linked_airport
    local fs     = {}

    local RX, RY, RW, RH = CFG.RX, CFG.RY, CFG.RW, CFG.RH
    local PX, PW = CFG.PX, CFG.PW

    -- Indicateur contrôle distant
    if data.remote_center then
        local rem_ap = find_ap(data.active_airport)
        local rem_nm = rem_ap and ("[" .. rem_ap.id .. "] " .. rem_ap.name) or "?"
        table.insert(fs, string.format(
            "box[%.2f,%.2f;%.2f,0.28;#220022]label[%.2f,%.2f;%s]",
            RX, RY - 0.32, RW, RX + 0.1, RY - 0.00,
            clr("#FF88FF", "⊕ Distant: " .. rem_nm)))
    end

    -- Fond radar
    table.insert(fs, string.format("box[%.2f,%.2f;%.2f,%.2f;#001800]", RX, RY, RW, RH))

    -- Rose des vents
    local cx = RX + RW / 2; local cy = RY + RH / 2
    table.insert(fs, string.format("label[%.2f,%.2f;%s]", cx - 0.08, RY + 0.05, clr("#335533", "N")))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]", cx - 0.08, RY + RH - 0.50, clr("#335533", "S")))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]", RX + 0.05, cy - 0.15, clr("#335533", "O")))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]", RX + RW - 0.28, cy - 0.15, clr("#335533", "E")))
    table.insert(fs, string.format("label[%.2f,%.2f;+]", cx - 0.05, cy - 0.12))

    -- Marques de distance : 4 points cardinaux (pas d'arcs)
    for _, frac in ipairs({1/3, 2/3}) do
        local r = RW / 2 * frac
        for _, a in ipairs({0, 90, 180, 270}) do
            local rad = math.rad(a)
            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                cx + math.sin(rad) * r - 0.04, cy - math.cos(rad) * r - 0.08, clr("#1a3d1a", "·")))
        end
    end

    -- Échelle
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
        RX + 0.1, RY + RH - 0.45, clr("#335533", "R:" .. radius .. "m")))

    -- Pistes de TOUS les aéroports (seulement si dans la portée)
    local airports = get_airports()
    local ap_label_drawn = {}
    for _, ap in ipairs(airports) do
        local is_linked = (ap.id == linked)
        local rw_col = is_linked and "#5566FF" or "#444466"
        local nm_col = is_linked and "#9999FF" or "#666688"
        if ap.runways then
            for _, rw in ipairs(ap.runways) do
                if rw.p1 and rw.p2 then
                    local x1, y1 = w2r(rw.p1, cpos, radius)
                    local x2, y2 = w2r(rw.p2, cpos, radius)
                    if x1 or x2 then
                        x1 = x1 or (x2 and (RW / 2) or nil)
                        y1 = y1 or (y2 and (RH / 2) or nil)
                        x2 = x2 or (RW / 2); y2 = y2 or (RH / 2)
                        for t = 0, 10 do
                            local f = t / 10
                            local ix = x1 + (x2 - x1) * f; local iy = y1 + (y2 - y1) * f
                            if ix >= 0.02 and ix <= RW - 0.20 and iy >= 0.02 and iy <= RH - 0.20 then
                                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                                    RX + ix, RY + iy, clr(rw_col, "·")))
                            end
                        end
                        local xm = (x1 + x2) / 2; local ym = (y1 + y2) / 2
                        if xm >= 0.1 and xm <= RW - 0.5 and ym >= 0.1 and ym <= RH - 0.4 then
                            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                                RX + xm, RY + ym - 0.28, clr(nm_col, rw.name or "?")))
                        end
                        if not is_linked and not ap_label_drawn[ap.id] then
                            if xm >= 0.1 and xm <= RW - 0.8 and ym >= 0.1 and ym <= RH - 0.6 then
                                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                                    RX + xm, RY + ym - 0.52,
                                    clr("#888888", "[" .. ap.id .. "]")))
                                ap_label_drawn[ap.id] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Autres radars actifs
    for key, info in pairs(active_nodes) do
        if key ~= pk(mtos.pos) and info.pos then
            local sx, sy = w2r(info.pos, cpos, radius)
            if sx then
                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                    RX + sx - 0.08, RY + sy - 0.12, clr("#4488CC", "◈")))
            end
        end
    end

    -- Avions + traînées
    for i, p in ipairs(planes) do
        local sx, sy = w2r(p.pos, cpos, radius)
        if sx then
            local col
            if i == sel then col = "#FFAA00"
            elseif p.has_req then col = "#FF3333"
            elseif p.spd_ms and p.spd_ms > 0.5 then col = "#00FF44"
            else col = "#FFFFFF" end

            for ti, tp in ipairs(p.trail or {}) do
                local tx, ty = w2r(tp, cpos, radius)
                if tx then
                    local dim = math.floor(220 - (ti - 1) * 25)
                    local tc
                    if i == sel then
                        tc = string.format("#%02X%02X00", dim, math.floor(dim * 0.67))
                    elseif p.has_req then
                        tc = string.format("#%02X0000", dim)
                    elseif p.spd_ms and p.spd_ms > 0.5 then
                        tc = string.format("#00%02X00", dim)
                    else
                        tc = string.format("#%02X%02X%02X", dim, dim, dim)
                    end
                    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                        RX + tx - 0.05, RY + ty - 0.10, clr(tc, "o")))
                end
            end

            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                RX + sx - 0.07, RY + sy - 0.13, clr(col, "▲")))

            local tag = p.model:sub(1, 5) .. "/" .. p.owner:sub(1, 6)
            local lx = sx - 0.35
            if lx < 0.05 then lx = sx + 0.10 end
            if lx + 1.5 > RW then lx = sx - 1.5 end
            if RY + sy - 0.52 > RY + 0.05 then
                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                    RX + lx, RY + sy - 0.52, clr(col, tag)))
            end
        end
    end

    -- ============ PANNEAU DROIT ============
    local py = CFG.CY

    local ap_obj = find_ap(linked)
    local ap_lbl = ap_obj and ("[" .. ap_obj.id .. "] " .. ap_obj.name) or "Hors aéroport"
    local ap_col = linked and "#88CCFF" or "#FFCC44"
    local ap_bg  = linked and "#002244" or "#222200"
    table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.45;%s]", PX, py, PW, ap_bg))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
        PX + 0.12, py + 0.00, clr(ap_col, ap_lbl)))
    py = py + 0.52

    table.insert(fs, string.format("label[%.2f,%.2f;Portée :]", PX, py + 0.10))
    table.insert(fs, mkdd(PX + 1.90, py, PW - 1.95, "dd_radius", CFG.radius_values, radius))
    py = py + 0.68

    local n = #planes
    table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.38;#001a00]", PX, py, PW))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]", PX + 0.12, py + 0.00,
        clr(n > 0 and "#FFAA00" or "#00FF44",
            n .. " contact" .. (n > 1 and "s" or ""))))
    py = py + 0.45

    -- Fiche avion sélectionné
    if sel > 0 and planes[sel] then
        local p = planes[sel]
        local rows = {}
        table.insert(rows, clr("#FFFF88", "Modèle   : " .. p.model))
        table.insert(rows, "Proprio  : " .. p.owner)
        table.insert(rows, "Pilote   : " .. (p.pilot or "—"))
        table.insert(rows, string.format("Cap      : %d° %s", p.heading, head2card(p.heading)))
        table.insert(rows, "Vitesse  : " .. fmt_spd(p.spd_ms))
        table.insert(rows, "Altitude : " .. fmt_alt(p.alt_m) .. " " .. climb_s(p.climb))
        table.insert(rows, "Distance : " .. p.dist .. "m")
        if p.throttle then
            table.insert(rows, "Gaz      : " .. p.throttle .. "%")
        end
        if p.hp_max and p.hp_max > 0 then
            local pct = math.floor(p.hp * 100 / p.hp_max)
            local hc = pct > 60 and "#00FF44" or (pct > 30 and "#FFAA00" or "#FF4444")
            table.insert(rows, string.format("PV       : %s",
                clr(hc, string.format("%.2f/%.2f (%.0f%%)", p.hp, p.hp_max, pct))))
        end
        if p.fuel then
            local fc = p.fuel > 30 and "#00FF44" or "#FF4444"
            table.insert(rows, "Carburant: " .. clr(fc, p.fuel .. "%"))
        end
        if p.autonomy_min then
            local ac = p.autonomy_min
            local acolor = ac > 60 and "#00FF44" or (ac > 20 and "#FFAA00" or "#FF4444")
            local astr
            if ac >= 60 then
                astr = string.format("%dh%02d", math.floor(ac / 60), ac % 60)
            else
                astr = ac .. " min"
            end
            -- Distance estimée = vitesse actuelle (m/s) × autonomie en secondes
            local dist_km = math.floor(p.spd_ms * ac * 60 / 1000 + 0.5)
            local dist_str = p.spd_ms > 0.5
                and string.format(" ~%dkm", dist_km)
                or " (à l'arrêt)"
            table.insert(rows, "Autonomie: " .. clr(acolor, astr .. dist_str)
                .. " (gaz " .. p.throttle .. "%)")
        elseif p.model == "PA-28" and p.throttle and p.throttle == 0 then
            table.insert(rows, clr("#888888", "Autonomie: moteur coupé"))
        end

        local row_h = 0.38
        local avail_h = CFG.Y_MAX - py - 0.05
        local max_rows = math.floor(avail_h / row_h) - 1
        while #rows > max_rows do table.remove(rows, #rows) end
        local bh = 0.08 + #rows * row_h + 0.08
        table.insert(fs, string.format("box[%.2f,%.2f;%.2f,%.2f;#002800]", PX, py, PW, bh))
        for li, row in ipairs(rows) do
            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                PX + 0.12, py + 0.08 + (li - 1) * row_h, row))
        end
        py = py + bh + 0.06
    else
        table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.36;#001000]", PX, py, PW))
        table.insert(fs, string.format("label[%.2f,%.2f;%s]",
            PX + 0.12, py - 0.02, clr("#448844", "Sélectionner un avion ci-dessous")))
        py = py + 0.43
    end

    -- Liste avions
    if n > 0 then
        table.insert(fs, string.format("label[%.2f,%.2f;%s]",
            PX, py, clr("#88FF88", "Contacts :")))
        py = py + 0.32

        local item_h = 0.44
        local avail = CFG.Y_MAX - py
        local visible = math.floor(avail / item_h)
        local need_scroll = (n > visible)
        local list_h = math.min(n, visible) * item_h

        if need_scroll then
            table.insert(fs, scroll_box(PX, py, PW - 0.28, list_h, "sc_planes"))
        end
        local lpy = need_scroll and 0 or py
        local lpx = need_scroll and 0 or PX

        for i, p in ipairs(planes) do
            local fg = (i == sel) and "#FFAA00" or
                       (p.has_req and "#FF6666" or
                       (p.pilot and "#AAFFAA" or "#FFFFFF"))
            local bg = (i == sel) and "#333300" or "#001500"
            local line = string.format("%-6s %4dm %3dkt %dm%s",
                p.model:sub(1, 6), p.dist, to_kt(p.spd_ms), p.alt_m,
                p.pilot and " [" .. p.pilot .. "]" or "")
            table.insert(fs, string.format("style[btn_sel_%d;bgcolor=%s]", i, bg))
            table.insert(fs, string.format("button[%.2f,%.2f;%.2f,%.2f;btn_sel_%d;%s]",
                lpx, lpy, need_scroll and (PW - 0.28) or PW, item_h, i, fe(clr(fg, line))))
            lpy = lpy + item_h
        end

        if need_scroll then
            table.insert(fs, "scroll_container_end[]")
            table.insert(fs, scroll_bar(PX + PW - 0.26, py, list_h, "sc_planes"))
        end
    end

    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
        RX + 0.10, RY + RH - 0.08,
        clr("#335533", "MAJ: " .. os.date("%H:%M:%S") .. "  T+" .. CFG.timer_interval .. "s")))

    return table.concat(fs)
end

-- =============================================================
--  ONGLET AÉROPORTS
-- =============================================================
function tab_myairport(data, mtos)
    local fs = {}
    local py = CFG.CY
    local airports = get_airports()
    local linked = data.linked_airport

    if #airports == 0 then
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py,
            clr("#888888", "Aucun aéroport. Utilisez l'onglet Admin.")))
        return table.concat(fs)
    end

    local ap_ids = {}; local ap_display = {}
    for _, a in ipairs(airports) do
        table.insert(ap_ids, a.id)
        local disp = a.id .. " — " .. a.name
        if #disp > 30 then disp = disp:sub(1, 28) .. ".." end
        table.insert(ap_display, disp)
    end
    local viewing = data.myap_view
    if not viewing then
        viewing = linked or ap_ids[1]
        for _, id in ipairs(ap_ids) do
            if id ~= linked then viewing = id; break end
        end
    end
    local ok = false
    for _, id in ipairs(ap_ids) do if id == viewing then ok = true; break end end
    if not ok then viewing = ap_ids[1] end

    table.insert(fs, string.format("label[0.20,%.2f;Aéroport :]", py + 0.10))
    local viewing_disp = ap_display[1]
    for i, id in ipairs(ap_ids) do
        if id == viewing then viewing_disp = ap_display[i]; break end
    end
    table.insert(fs, mkdd(2.40, py, 10.0, "myap_sel", ap_display, viewing_disp))
    py = py + 0.68

    local ap = find_ap(viewing)
    if not ap then
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py, clr("#FF4444", "Introuvable.")))
        return table.concat(fs)
    end

    local is_linked = (viewing == linked)
    local is_active = (viewing == data.active_airport)
    local badge = ""
    if is_linked then badge = badge .. clr("#00FF88", " ← lié") end
    if is_active and not is_linked then badge = badge .. clr("#FF88FF", " ← contrôlé") end

    table.insert(fs, string.format("box[0,%.2f;%.2f,0.50;#002244]", py, CFG.X_MAX))
    table.insert(fs, string.format("label[0.20,%.2f;%s]", py + 0.02,
        clr("#88CCFF", "[" .. ap.id .. "] " .. ap.name) .. badge))
    if ap.pos then
        table.insert(fs, string.format("label[10.0,%.2f;%s]", py + 0.02,
            clr("#446688", string.format("(%.0f,%.0f,%.0f)", ap.pos.x, ap.pos.y, ap.pos.z))))
    end
    py = py + 0.58

    -- Zone contrôle
    if is_active and not is_linked then
        table.insert(fs, string.format("button[0.20,%.2f;6.0,0.50;ctrl_return;%s]",
            py, fe(clr("#FFAA00", "⟵ Revenir à l'aéroport lié"))))
        py = py + 0.58
    elseif is_linked and (not data.active_airport or data.active_airport == linked) then
        table.insert(fs, string.format("box[0.20,%.2f;7.0,0.38;#002200]", py))
        table.insert(fs, string.format("label[0.40,%.2f;%s]", py - 0.03,
            clr("#00FF88", "Cet ordinateur contrôle son aéroport d'origine.")))
        py = py + 0.46
    elseif is_linked and data.active_airport and data.active_airport ~= linked then
        table.insert(fs, string.format("button[0.20,%.2f;6.0,0.50;ctrl_return;%s]",
            py, fe(clr("#FFAA00", "⟵ Revenir à cet aéroport lié"))))
        py = py + 0.58
    elseif data.myap_ctrl_mode == viewing then
        table.insert(fs, string.format("box[0.20,%.2f;9.0,2.70;#110022]", py))
        table.insert(fs, string.format("label[0.50,%.2f;%s]", py + 0.02,
            clr("#CC88FF", "Mot de passe requis pour prendre le contrôle de [" .. viewing .. "] :")))
        table.insert(fs, string.format("pwdfield[0.65,%.2f;5.5,0.80;ctrl_pw;Mot de passe]", py + 1.10))
        table.insert(fs, string.format("button[5.85,%.2f;2.7,0.62;ctrl_confirm;Confirmer]", py + 0.86))
        table.insert(fs, string.format("button[0.40,%.2f;2.5,0.50;ctrl_cancel;Annuler]", py + 1.85))
        if data.myap_ctrl_err then
            table.insert(fs, string.format("label[3.10,%.2f;%s]", py + 1.75,
                clr("#FF4444", data.myap_ctrl_err)))
        end
        py = py + 2.72
    else
        table.insert(fs, string.format("button[0.20,%.2f;6.0,0.50;ctrl_request;%s]",
            py, fe(clr("#88FFFF", "⊕ Prendre le contrôle de [" .. viewing .. "]"))))
        py = py + 0.58
    end

    -- Tableau des pistes
    ap.runways = ap.runways or {}
    if #ap.runways == 0 then
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py,
            clr("#888888", "Aucune piste enregistrée.")))
        return table.concat(fs)
    end

    table.insert(fs, string.format("box[0,%.2f;%.2f,0.40;#003355]", py, CFG.X_MAX))
    local hdrs = {{0.20,"Désig."},{2.2,"Long."},{4.0,"Larg."},
                  {5.6,"Coordonnées d'approche par sens"},{12.0,"P1/P2"}}
    for _, h in ipairs(hdrs) do
        table.insert(fs, string.format("label[%.2f,%.2f;%s]", h[1], py + 0.00, clr("#AADDFF", h[2])))
    end
    py = py + 0.46

    local item_h = 0.46
    local avail = CFG.Y_MAX - py
    local need_scroll = (#ap.runways * item_h > avail)
    local list_h = math.min(#ap.runways * item_h, avail)

    if need_scroll then
        table.insert(fs, scroll_box(0, py, CFG.X_MAX - 0.28, list_h, "sc_rw"))
    end

    for _, rw in ipairs(ap.runways) do
        local len = rw_len(rw)
        local p1s = rw.p1 and string.format("%.0f,%.0f,%.0f", rw.p1.x, rw.p1.y, rw.p1.z) or "?"
        local p2s = rw.p2 and string.format("%.0f,%.0f,%.0f", rw.p2.x, rw.p2.y, rw.p2.z) or "?"
        local app_str = "—"
        if rw.approaches then
            local parts = {}
            for rn, coords in pairs(rw.approaches) do
                table.insert(parts, rn .. ":" .. coords)
            end
            if #parts > 0 then app_str = table.concat(parts, "  ") end
        end
        local base_y = need_scroll and 0 or py
        table.insert(fs, string.format("box[0,%.2f;%.2f,%.2f;#001122]",
            base_y, CFG.X_MAX, item_h))
        table.insert(fs, string.format("label[0.20,%.2f;%s]",  base_y + 0.03, clr("#FFFFFF", rw.name or "?")))
        table.insert(fs, string.format("label[2.20,%.2f;%s]",  base_y + 0.03, len .. "m"))
        table.insert(fs, string.format("label[4.00,%.2f;%s]",  base_y + 0.03, (rw.width or 30) .. "m"))
        table.insert(fs, string.format("label[5.60,%.2f;%s]",  base_y + 0.03, clr("#AAAACC", app_str:sub(1, 28))))
        table.insert(fs, string.format("label[12.00,%.2f;%s]", base_y + 0.03,
            clr("#555577", p1s:sub(1, 12) .. "|" .. p2s:sub(1, 12))))
        if need_scroll then base_y = base_y + item_h end
        py = py + item_h
    end
    if need_scroll then
        table.insert(fs, "scroll_container_end[]")
        table.insert(fs, scroll_bar(CFG.X_MAX - 0.26, py - list_h - 0.46, list_h, "sc_rw"))
    end

    return table.concat(fs)
end

-- =============================================================
--  ONGLET ATC
-- =============================================================
function tab_atc(data, mtos)
    local fs = {}
    local py = CFG.CY
    local linked = data.active_airport or data.linked_airport
    local state  = get_shared_atc(linked)
    local reqs   = state.requests or {}
    local convs  = state.conversations or {}
    local sub    = data.atc_sub or "requests"

    local hbg = linked and "#1a0000" or "#222222"
    local hfg = linked and "#FF8888" or "#888888"
    local linked_ap_obj  = linked and find_ap(linked)
    local linked_display = linked_ap_obj
        and ("[" .. linked_ap_obj.id .. "] " .. linked_ap_obj.name)
        or (linked or "(non lié à un aéroport)")
    table.insert(fs, string.format("box[0,%.2f;%.2f,0.40;%s]", py, CFG.X_MAX, hbg))
    table.insert(fs, string.format("label[0.20,%.2f;%s]", py - 0.06,
        clr(hfg, "ATC — " .. linked_display)))
    py = py + 0.46

    -- Sous-onglets
    local nl, nh = 0, 0
    for _, r in ipairs(reqs) do
        if r.status == "hold" then nh = nh + 1 else nl = nl + 1 end
    end
    local lq = "Demandes" .. (nl > 0 and " [" .. nl .. "]" or "") .. (nh > 0 and " (" .. nh .. "⏸)" or "")
    local lr = "Radio" .. (#convs > 0 and " [" .. #convs .. "]" or "")
    table.insert(fs, string.format("box[0,%.2f;7.10,0.46;%s]", py,
        sub == "requests" and "#004400" or "#002200"))
    table.insert(fs, string.format("button[0,%.2f;7.10,0.46;atcsub_req;%s]", py,
        fe(clr(sub == "requests" and "#FFFFFF" or "#88FF88", lq))))
    table.insert(fs, string.format("box[7.20,%.2f;7.60,0.46;%s]", py,
        sub == "radio" and "#004400" or "#002200"))
    table.insert(fs, string.format("button[7.20,%.2f;7.60,0.46;atcsub_rad;%s]", py,
        fe(clr(sub == "radio" and "#FFFFFF" or "#88FF88", lr))))
    py = py + 0.52

    -- ===================== DEMANDES =====================
    if sub == "requests" then
        if #reqs == 0 then
            table.insert(fs, string.format("label[0.20,%.2f;%s]", py,
                clr("#446644", "Aucune demande en attente.")))
            return table.concat(fs)
        end

        local item_h_base = 1.60
        local avail = CFG.Y_MAX - py
        local need_scroll = (#reqs * item_h_base > avail)
        local list_h = math.min(#reqs * item_h_base, avail - 0.05)

        if need_scroll then
            table.insert(fs, scroll_box(0, py, CFG.X_MAX - 0.28, list_h, "sc_atc"))
        end

        local rpy = need_scroll and 0 or py

        for ri, req in ipairs(reqs) do
            local age = os.time() - (req.time or 0)
            local bg, fg
            if req.status == "hold" then bg = "#1a1a00"; fg = "#CCCC00"
            elseif age < 60 then         bg = "#1a0000"; fg = "#FFFF44"
            else                         bg = "#111111"; fg = "#888888" end

            local tlab = {landing="Atterrissage", takeoff="Décollage", flyover="Survol", approach="Approche"}
            local det = tlab[req.req_type] or req.req_type
            if req.req_type == "flyover" and req.alt then
                det = det .. " " .. req.alt .. "m/" .. to_ft(req.alt) .. "ft"
            end
            local stat = req.status == "hold" and "⏸" or "★"

            -- Nom complet de l'aéroport concerné
            local ap_obj_req = find_ap(req.airport)
            local ap_disp_req = ap_obj_req and (ap_obj_req.name .. " [" .. req.airport .. "]") or (req.airport or "?")

            local age_str = age < 60 and (age .. "s") or (math.floor(age / 60) .. "min " .. age % 60 .. "s")
            -- Ligne unique : [n]★ joueur (modèle) → NomAéroport [ID] | demande | il y a Xs
            -- fe() obligatoire car la ligne contient des [ qui casseraient le formspec
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.50;%s]", rpy, CFG.X_MAX, bg))
            table.insert(fs, string.format("label[0.20,%.2f;%s]", rpy + 0.00,
                fe(string.format("[%d]%s %s (%s) → %s  |  %s  |  il y a %s",
                    ri, stat, req.player, req.model or "?", ap_disp_req, det, age_str))))
            rpy = rpy + 0.95

            if req.req_type == "landing" or req.req_type == "takeoff" then
                local ap  = linked and find_ap(linked)
                local rws = ap and ap.runways or {}
                local verb = req.req_type == "landing" and "Att." or "Déc."
                if #rws > 0 then
                    local bx = 0.10
                    for rwi, rw in ipairs(rws) do
                        local parts = {}
                        for pn in (rw.name or ""):gmatch("[^/]+") do table.insert(parts, pn) end
                        for _, pn in ipairs(parts) do
                            if bx + 2.8 > CFG.X_MAX then break end
                            table.insert(fs, string.format(
                                "button[%.2f,%.2f;1.7,0.00;atc_rw_%d_%d_%s;%s]",
                                bx, rpy, ri, rwi, pn, fe(clr("#00FF88", "✔ " .. verb .. " " .. pn))))
                            bx = bx + 2.8
                        end
                    end
                    rpy = rpy + 0.52
                else
                    table.insert(fs, string.format(
                        "button[0.10,%.2f;3.0,0.46;atc_auth_%d;%s]",
                        rpy, ri, fe(clr("#00FF88", "✔ Autorisé"))))
                    rpy = rpy + 0.52
                end
            elseif req.req_type == "flyover" then
                local alt_v = req.alt or 500
                table.insert(fs, string.format("label[0.20,%.2f;Alt.(m):]", rpy - 0.20))
                table.insert(fs, string.format("field[2.20,%.2f;2.8,0.90;atc_alt_%d;;%s]",
                    rpy, ri, fe(tostring(alt_v))))
                table.insert(fs, string.format("button[5.20,%.2f;1.5,0.20;atc_alt_set_%d;Set]", rpy, ri))
                table.insert(fs, string.format("button[6.90,%.2f;3.0,0.20;atc_auth_%d;%s]",
                    rpy, ri, fe(clr("#00FF88", "✔ Autorisé"))))
                rpy = rpy + 0.90
            elseif req.req_type == "approach" then
                local ap  = linked and find_ap(linked)
                local rws = ap and ap.runways or {}
                local bx  = 0.10
                for rwi, rw in ipairs(rws) do
                    local parts = {}
                    for pn in (rw.name or ""):gmatch("[^/]+") do table.insert(parts, pn) end
                    for _, pn in ipairs(parts) do
                        if bx + 2.8 > CFG.X_MAX then break end
                        table.insert(fs, string.format(
                            "button[%.2f,%.2f;2.7,0.46;atc_app_%d_%d_%s;%s]",
                            bx, rpy, ri, rwi, pn, fe(clr("#44FFCC", "⊕ App. " .. pn))))
                        bx = bx + 2.8
                    end
                end
                rpy = rpy + 0.52
            end

            -- Boutons communs
            table.insert(fs, string.format("button[0.10,%.2f;2.7,0.35;atc_ref_%d;%s]",
                rpy, ri, fe(clr("#FF4444", "✕ Refusé"))))
            if req.status == "hold" then
                table.insert(fs, string.format("style[atc_hold_%d;bgcolor=#333333;textcolor=#666666]", ri))
                table.insert(fs, string.format("button[2.90,%.2f;3.3,0.35;atc_hold_%d;%s]",
                    rpy, ri, fe("⏸ En attente")))
            else
                table.insert(fs, string.format("button[2.90,%.2f;3.3,0.35;atc_hold_%d;%s]",
                    rpy, ri, fe(clr("#FFAA00", "⏸ Attente"))))
            end
            table.insert(fs, string.format("button[6.30,%.2f;2.7,0.35;atc_del_%d;%s]",
                rpy, ri, fe(clr("#666666", "✕ Suppr."))))
            rpy = rpy + 0.50
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.03;#333333]", rpy, CFG.X_MAX))
            rpy = rpy + 0.08
        end

        if need_scroll then
            table.insert(fs, "scroll_container_end[]")
            table.insert(fs, scroll_bar(CFG.X_MAX - 0.26, py, list_h, "sc_atc"))
        end
    end

    -- ===================== RADIO =====================
    if sub == "radio" then
        local LW = 4.20; local CX = 4.50; local CW = CFG.X_MAX - CX

        table.insert(fs, string.format("box[0,%.2f;%.2f,0.38;#002233]", py, LW))
        table.insert(fs, string.format("label[0.10,%.2f;%s]", py - 0.02, clr("#88CCFF", "Discussions")))
        local lpy = py + 0.44

        for ci, conv in ipairs(convs) do
            if lpy + 0.44 > CFG.Y_MAX then break end
            local act = (data.radio_sel == ci)
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.44;%s]",
                lpy, LW, act and "#003344" or "#001122"))
            table.insert(fs, string.format("button[0,%.2f;%.2f,0.75;radio_sel_%d;%s]",
                lpy, LW, ci, fe(clr(act and "#FFFFFF" or "#88CCFF",
                    (conv.pilot or "?"):sub(1, 14) .. " (" .. #(conv.messages or {}) .. ")"))))
            lpy = lpy + 0.65
        end
        if lpy + 0.44 <= CFG.Y_MAX then
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.44;#001a22]", lpy, LW))
            table.insert(fs, string.format("button[0,%.2f;%.2f,1.00;radio_new;%s]",
                lpy, LW, fe(clr("#44FFCC", "+ Contacter pilote"))))
        end

        if data.radio_new_mode then
            table.insert(fs, string.format("box[%.2f,%.2f;%.2f,1.00;#001122]", CX, py, CW))
            table.insert(fs, string.format("label[%.2f,%.2f;Nom du pilote :]", CX + 0.15, py + 0.00))
            table.insert(fs, string.format("field[%.2f,%.2f;%.2f,0.60;radio_new_target;;%s]",
                CX + 0.35, py + 0.9, CW - 0.30, fe(data.radio_new_target or "")))
            table.insert(fs, string.format("button[%.2f,%.2f;3.5,0.50;radio_new_open;%s]",
                CX + 0.15, py + 1.5, fe(clr("#44FFCC", "Ouvrir discussion"))))
            table.insert(fs, string.format("button[%.2f,%.2f;2.5,0.50;radio_new_cancel;Annuler]",
                CX + 3.8, py + 1.5))
            return table.concat(fs)
        end

        if not data.radio_sel or not convs[data.radio_sel] then
            table.insert(fs, string.format("label[%.2f,%.2f;%s]", CX + 0.20, py + 0.30,
                clr("#446644", "← Sélectionner ou créer une discussion")))
            return table.concat(fs)
        end

        local conv  = convs[data.radio_sel]
        local msgs  = conv.messages or {}
        local avail = CFG.Y_MAX - py
        local hist_h = math.max(1.5, avail - 1.46)

        table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.40;#002233]", CX, py, CW))
        table.insert(fs, string.format("label[%.2f,%.2f;%s]", CX + 0.15, py + 0.00,
            clr("#00FFFF", "⚡ Radio — " .. (conv.pilot or "?"))))
        table.insert(fs, string.format("button[%.2f,%.2f;1.8,0.34;radio_close_%d;%s]",
            CX + CW - 1.88, py + 0.03, data.radio_sel, fe(clr("#FF6666", "✕ Clore"))))
        py = py + 0.46

        table.insert(fs, string.format("box[%.2f,%.2f;%.2f,%.2f;#0a0a1a]", CX, py, CW, hist_h))
        local msg_h  = 0.38
        local vis    = math.floor((hist_h - 0.1) / msg_h)
        local mstart = math.max(1, #msgs - vis + 1)
        local lmy    = py + 0.06
        for mi = mstart, #msgs do
            if lmy + msg_h > py + hist_h - 0.02 then break end
            local m    = msgs[mi]
            local who  = m.from == "atc" and "ATC" or (m.from or "?")
            local mc   = m.from == "atc" and "#DD99FF" or "#66CCFF"
            local tstr = os.date("%H:%M", m.time or 0)
            -- Pas de [ dans tstr (format HH:MM), mais m.text peut en contenir
            -- On n'utilise PAS minetest.colorize ici car il génère des séquences
            -- échappées incompatibles avec fe(). On affiche en blanc sans couleur.
            local line = string.format("%s %s: %s", tstr, who, m.text or "")
            if #line > 63 then line = line:sub(1, 60) .. ".." end
            -- Préfixe couleur manuel : couleur du nom d'expéditeur seulement
            local prefix = string.format("%s %s: ", tstr, who)
            local body   = (m.text or ""):sub(1, 63 - #prefix)
            table.insert(fs, string.format("label[%.2f,%.2f;%s%s]",
                CX + 0.15, lmy,
                minetest.colorize(mc, fe(prefix)),
                fe(body)))
            lmy = lmy + msg_h
        end
        py = py + hist_h + 0.05

        table.insert(fs, string.format("field[%.2f,%.2f;%.2f,0.62;radio_rep_%d;;%s]",
            CX, py, CW - 3.0, data.radio_sel, fe(data.radio_draft or "")))
        table.insert(fs, string.format("button[%.2f,%.2f;2.8,0.62;radio_send_%d;%s]",
            CX + CW - 2.9, py, data.radio_sel, fe(clr("#00FFFF", "Envoyer ▶"))))
    end

    return table.concat(fs)
end

-- =============================================================
--  ONGLET ADMIN
-- =============================================================
function tab_admin(data, mtos)
    local fs = {}
    local py = CFG.CY

    if not data.admin_ok then
        table.insert(fs, string.format("box[0,%.2f;10,3.40;#110011]", py))
        table.insert(fs, string.format("label[0.30,%.2f;%s]", py + 0.05,
            clr("#CC88CC", "Administration — Mot de passe requis")))
        table.insert(fs, string.format("pwdfield[0.60,%.2f;6.0,0.62;admin_pw;Mot de passe]", py + 1.30))
        table.insert(fs, string.format("button[0.30,%.2f;3.5,0.62;admin_login;Déverrouiller]", py + 1.85))
        if data.admin_err then
            table.insert(fs, string.format("label[0.30,%.2f;%s]", py + 2.60,
                clr("#FF4444", data.admin_err)))
        end
        return table.concat(fs)
    end

    local view = data.av or "list"

    -- ---- LISTE AÉROPORTS ----
    if view == "list" then
        local airports = get_airports()
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]", py, CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py + 0.00, clr("#88CCFF", "Aéroports enregistrés")))
        table.insert(fs, string.format("button[11.2,%.2f;3.4,0.38;new_ap;+ Nouvel aéroport]", py + 0.04))
        py = py + 0.65
        if #airports == 0 then
            table.insert(fs, string.format("label[0.20,%.2f;%s]", py, clr("#888888", "Aucun aéroport.")))
        else
            local item_h = 0.70
            local avail  = CFG.Y_MAX - py
            local need_scroll = (#airports * item_h > avail)
            local list_h = math.min(#airports * item_h, avail)
            if need_scroll then table.insert(fs, scroll_box(0, py, CFG.X_MAX - 0.28, list_h, "sc_ap")) end
            for i, ap in ipairs(airports) do
                local nrw = ap.runways and #ap.runways or 0
                local bpy = need_scroll and (i - 1) * item_h or py
                table.insert(fs, string.format("box[0,%.2f;%.2f,%.2f;#001122]", bpy, CFG.X_MAX, item_h))
                table.insert(fs, string.format("label[0.20,%.2f;%s]",
                    bpy + 0.00, fe(string.format("[%s] %s — %d piste%s", ap.id, ap.name, nrw, nrw > 1 and "s" or ""))))
                table.insert(fs, string.format("button[10.40,%.2f;2.0,0.38;ap_rw_%d;Pistes →]", bpy + 0.06, i))
                table.insert(fs, string.format("button[12.50,%.2f;2.1,0.38;ap_del_%d;%s]",
                    bpy + 0.06, i, fe(clr("#FF6666", "✕ Suppr."))))
                if not need_scroll then py = py + item_h end
            end
            if need_scroll then
                table.insert(fs, "scroll_container_end[]")
                table.insert(fs, scroll_bar(CFG.X_MAX - 0.26, py, list_h, "sc_ap"))
            end
        end
        return table.concat(fs)
    end

    -- ---- NOUVEAU AÉROPORT ----
    if view == "new_ap" then
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]", py, CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py + 0.00, clr("#88CCFF", "Créer un aéroport")))
        table.insert(fs, string.format("button[12.2,%.2f;2.4,0.38;av_back;← Retour]", py + 0.04))
        py = py + 0.58
        table.insert(fs, string.format("label[0.20,%.2f;Identifiant OACI (max 6 car. ex: LFPG) :]", py))
        py = py + 0.36
        table.insert(fs, string.format("field[0.20,%.2f;4.5,0.64;ap_id;;%s]", py, fe(data.n_ap_id or "")))
        py = py + 0.82
        table.insert(fs, string.format("label[0.20,%.2f;Nom complet de l'aéroport :]", py))
        py = py + 0.36
        table.insert(fs, string.format("field[0.20,%.2f;10,0.64;ap_name;;%s]", py, fe(data.n_ap_name or "")))
        py = py + 0.82
        table.insert(fs, string.format("label[0.20,%.2f;Position centre X/Y/Z (vide = position de l'ordi) :]", py))
        py = py + 0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.5,0.64;ap_px;;%s]", py, fe(data.n_ap_x or "")))
        table.insert(fs, string.format("field[3.90,%.2f;3.5,0.64;ap_py;;%s]", py, fe(data.n_ap_y or "")))
        table.insert(fs, string.format("field[7.60,%.2f;3.5,0.64;ap_pz;;%s]", py, fe(data.n_ap_z or "")))
        py = py + 0.82
        table.insert(fs, string.format("button[0.20,%.2f;4.5,0.64;ap_create;✔ Créer l'aéroport]", py))
        if data.n_ap_err then
            table.insert(fs, string.format("label[0.20,%.2f;%s]", py + 0.76, clr("#FF4444", data.n_ap_err)))
        end
        return table.concat(fs)
    end

    -- ---- LISTE PISTES ----
    if view == "rw_list" and data.ai then
        local airports = get_airports()
        local ap = airports[data.ai]
        if not ap then data.av = "list"; return tab_admin(data, mtos) end
        ap.runways = ap.runways or {}
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]", py, CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py + 0.00,
            clr("#88CCFF", "[" .. ap.id .. "] " .. ap.name .. " — Pistes")))
        table.insert(fs, string.format("button[12.2,%.2f;2.4,0.38;av_back;← Retour]", py + 0.04))
        table.insert(fs, string.format("button[9.10,%.2f;2.9,0.38;new_rw;+ Nouvelle piste]", py + 0.04))
        py = py + 0.52
        if #ap.runways == 0 then
            table.insert(fs, string.format("label[0.20,%.2f;%s]", py, clr("#888888", "Aucune piste.")))
        else
            local item_h = 0.50
            local avail  = CFG.Y_MAX - py
            local need_scroll = (#ap.runways * item_h > avail)
            local list_h = math.min(#ap.runways * item_h, avail)
            if need_scroll then table.insert(fs, scroll_box(0, py, CFG.X_MAX - 0.28, list_h, "sc_rw2")) end
            for ri, rw in ipairs(ap.runways) do
                local bpy = need_scroll and (ri - 1) * item_h or py
                local app_info = ""
                if rw.approaches then
                    local p2 = {}
                    for rn, c in pairs(rw.approaches) do table.insert(p2, rn .. ":" .. c) end
                    if #p2 > 0 then app_info = " App:" .. table.concat(p2, " ") end
                end
                table.insert(fs, string.format("box[0,%.2f;%.2f,%.2f;#001122]", bpy, CFG.X_MAX, item_h))
                table.insert(fs, string.format("label[0.20,%.2f;%s  |  %dm × %dm%s]",
                    bpy + 0.00, rw.name or ("R" .. ri), rw_len(rw), rw.width or 30, app_info))
                table.insert(fs, string.format("button[12.50,%.2f;2.1,0.38;rw_del_%d;%s]",
                    bpy + 0.06, ri, fe(clr("#FF6666", "✕ Suppr."))))
                if not need_scroll then py = py + item_h end
            end
            if need_scroll then
                table.insert(fs, "scroll_container_end[]")
                table.insert(fs, scroll_bar(CFG.X_MAX - 0.26, py, list_h, "sc_rw2"))
            end
        end
        return table.concat(fs)
    end

    -- ---- NOUVELLE PISTE ----
    if view == "new_rw" and data.ai then
        local airports = get_airports()
        local ap = airports[data.ai]
        if not ap then data.av = "list"; return tab_admin(data, mtos) end
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]", py, CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py + 0.00,
            clr("#88CCFF", "Nouvelle piste — [" .. ap.id .. "] " .. ap.name)))
        table.insert(fs, string.format("button[12.2,%.2f;2.4,0.38;av_back;← Retour]", py + 0.04))
        py = py + 0.58
        table.insert(fs, string.format("label[0.20,%.2f;Suffixe optionnel (L, R, C ou vide) :]", py))
        py = py + 0.36
        table.insert(fs, string.format("field[0.20,%.2f;2.5,0.62;rw_suf;;%s]", py, fe(data.n_rw_suf or "")))
        py = py + 0.80
        table.insert(fs, string.format("label[0.20,%.2f;Largeur (m) :]", py))
        py = py + 0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.0,0.62;rw_wid;;%s]", py, fe(data.n_rw_wid or "30")))
        py = py + 0.80
        table.insert(fs, string.format("label[0.20,%.2f;Extrémité 1 — X / Y / Z :]", py))
        py = py + 0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.5,0.62;rw_p1x;;%s]", py, fe(data.n_rw_p1x or "")))
        table.insert(fs, string.format("field[3.90,%.2f;3.5,0.62;rw_p1y;;%s]", py, fe(data.n_rw_p1y or "")))
        table.insert(fs, string.format("field[7.60,%.2f;3.5,0.62;rw_p1z;;%s]", py, fe(data.n_rw_p1z or "")))
        py = py + 0.80
        table.insert(fs, string.format("label[0.20,%.2f;Extrémité 2 — X / Y / Z :]", py))
        py = py + 0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.5,0.62;rw_p2x;;%s]", py, fe(data.n_rw_p2x or "")))
        table.insert(fs, string.format("field[3.90,%.2f;3.5,0.62;rw_p2y;;%s]", py, fe(data.n_rw_p2y or "")))
        table.insert(fs, string.format("field[7.60,%.2f;3.5,0.62;rw_p2z;;%s]", py, fe(data.n_rw_p2z or "")))
        py = py + 0.80
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py,
            clr("#8888CC", "Coord. d'approche optionnelles (X,Z) :")))
        py = py + 0.36
        local p1x_v = tonumber(data.n_rw_p1x); local p1z_v = tonumber(data.n_rw_p1z)
        local p2x_v = tonumber(data.n_rw_p2x); local p2z_v = tonumber(data.n_rw_p2z)
        local rn1, rn2 = "??", "??"
        if p1x_v and p1z_v and p2x_v and p2z_v then
            local name = rwy_name({x=p1x_v,y=0,z=p1z_v}, {x=p2x_v,y=0,z=p2z_v}, data.n_rw_suf or "")
            local parts = {}
            for pn in name:gmatch("[^/]+") do table.insert(parts, pn) end
            rn1 = parts[1] or "01"; rn2 = parts[2] or "19"
        end
        table.insert(fs, string.format("label[0.20,%.2f;Piste %s (X,Z) :]", py, rn1))
        table.insert(fs, string.format("field[3.50,%.2f;4.0,0.62;rw_app1;;%s]", py, fe(data.n_rw_app1 or "")))
        table.insert(fs, string.format("label[7.70,%.2f;Piste %s (X,Z) :]", py, rn2))
        table.insert(fs, string.format("field[11.0,%.2f;3.5,0.62;rw_app2;;%s]", py, fe(data.n_rw_app2 or "")))
        py = py + 0.80
        table.insert(fs, string.format("label[0.20,%.2f;%s]", py,
            clr("#8888FF", "Numéro calculé automatiquement depuis les coordonnées.")))
        py = py + 0.55
        table.insert(fs, string.format("button[0.20,%.2f;4.5,0.62;rw_create;✔ Créer la piste]", py))
        if data.n_rw_err then
            table.insert(fs, string.format("label[0.20,%.2f;%s]", py + 0.74, clr("#FF4444", data.n_rw_err)))
        end
        return table.concat(fs)
    end

    return table.concat(fs)
end

-- =============================================================
--  FORMSPEC PRINCIPALE (barre d'onglets + dispatch)
-- =============================================================
function build_fs(app, mtos)
    local data = mtos.bdev:get_app_storage('ram', 'radar')
    data.tab = data.tab or "radar"

    local linked = data.active_airport or data.linked_airport
    local state  = get_shared_atc(linked)
    local reqs   = state.requests or {}
    local nl, nh = 0, 0
    for _, r in ipairs(reqs) do
        if r.status == "hold" then nh = nh + 1 else nl = nl + 1 end
    end

    local fs = {}
    local tabs = {
        {id="radar", label="Radar"},
        {id="myap",  label="Aéroports"},
        {id="atc",   label="ATC"},
        {id="admin", label="Admin"},
    }
    local tx = 0.0
    for _, t in ipairs(tabs) do
        local act = data.tab == t.id
        local bg  = act and "#005500" or "#002200"
        local fg  = act and "#FFFFFF"  or "#88FF88"
        local lbl = t.label
        if t.id == "atc" then
            if nl > 0 then fg = act and "#FFFFFF" or "#FF6666"; lbl = lbl .. " [" .. nl .. "]"
            elseif nh > 0 then fg = act and "#FFFFFF" or "#FFFF44"; lbl = lbl .. " [" .. nh .. "⏸]" end
        end
        if t.id == "admin" then lbl = lbl .. (data.admin_ok and "" or " 🔒") end
        table.insert(fs, string.format("box[%.2f,%.2f;3.62,%.2f;%s]", tx, CFG.TAB_Y, CFG.TAB_H, bg))
        table.insert(fs, string.format("button[%.2f,%.2f;3.62,%.2f;tab_%s;%s]",
            tx, CFG.TAB_Y, CFG.TAB_H, t.id, fe(clr(fg, lbl))))
        tx = tx + 3.72
    end

    if     data.tab == "radar" then table.insert(fs, tab_radar(data, mtos))
    elseif data.tab == "myap"  then table.insert(fs, tab_myairport(data, mtos))
    elseif data.tab == "atc"   then table.insert(fs, tab_atc(data, mtos))
    elseif data.tab == "admin" then table.insert(fs, tab_admin(data, mtos))
    end

    return table.concat(fs)
end

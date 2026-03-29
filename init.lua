-- =============================================================
-- radar_atc/init.lua  —  Mod indépendant Radar ATC pour laptop
-- Layout confirmé par analyse des apps natives laptop :
--   Barre launcher : y = -0.31 à +0.30 (NE PAS toucher)
--   Onglets        : y = 0.32, h = 0.55  → fin à 0.87
--   Contenu        : y = 0.97  →  y_max = 9.62
--   x_max safe     : 14.80
-- =============================================================

-- =============================================================
--  PARAMÈTRES (modifiables via settingstype.conf)
-- =============================================================
local function setting(key, default)
    local v = minetest.settings:get("radar_atc." .. key)
    return (v and v ~= "") and v or default
end

local CFG = {
    password_admin  = setting("password_admin",  "maverick"),
    password_remote = setting("password_remote", "rafale"),
    timer_interval  = 3,
    airport_link_r  = 500,
    trail_len       = 5,
    radius_values   = {500, 750, 1000, 1500, 2000, 3000, 5000},
    default_radius  = 1000,
    -- Layout constants (mesurés sur apps natives laptop)
    TAB_Y  = 0.32,   -- y début barre onglets
    TAB_H  = 0.55,   -- hauteur onglets
    CY     = 0.97,   -- y début contenu
    Y_MAX  = 9.62,   -- y maximum safe
    X_MAX  = 14.80,  -- x maximum safe
    -- Radar
    RX = 0.05,       -- radar origine x
    RH = 7.60,       -- radar hauteur
}
CFG.RY  = CFG.CY              -- radar origine y
CFG.RW  = 6.80                -- radar largeur
CFG.PX  = CFG.RX + CFG.RW + 0.30   -- panneau droit x
CFG.PW  = CFG.X_MAX - CFG.PX       -- panneau droit largeur
CFG.TAB_END = CFG.TAB_Y + CFG.TAB_H

-- =============================================================
--  STOCKAGE PERSISTANT
-- =============================================================
local ST = minetest.get_mod_storage()
local _ap_cache = nil

local function get_airports()
    if not _ap_cache then
        local r = ST:get_string("airports_v5")
        _ap_cache = (r ~= "" and minetest.deserialize(r)) or {}
    end
    return _ap_cache
end

local function save_airports()
    -- Toutes les modifications passent ICI pour garder le cache cohérent
    ST:set_string("airports_v5", minetest.serialize(_ap_cache or {}))
end

-- État ATC partagé entre tous les nœuds d'un même aéroport
local function get_shared_atc(airport_id)
    if not airport_id then return {requests={}, conversations={}} end
    local r = ST:get_string("atc_" .. airport_id)
    return (r ~= "" and minetest.deserialize(r))
        or {requests={}, conversations={}}
end

local function save_shared_atc(airport_id, state)
    if not airport_id then return end
    ST:set_string("atc_" .. airport_id, minetest.serialize(state))
    -- Notifie tous les nœuds actifs de cet aéroport
    for _, info in pairs(active_nodes or {}) do
        if info.airport_id == airport_id then
            local mt = laptop.os_get(info.pos)
            if mt then
                local data = mt.bdev:get_app_storage('ram','radar')
                data._atc_dirty = true
                -- Save différé pour éviter les empilements
                if not data._save_scheduled then
                    data._save_scheduled = true
                    minetest.after(1.5, function()
                        local mt2 = laptop.os_get(info.pos)
                        if mt2 then
                            local d2 = mt2.bdev:get_app_storage('ram','radar')
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

local function find_ap(id)
    if not id then return nil end
    for i, a in ipairs(get_airports()) do
        if a.id == id then return a, i end
    end
end

-- =============================================================
--  RADARS ACTIFS
-- =============================================================
active_nodes = {}  -- global pour save_shared_atc

local function pk(pos)
    return math.floor(pos.x).."_"..math.floor(pos.y).."_"..math.floor(pos.z)
end

-- =============================================================
--  CONVERSIONS
-- =============================================================
local function yaw2head(y)
    return math.floor(((math.deg(y)+180)%360)+0.5)%360
end
local function head2card(h)
    local d={"N","NNE","NE","ENE","E","ESE","SE","SSE",
              "S","SSO","SO","OSO","O","ONO","NO","NNO"}
    return d[math.floor((h+11.25)/22.5)%16+1]
end
local function d2d(a,b)
    return math.floor(math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)+0.5)
end
local function d3d(a,b)
    return math.floor(math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)+0.5)
end
local function hspd(v) return math.sqrt((v.x or 0)^2+(v.z or 0)^2) end
local function to_kmh(ms) return math.floor(ms*3.6+0.5) end
local function to_kt(ms)  return math.floor(ms*1.944+0.5) end
local function to_ft(y)   return math.floor(y*3.281+0.5) end
local function to_fl(y)   return math.floor(y*3.281/100+0.5) end

local function fmt_alt(y)
    local m=math.floor(y+0.5); local f=to_ft(y); local l=to_fl(y)
    if l>=10 then return string.format("FL%03d | %dm | %dft",l,m,f) end
    return string.format("%dm | %dft",m,f)
end
local function fmt_spd(ms)
    return string.format("%dkm/h | %dkt",to_kmh(ms),to_kt(ms))
end
local function climb_s(r)
    if not r then return "~" end
    if r>0.3 then return "^" end
    if r<-0.3 then return "v" end
    return "~"
end

-- =============================================================
--  NUMÉROS DE PISTE
-- =============================================================
local function bearing(p1,p2)
    return math.deg(math.atan2(p2.x-p1.x,-(p2.z-p1.z)))%360
end
local function rwy_num(b)
    local n=math.floor((b+5)/10)%36
    return n==0 and 36 or n
end
local function rwy_name(p1,p2,suffix)
    local b1=bearing(p1,p2)
    local n1=rwy_num(b1); local n2=rwy_num((b1+180)%360)
    local s=(suffix or ""):upper():gsub("[^LRC]",""):sub(1,1)
    local so=s=="L" and "R" or (s=="R" and "L" or s)
    local lo,hi=n1,n2
    if n1>n2 then lo,hi=n2,n1; s,so=so,s end
    return string.format("%02d%s/%02d%s",lo,so,hi,s)
end

-- Cap → direction cardinale textuelle
local function cap_to_dir(cap)
    local dirs={"nord","nord-nord-est","nord-est","est-nord-est",
                 "est","est-sud-est","sud-est","sud-sud-est",
                 "sud","sud-sud-ouest","sud-ouest","ouest-sud-ouest",
                 "ouest","ouest-nord-ouest","nord-ouest","nord-nord-ouest"}
    return dirs[math.floor((cap+11.25)/22.5)%16+1]
end

-- =============================================================
--  AÉROPORTS
-- =============================================================
local function nearest_ap(pos)
    local best,bd=nil,math.huge
    for _,a in ipairs(get_airports()) do
        if a.pos then
            local d=d3d(pos,a.pos)
            if d<bd then bd=d; best=a end
        end
    end
    return best,bd
end
local function linked_ap(cpos)
    local best,bd=nil,math.huge
    for _,a in ipairs(get_airports()) do
        if a.pos then
            local d=d3d(cpos,a.pos)
            if d<=CFG.airport_link_r and d<bd then bd=d; best=a end
        end
    end
    return best
end
local function rw_len(rw)
    if not(rw.p1 and rw.p2) then return 0 end
    return d3d(rw.p1,rw.p2)
end

-- =============================================================
--  PROJECTION RADAR
-- =============================================================
local function w2r(tp, cp, radius)
    local dx=(tp.x-cp.x)/radius
    local dz=-(tp.z-cp.z)/radius
    local sx=CFG.RW/2+dx*CFG.RW/2
    local sy=CFG.RH/2+dz*CFG.RH/2
    -- Retourne nil si hors portée (pas de clip sur le bord)
    if sx<0.05 or sx>CFG.RW-0.25 or sy<0.05 or sy>CFG.RH-0.25 then
        return nil, nil
    end
    return sx, sy
end

-- =============================================================
--  SCAN AVIONS
-- =============================================================
local function uid(p)
    -- Inclut position arrondie pour distinguer 2 avions identiques du même owner
    return string.format("%s__%s__%d_%d",
        p.model or "", p.owner or "",
        math.floor((p.pos and p.pos.x or 0)/10),
        math.floor((p.pos and p.pos.z or 0)/10))
end

-- Vérifie si un avion a une demande ATC active
local function has_atc_request(player_name, airport_id)
    if not airport_id then return false end
    local state = get_shared_atc(airport_id)
    for _, r in ipairs(state.requests or {}) do
        if r.player == player_name then return true end
    end
    return false
end

local function scan(cpos, radius, old, trails, active_ap)
    trails = trails or {}
    local res = {}
    local objs = core.get_objects_inside_radius(cpos, radius)
    for _, obj in ipairs(objs) do
        if not obj:is_player() then
            local e = obj:get_luaentity()
            if e and e._vehicle_name then
                local pilot=(e.driver_name and e.driver_name~="") and e.driver_name or nil
                if pilot or e.isonground==false then
                    local pos=obj:get_pos()
                    local vel=obj:get_velocity() or {x=0,y=0,z=0}
                    local sp=hspd(vel)
                    local p={
                        model   = e._vehicle_name,
                        owner   = e.owner or "?",
                        pilot   = pilot,
                        pos     = {x=pos.x,y=pos.y,z=pos.z},
                        heading = yaw2head(e._yaw or 0),
                        spd_ms  = sp,
                        climb   = e._climb_rate or 0,
                        alt_m   = math.floor(pos.y+0.5),
                        hp      = math.floor((e.hp_max or 0)*100)/100,
                        hp_max  = math.floor((e._max_plane_hp or e.hp_max or 0)*100)/100,
                        fuel    = (e._max_fuel and e._max_fuel>0)
                                  and math.floor((e._energy or 0)*100/e._max_fuel) or nil,
                        throttle= e._power_lever and math.floor(e._power_lever*10) or nil,
                        dist    = d2d(cpos,pos),
                        has_req = (pilot and has_atc_request(pilot, active_ap)) or false,
                    }
                    -- Traînée (Lua 5.1)
                    local u=uid(p)
                    local src=trails[u] or {}
                    local tr={}
                    for i=1,#src do tr[i]=src[i] end
                    if old then
                        for _,op in ipairs(old) do
                            if uid(op)==u then
                                table.insert(tr,1,{x=op.pos.x,y=op.pos.y,z=op.pos.z})
                                break
                            end
                        end
                    end
                    while #tr>CFG.trail_len do table.remove(tr,#tr) end
                    p.trail=tr
                    table.insert(res,p)
                end
            end
        end
    end
    table.sort(res,function(a,b) return a.dist<b.dist end)
    local nt={}
    for _,p in ipairs(res) do nt[uid(p)]=p.trail end
    return res,nt
end

-- =============================================================
--  HELPERS FORMSPEC
-- =============================================================
local function fe(s) return minetest.formspec_escape(tostring(s or "")) end
local function clr(c,t) return minetest.colorize(c,tostring(t or "")) end

-- Construit un dropdown
local function mkdd(x,y,w,name,items,sel_val)
    local idx=1; local strs={}
    for i,v in ipairs(items) do
        strs[i]=tostring(v)
        if v==sel_val then idx=i end
    end
    return string.format("dropdown[%.2f,%.2f;%.2f,0.60;%s;%s;%d]",
        x,y,w,name,table.concat(strs,","),idx)
end

-- Scroll container wrapper (Minetest 5.4+)
local function scroll_box(x,y,w,h,name)
    return string.format("scroll_container[%.2f,%.2f;%.2f,%.2f;%s;vertical]",x,y,w,h,name)
end
local function scroll_bar(x,y,h,name)
    return string.format("scrollbar[%.2f,%.2f;0.25,%.2f;vertical;%s;0]",x,y,h,name)
end

-- =============================================================
--  ONGLET RADAR
-- =============================================================
local function tab_radar(data, mtos)
    local cpos   = data.remote_center or data.center_pos or mtos.pos
    local radius = data.radius or CFG.default_radius
    local planes = data.planes or {}
    local sel    = data.selected or 0
    local linked = data.active_airport or data.linked_airport
    local fs     = {}

    local RX,RY,RW,RH = CFG.RX,CFG.RY,CFG.RW,CFG.RH
    local PX,PW = CFG.PX,CFG.PW

    -- Indicateur contrôle distant
    if data.remote_center then
        local rem_ap=find_ap(data.active_airport)
        local rem_nm=rem_ap and ("["..rem_ap.id.."] "..rem_ap.name) or "?"
        table.insert(fs, string.format(
            "box[%.2f,%.2f;%.2f,0.28;#220022]label[%.2f,%.2f;%s]",
            RX,RY-0.32,RW, RX+0.1,RY-0.28,
            clr("#FF88FF","⊕ Distant: "..rem_nm)))
    end

    -- Fond radar
    table.insert(fs, string.format("box[%.2f,%.2f;%.2f,%.2f;#001800]",RX,RY,RW,RH))

    -- Rose des vents
    local cx=RX+RW/2; local cy=RY+RH/2
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",cx-0.08,RY+0.05,clr("#335533","N")))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",cx-0.08,RY+RH-0.50,clr("#335533","S")))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",RX+0.05,cy-0.15,clr("#335533","O")))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",RX+RW-0.28,cy-0.15,clr("#335533","E")))
    table.insert(fs, string.format("label[%.2f,%.2f;+]",cx-0.05,cy-0.12))

    -- Cercles indicatifs
    for _,frac in ipairs({1/3,2/3}) do
        local r=RW/2*frac
        for a=0,315,45 do
            local rad=math.rad(a)
            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                cx+math.sin(rad)*r-0.04, cy-math.cos(rad)*r-0.08, clr("#1a3d1a","·")))
        end
    end

    -- Échelle
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
        RX+0.1,RY+RH-0.45,clr("#335533","R:"..radius.."m")))

    -- Pistes de TOUS les aéroports (seulement si dans la portée)
    local airports=get_airports()
    local ap_label_drawn={} -- évite de dessiner le label 2x pour le même aéroport
    for _,ap in ipairs(airports) do
        local is_linked=(ap.id==linked)
        local rw_col = is_linked and "#5566FF" or "#444466"
        local nm_col = is_linked and "#9999FF" or "#666688"
        if ap.runways then
            for _,rw in ipairs(ap.runways) do
                if rw.p1 and rw.p2 then
                    local x1,y1=w2r(rw.p1,cpos,radius)
                    local x2,y2=w2r(rw.p2,cpos,radius)
                    -- N'affiche que si au moins une extrémité est dans la portée
                    if x1 or x2 then
                        -- Clamp les points hors portée sur le bord
                        x1=x1 or (x2 and (RW/2) or nil)
                        y1=y1 or (y2 and (RH/2) or nil)
                        x2=x2 or (RW/2); y2=y2 or (RH/2)
                        -- Points interpolés
                        for t=0,10 do
                            local f=t/10
                            local ix=x1+(x2-x1)*f; local iy=y1+(y2-y1)*f
                            if ix>=0.02 and ix<=RW-0.20 and iy>=0.02 and iy<=RH-0.20 then
                                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                                    RX+ix,RY+iy,clr(rw_col,"·")))
                            end
                        end
                        -- Numéro de piste au milieu
                        local xm=(x1+x2)/2; local ym=(y1+y2)/2
                        if xm>=0.1 and xm<=RW-0.5 and ym>=0.1 and ym<=RH-0.4 then
                            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                                RX+xm, RY+ym-0.28, clr(nm_col,rw.name or "?")))
                        end
                        -- Indicatif aéroport (une seule fois par aéroport étranger)
                        if not is_linked and not ap_label_drawn[ap.id] then
                            if xm>=0.1 and xm<=RW-0.8 and ym>=0.1 and ym<=RH-0.6 then
                                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                                    RX+xm, RY+ym-0.52,
                                    clr("#888888","["..ap.id.."]")))
                                ap_label_drawn[ap.id]=true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Autres radars actifs (seulement si dans la portée)
    for key,info in pairs(active_nodes) do
        if key~=pk(mtos.pos) and info.pos then
            local sx,sy=w2r(info.pos,cpos,radius)
            if sx then
                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                    RX+sx-0.08,RY+sy-0.12,clr("#4488CC","◈")))
            end
        end
    end

    -- Avions + traînées
    for i,p in ipairs(planes) do
        local sx,sy=w2r(p.pos,cpos,radius)
        if sx then
            -- Couleur selon état
            local col
            if i==sel then
                col="#FFAA00"    -- jaune = sélectionné
            elseif p.has_req then
                col="#FF3333"    -- rouge = demande ATC
            elseif p.spd_ms and p.spd_ms>0.5 then
                col="#00FF44"    -- vert = en mouvement
            else
                col="#FFFFFF"    -- blanc = immobile
            end

            -- Traînée : couleur fixe légèrement assombrie, pas de dégradé fort
            for ti,tp in ipairs(p.trail or {}) do
                local tx,ty=w2r(tp,cpos,radius)
                if tx then
                    -- Légère variation de luminosité seulement
                    local dim=math.floor(220-(ti-1)*25)
                    local tc
                    if i==sel then
                        tc=string.format("#%02X%02X00",dim,math.floor(dim*0.67))
                    elseif p.has_req then
                        tc=string.format("#%02X0000",dim)
                    elseif p.spd_ms and p.spd_ms>0.5 then
                        tc=string.format("#00%02X00",dim)
                    else
                        tc=string.format("#%02X%02X%02X",dim,dim,dim)
                    end
                    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                        RX+tx-0.05,RY+ty-0.10,clr(tc,"o")))
                end
            end

            -- Blip triangle
            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                RX+sx-0.07,RY+sy-0.13,clr(col,"▲")))

            -- Label avion : TOUJOURS au-dessus du blip, décalé pour ne pas
            -- chevaucher les points de trail (qui sont à sy-0.10)
            -- On place le label à sy-0.52 (au-dessus de tout)
            local tag=p.model:sub(1,5).."/"..p.owner:sub(1,6)
            local lx=sx-0.35
            if lx<0.05 then lx=sx+0.10 end
            if lx+1.5>RW then lx=sx-1.5 end
            -- Vérifie que le label ne sort pas du radar
            if RY+sy-0.52>RY+0.05 then
                table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                    RX+lx, RY+sy-0.52, clr(col,tag)))
            end
        end
    end

    -- ============ PANNEAU DROIT ============
    local py=CFG.CY

    -- Header aéroport
    local ap_obj=find_ap(linked)
    local ap_lbl=ap_obj and ("["..ap_obj.id.."] "..ap_obj.name) or "Hors aéroport"
    local ap_col=linked and "#88CCFF" or "#FFCC44"
    local ap_bg=linked and "#002244" or "#222200"
    table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.45;%s]",PX,py,PW,ap_bg))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
        PX+0.12,py+0.00,clr(ap_col,ap_lbl)))
    py=py+0.52

    -- Dropdown rayon (label + dropdown sur la même ligne)
    table.insert(fs, string.format("label[%.2f,%.2f;Portée :]",PX,py+0.10))
    table.insert(fs, mkdd(PX+1.90,py,PW-1.95,"dd_radius",CFG.radius_values,radius))
    py=py+0.68

    -- Compteur contacts
    local n=#planes
    table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.38;#001a00]",PX,py,PW))
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",PX+0.12,py+0.00,
        clr(n>0 and "#FFAA00" or "#00FF44",
            n.." contact"..(n>1 and "s" or ""))))
    py=py+0.45

    -- Fiche avion sélectionné
    if sel>0 and planes[sel] then
        local p=planes[sel]
        local rows={}
        table.insert(rows, clr("#FFFF88","Modèle   : "..p.model))
        table.insert(rows, "Proprio  : "..p.owner)
        table.insert(rows, "Pilote   : "..(p.pilot or "—"))
        table.insert(rows, string.format("Cap      : %d° %s",p.heading,head2card(p.heading)))
        table.insert(rows, "Vitesse  : "..fmt_spd(p.spd_ms))
        table.insert(rows, "Altitude : "..fmt_alt(p.alt_m).." "..climb_s(p.climb))
        table.insert(rows, "Distance : "..p.dist.."m")
        if p.throttle then
            table.insert(rows, "Gaz      : "..p.throttle.."%")
        end
        if p.hp_max and p.hp_max>0 then
            local pct=math.floor(p.hp*100/p.hp_max)
            local hc=pct>60 and "#00FF44" or (pct>30 and "#FFAA00" or "#FF4444")
            table.insert(rows, string.format("PV       : %s",
                clr(hc,string.format("%.2f/%.2f (%.0f%%)",p.hp,p.hp_max,pct))))
        end
        if p.fuel then
            local fc=p.fuel>30 and "#00FF44" or "#FF4444"
            table.insert(rows, "Carburant: "..clr(fc,p.fuel.."%"))
        end

        -- Hauteur disponible pour la fiche
        local row_h=0.38
        local avail_h=CFG.Y_MAX-py-0.05
        local max_rows=math.floor(avail_h/row_h)-1
        if #rows>max_rows then
            while #rows>max_rows do table.remove(rows,#rows) end
        end
        local bh=0.08+#rows*row_h+0.08
        table.insert(fs, string.format("box[%.2f,%.2f;%.2f,%.2f;#002800]",PX,py,PW,bh))
        for li,row in ipairs(rows) do
            table.insert(fs, string.format("label[%.2f,%.2f;%s]",
                PX+0.12, py+0.08+(li-1)*row_h, row))
        end
        py=py+bh+0.06
    else
        table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.36;#001000]",PX,py,PW))
        table.insert(fs, string.format("label[%.2f,%.2f;%s]",
            PX+0.12,py-0.03,clr("#448844","Sélectionner un avion ci-dessous")))
        py=py+0.43
    end

    -- Liste avions — scroll_container si trop d'avions
    if n>0 then
        table.insert(fs, string.format("label[%.2f,%.2f;%s]",
            PX,py,clr("#88FF88","Contacts :")))
        py=py+0.32

        local item_h=0.44
        local avail=CFG.Y_MAX-py
        local visible=math.floor(avail/item_h)
        local need_scroll=(n>visible)
        local list_h=math.min(n,visible)*item_h

        if need_scroll then
            -- scroll_container pour la liste
            table.insert(fs, scroll_box(PX,py,PW-0.28,list_h,"sc_planes"))
        end
        local lpy=need_scroll and 0 or py
        local lpx=need_scroll and 0 or PX

        for i,p in ipairs(planes) do
            local fg=(i==sel) and "#FFAA00" or
                     (p.has_req and "#FF6666" or
                     (p.pilot and "#AAFFAA" or "#FFFFFF"))
            local bg=(i==sel) and "#333300" or "#001500"
            local line=string.format("%-6s %4dm %3dkt %dm%s",
                p.model:sub(1,6),p.dist,to_kt(p.spd_ms),p.alt_m,
                p.pilot and " ["..p.pilot.."]" or "")
            table.insert(fs, string.format("style[btn_sel_%d;bgcolor=%s]",i,bg))
            table.insert(fs, string.format("button[%.2f,%.2f;%.2f,%.2f;btn_sel_%d;%s]",
                lpx,lpy,need_scroll and (PW-0.28) or PW,item_h,i,fe(clr(fg,line))))
            lpy=lpy+item_h
        end

        if need_scroll then
            table.insert(fs, "scroll_container_end[]")
            table.insert(fs, scroll_bar(PX+PW-0.26,py,list_h,"sc_planes"))
        end
    end

    -- Timestamp bas radar
    table.insert(fs, string.format("label[%.2f,%.2f;%s]",
        RX+0.10, RY+RH-0.08,
        clr("#335533","MAJ: "..os.date("%H:%M:%S").."  T+"..CFG.timer_interval.."s")))

    return table.concat(fs)
end

-- =============================================================
--  ONGLET AÉROPORTS
-- =============================================================
local function tab_myairport(data, mtos)
    local fs={}
    local py=CFG.CY
    local airports=get_airports()
    local linked=data.linked_airport

    if #airports==0 then
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py,
            clr("#888888","Aucun aéroport. Utilisez l'onglet Admin.")))
        return table.concat(fs)
    end

    -- Dropdown sélection aéroport
    local ap_ids={}; local ap_display={}
    for _,a in ipairs(airports) do
        table.insert(ap_ids,a.id)
        table.insert(ap_display,a.id)  -- dropdown : ID uniquement (concis)
    end
    local viewing=data.myap_view
    if not viewing then viewing=linked or ap_ids[1] end
    local ok=false
    for _,id in ipairs(ap_ids) do if id==viewing then ok=true; break end end
    if not ok then viewing=ap_ids[1] end

    table.insert(fs, string.format("label[0.20,%.2f;Aéroport :]",py+0.10))
    table.insert(fs, mkdd(2.40,py,5.0,"myap_sel",ap_display,viewing))
    py=py+0.68

    local ap=find_ap(viewing)
    if not ap then
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py,clr("#FF4444","Introuvable.")))
        return table.concat(fs)
    end

    -- Nom complet de l'aéroport + badges
    local is_linked=(viewing==linked)
    local is_active=(viewing==data.active_airport)
    local badge=""
    if is_linked then badge=badge..clr("#00FF88"," ← lié") end
    if is_active and not is_linked then badge=badge..clr("#FF88FF"," ← contrôlé") end

    table.insert(fs, string.format("box[0,%.2f;%.2f,0.50;#002244]",py,CFG.X_MAX))
    table.insert(fs, string.format("label[0.20,%.2f;%s]",py+0.02,
        clr("#88CCFF","["..ap.id.."] "..ap.name)..badge))
    if ap.pos then
        table.insert(fs, string.format("label[10.0,%.2f;%s]",py+0.02,
            clr("#446688",string.format("(%.0f,%.0f,%.0f)",ap.pos.x,ap.pos.y,ap.pos.z))))
    end
    py=py+0.58

    -- Boutons contrôle distant
    if not is_linked then
        if is_active then
            table.insert(fs, string.format("button[0.20,%.2f;5.0,0.50;ctrl_return;%s]",
                py,fe(clr("#FFAA00","⟵ Revenir à l'aéroport lié"))))
            py=py+0.58
        elseif data.myap_ctrl_mode==viewing then
            -- Formulaire mdp
            table.insert(fs, string.format("box[0.20,%.2f;8.0,1.50;#110022]",py))
            table.insert(fs, string.format("label[0.40,%.2f;%s]",py+0.10,
                clr("#CC88FF","Mot de passe pour prendre le contrôle :")))
            table.insert(fs, string.format("pwdfield[0.40,%.2f;5.0,0.60;ctrl_pw;Mot de passe]",py+0.48))
            table.insert(fs, string.format("button[5.50,%.2f;2.5,0.60;ctrl_confirm;Confirmer]",py+0.48))
            table.insert(fs, string.format("button[0.40,%.2f;2.5,0.48;ctrl_cancel;Annuler]",py+1.16))
            if data.myap_ctrl_err then
                table.insert(fs, string.format("label[3.10,%.2f;%s]",py+1.22,
                    clr("#FF4444",data.myap_ctrl_err)))
            end
            py=py+1.68
        else
            table.insert(fs, string.format("button[0.20,%.2f;5.0,0.50;ctrl_request;%s]",
                py,fe(clr("#88FFFF","⊕ Prendre le contrôle"))))
            py=py+0.58
        end
    else
        -- Aéroport lié
        if data.active_airport and data.active_airport~=linked then
            table.insert(fs, string.format("button[0.20,%.2f;5.0,0.50;ctrl_return;%s]",
                py,fe(clr("#FFAA00","⟵ Revenir à cet aéroport"))))
        else
            table.insert(fs, string.format("box[0.20,%.2f;7.0,0.38;#002200]",py))
            table.insert(fs, string.format("label[0.40,%.2f;%s]",py+0.08,
                clr("#00FF88","Contrôle actif sur l'aéroport lié.")))
        end
        py=py+0.50
    end

    -- Tableau des pistes
    ap.runways=ap.runways or {}
    if #ap.runways==0 then
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py,
            clr("#888888","Aucune piste enregistrée.")))
        return table.concat(fs)
    end

    -- En-tête tableau
    table.insert(fs, string.format("box[0,%.2f;%.2f,0.40;#003355]",py,CFG.X_MAX))
    local hdrs={{0.20,"Désig."},{2.8,"Long."},{5.0,"Larg."},{6.8,"Cap"},
                {8.2,"Approche"},{10.5,"P1"},{12.7,"P2"}}
    for _,h in ipairs(hdrs) do
        table.insert(fs, string.format("label[%.2f,%.2f;%s]",h[1],py+0.00,clr("#AADDFF",h[2])))
    end
    py=py+0.46

    -- Lignes pistes (scroll si nécessaire)
    local item_h=0.46
    local avail=CFG.Y_MAX-py
    local need_scroll=(#ap.runways*item_h>avail)
    local list_h=math.min(#ap.runways*item_h, avail)

    if need_scroll then
        table.insert(fs, scroll_box(0,py,CFG.X_MAX-0.28,list_h,"sc_rw"))
    end

    for _,rw in ipairs(ap.runways) do
        local len=rw_len(rw)
        local cap=(rw.p1 and rw.p2) and string.format("%.0f°",bearing(rw.p1,rw.p2)) or "—"
        local p1s=rw.p1 and string.format("%.0f,%.0f,%.0f",rw.p1.x,rw.p1.y,rw.p1.z) or "?"
        local p2s=rw.p2 and string.format("%.0f,%.0f,%.0f",rw.p2.x,rw.p2.y,rw.p2.z) or "?"
        -- Coordonnées d'approche
        local app_str="—"
        if rw.approaches then
            local parts={}
            for rn,coords in pairs(rw.approaches) do
                table.insert(parts,rn..":"..coords)
            end
            if #parts>0 then app_str=table.concat(parts," | ") end
        end
        local base_y=need_scroll and 0 or py
        table.insert(fs, string.format("box[0,%.2f;%.2f,%.2f;#001122]",
            base_y,CFG.X_MAX,item_h))
        table.insert(fs, string.format("label[0.20,%.2f;%s]", base_y+0.03,clr("#FFFFFF",rw.name or "?")))
        table.insert(fs, string.format("label[2.80,%.2f;%s]", base_y+0.03,len.."m"))
        table.insert(fs, string.format("label[5.00,%.2f;%s]", base_y+0.03,(rw.width or 30).."m"))
        table.insert(fs, string.format("label[6.80,%.2f;%s]", base_y+0.03,cap))
        table.insert(fs, string.format("label[8.20,%.2f;%s]", base_y+0.03,clr("#8888AA",app_str:sub(1,18))))
        table.insert(fs, string.format("label[10.50,%.2f;%s]",base_y+0.03,clr("#555577",p1s)))
        table.insert(fs, string.format("label[12.70,%.2f;%s]",base_y+0.03,clr("#555577",p2s)))
        if need_scroll then base_y=base_y+item_h end
        py=py+item_h
    end
    if need_scroll then
        table.insert(fs,"scroll_container_end[]")
        table.insert(fs, scroll_bar(CFG.X_MAX-0.26,py-list_h-0.46,list_h,"sc_rw"))
    end

    return table.concat(fs)
end

-- =============================================================
--  ONGLET ATC
-- =============================================================
local function tab_atc(data, mtos)
    local fs={}
    local py=CFG.CY
    local linked=data.active_airport or data.linked_airport
    local state=get_shared_atc(linked)
    local reqs=state.requests or {}
    local convs=state.conversations or {}
    local sub=data.atc_sub or "requests"

    -- Header ATC
    local hbg=linked and "#1a0000" or "#222222"
    local hfg=linked and "#FF8888" or "#888888"
    table.insert(fs, string.format("box[0,%.2f;%.2f,0.40;%s]",py,CFG.X_MAX,hbg))
    table.insert(fs, string.format("label[0.20,%.2f;%s]",py-0.07,
        clr(hfg,"ATC — "..(linked or "(non lié à un aéroport)"))))
    py=py+0.46

    -- Sous-onglets
    local nl,nh=0,0
    for _,r in ipairs(reqs) do
        if r.status=="hold" then nh=nh+1 else nl=nl+1 end
    end
    local lq="Demandes"..(nl>0 and " ["..nl.."]" or "")..(nh>0 and " ("..nh.."⏸)" or "")
    local lr="Radio"..(#convs>0 and " ["..#convs.."]" or "")
    table.insert(fs, string.format("box[0,%.2f;7.10,0.46;%s]",py,
        sub=="requests" and "#004400" or "#002200"))
    table.insert(fs, string.format("button[0,%.2f;7.10,0.46;atcsub_req;%s]",py,
        fe(clr(sub=="requests" and "#FFFFFF" or "#88FF88",lq))))
    table.insert(fs, string.format("box[7.20,%.2f;7.60,0.46;%s]",py,
        sub=="radio" and "#004400" or "#002200"))
    table.insert(fs, string.format("button[7.20,%.2f;7.60,0.46;atcsub_rad;%s]",py,
        fe(clr(sub=="radio" and "#FFFFFF" or "#88FF88",lr))))
    py=py+0.52

    -- ===================== DEMANDES =====================
    if sub=="requests" then
        if #reqs==0 then
            table.insert(fs, string.format("label[0.20,%.2f;%s]",py,
                clr("#446644","Aucune demande en attente.")))
            return table.concat(fs)
        end

        local item_h_base=1.60  -- hauteur de base par requête (sans boutons piste)
        local avail=CFG.Y_MAX-py
        local need_scroll=(#reqs*item_h_base>avail)
        local list_h=math.min(#reqs*item_h_base, avail-0.05)

        if need_scroll then
            table.insert(fs, scroll_box(0,py,CFG.X_MAX-0.28,list_h,"sc_atc"))
        end

        local rpy=need_scroll and 0 or py

        for ri,req in ipairs(reqs) do
            local age=os.time()-(req.time or 0)
            local bg,fg
            if req.status=="hold" then bg="#1a1a00"; fg="#CCCC00"
            elseif age<60         then bg="#1a0000"; fg="#FFFF44"
            else                       bg="#111111"; fg="#888888" end

            local tlab={landing="Atterrissage",takeoff="Décollage",flyover="Survol",approach="Approche"}
            local det=tlab[req.req_type] or req.req_type
            if req.req_type=="flyover" and req.alt then
                det=det.." "..req.alt.."m/"..to_ft(req.alt).."ft"
            end
            local stat=req.status=="hold" and "⏸" or "★"
            -- Infos avion
            local plane_info=""
            if req.model or req.owner then
                plane_info=" | "..(req.model or "?").."/"..(req.owner or "?")
            end

            -- Ligne résumé
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.38;%s]",rpy,CFG.X_MAX,bg))
            table.insert(fs, string.format("label[0.20,%.2f;%s]",rpy+0.06,
                clr(fg,string.format("[%d]%s %s→%s (%s)%s  %ds",
                    ri,stat,req.player,req.airport or "?",det,plane_info,age))))
            rpy=rpy+0.42

            -- Boutons autorisation
            if req.req_type=="landing" or req.req_type=="takeoff" then
                local ap=linked and find_ap(linked)
                local rws=ap and ap.runways or {}
                local verb=req.req_type=="landing" and "Att." or "Déc."
                if #rws>0 then
                    local bx=0.10
                    for rwi,rw in ipairs(rws) do
                        local parts={}
                        for pn in (rw.name or ""):gmatch("[^/]+") do
                            table.insert(parts,pn)
                        end
                        for _,pn in ipairs(parts) do
                            if bx+2.8>CFG.X_MAX then break end
                            table.insert(fs, string.format(
                                "button[%.2f,%.2f;2.7,0.46;atc_rw_%d_%d_%s;%s]",
                                bx,rpy,ri,rwi,pn,fe(clr("#00FF88","✔ "..verb.." "..pn))))
                            bx=bx+2.8
                        end
                    end
                    rpy=rpy+0.52
                else
                    table.insert(fs, string.format(
                        "button[0.10,%.2f;3.0,0.46;atc_auth_%d;%s]",
                        rpy,ri,fe(clr("#00FF88","✔ Autorisé"))))
                    rpy=rpy+0.52
                end
            elseif req.req_type=="flyover" then
                local alt_v=req.alt or 500
                table.insert(fs, string.format("label[0.20,%.2f;Alt.(m):]",rpy+0.08))
                table.insert(fs, string.format("field[2.20,%.2f;2.8,0.50;atc_alt_%d;;%s]",
                    rpy,ri,fe(tostring(alt_v))))
                table.insert(fs, string.format("button[5.20,%.2f;1.5,0.50;atc_alt_set_%d;Set]",rpy,ri))
                table.insert(fs, string.format("button[6.90,%.2f;3.0,0.50;atc_auth_%d;%s]",
                    rpy,ri,fe(clr("#00FF88","✔ Autorisé"))))
                rpy=rpy+0.56
            elseif req.req_type=="approach" then
                -- Boutons par sens de piste avec coordonnées d'approche
                local ap=linked and find_ap(linked)
                local rws=ap and ap.runways or {}
                local bx=0.10
                for rwi,rw in ipairs(rws) do
                    local parts={}
                    for pn in (rw.name or ""):gmatch("[^/]+") do table.insert(parts,pn) end
                    for _,pn in ipairs(parts) do
                        if bx+2.8>CFG.X_MAX then break end
                        table.insert(fs, string.format(
                            "button[%.2f,%.2f;2.7,0.46;atc_app_%d_%d_%s;%s]",
                            bx,rpy,ri,rwi,pn,fe(clr("#44FFCC","⊕ App. "..pn))))
                        bx=bx+2.8
                    end
                end
                rpy=rpy+0.52
            end

            -- Boutons communs
            table.insert(fs, string.format("button[0.10,%.2f;2.7,0.44;atc_ref_%d;%s]",
                rpy,ri,fe(clr("#FF4444","✕ Refusé"))))
            table.insert(fs, string.format("button[2.90,%.2f;3.3,0.44;atc_hold_%d;%s]",
                rpy,ri,fe(clr("#FFAA00","⏸ Attente"))))
            table.insert(fs, string.format("button[6.30,%.2f;2.7,0.44;atc_del_%d;%s]",
                rpy,ri,fe(clr("#666666","✕ Suppr."))))
            rpy=rpy+0.50

            -- Séparateur
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.03;#333333]",rpy,CFG.X_MAX))
            rpy=rpy+0.08
        end

        if need_scroll then
            table.insert(fs,"scroll_container_end[]")
            table.insert(fs, scroll_bar(CFG.X_MAX-0.26,py,list_h,"sc_atc"))
        end
    end

    -- ===================== RADIO =====================
    if sub=="radio" then
        local LW=4.20; local CX=4.50; local CW=CFG.X_MAX-CX

        -- Colonne gauche : liste conversations
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.38;#002233]",py,LW))
        table.insert(fs, string.format("label[0.10,%.2f;%s]",py-0.1,clr("#88CCFF","Discussions")))
        local lpy=py+0.44

        for ci,conv in ipairs(convs) do
            if lpy+0.44>CFG.Y_MAX then break end
            local act=(data.radio_sel==ci)
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.44;%s]",
                lpy,LW,act and "#003344" or "#001122"))
            table.insert(fs, string.format("button[0,%.2f;%.2f,0.44;radio_sel_%d;%s]",
                lpy,LW,ci,fe(clr(act and "#FFFFFF" or "#88CCFF",
                    (conv.pilot or "?"):sub(1,14).." ("..#(conv.messages or {})..")"))))
            lpy=lpy+0.46
        end
        if lpy+0.44<=CFG.Y_MAX then
            table.insert(fs, string.format("box[0,%.2f;%.2f,0.44;#001a22]",lpy,LW))
            table.insert(fs, string.format("button[0,%.2f;%.2f,0.44;radio_new;%s]",
                lpy,LW,fe(clr("#44FFCC","+ Contacter pilote"))))
        end

        -- Formulaire nouvelle discussion
        if data.radio_new_mode then
            table.insert(fs, string.format("box[%.2f,%.2f;%.2f,1.48;#001122]",CX,py,CW))
            table.insert(fs, string.format("label[%.2f,%.2f;Nom du pilote :]",CX+0.15,py+0.10))
            table.insert(fs, string.format("field[%.2f,%.2f;%.2f,0.60;radio_new_target;;%s]",
                CX+0.15,py+0.42,CW-0.30,fe(data.radio_new_target or "")))
            table.insert(fs, string.format("button[%.2f,%.2f;3.5,0.50;radio_new_open;%s]",
                CX+0.15,py+1.0,fe(clr("#44FFCC","Ouvrir discussion"))))
            table.insert(fs, string.format("button[%.2f,%.2f;2.5,0.50;radio_new_cancel;Annuler]",
                CX+3.8,py+1.0))
            return table.concat(fs)
        end

        -- Conversation active
        if not data.radio_sel or not convs[data.radio_sel] then
            table.insert(fs, string.format("label[%.2f,%.2f;%s]",CX+0.20,py+0.30,
                clr("#446644","← Sélectionner ou créer une discussion")))
            return table.concat(fs)
        end

        local conv=convs[data.radio_sel]
        local msgs=conv.messages or {}
        local avail=CFG.Y_MAX-py
        local hist_h=math.max(1.5, avail-1.46)

        -- Header conversation
        table.insert(fs, string.format("box[%.2f,%.2f;%.2f,0.40;#002233]",CX,py,CW))
        table.insert(fs, string.format("label[%.2f,%.2f;%s]",CX+0.15,py+0.09,
            clr("#00FFFF","⚡ Radio — "..(conv.pilot or "?"))))
        table.insert(fs, string.format("button[%.2f,%.2f;1.8,0.34;radio_close_%d;%s]",
            CX+CW-1.88,py+0.03,data.radio_sel,fe(clr("#FF6666","✕ Clore"))))
        py=py+0.46

        -- Historique textarea
        local hist=""
        local start=math.max(1,#msgs-20)
        for mi=start,#msgs do
            local m=msgs[mi]
            local who=m.from=="atc" and "ATC" or (m.from or "?")
            hist=hist..string.format("[%s] %s: %s\n",
                os.date("%H:%M",m.time or 0),who,m.text or "")
        end
        table.insert(fs, string.format("textarea[%.2f,%.2f;%.2f,%.2f;;;%s]",
            CX,py,CW,hist_h,fe(hist)))
        py=py+hist_h+0.05

        -- Champ réponse
        table.insert(fs, string.format("field[%.2f,%.2f;%.2f,0.62;radio_rep_%d;;%s]",
            CX,py,CW-3.0,data.radio_sel,fe(data.radio_draft or "")))
        table.insert(fs, string.format("button[%.2f,%.2f;2.8,0.62;radio_send_%d;%s]",
            CX+CW-2.9,py,data.radio_sel,fe(clr("#00FFFF","Envoyer ▶"))))
    end

    return table.concat(fs)
end

-- =============================================================
--  ONGLET ADMIN
-- =============================================================
local function tab_admin(data, mtos)
    local fs={}
    local py=CFG.CY

    if not data.admin_ok then
        table.insert(fs, string.format("box[0,%.2f;10,3.40;#110011]",py))
        table.insert(fs, string.format("label[0.30,%.2f;%s]",py+0.05,
            clr("#CC88CC","Administration — Mot de passe requis")))
        table.insert(fs, string.format("pwdfield[0.30,%.2f;6.0,0.62;admin_pw;Mot de passe]",py+1.30))
        table.insert(fs, string.format("button[0.30,%.2f;3.5,0.62;admin_login;Déverrouiller]",py+1.85))
        if data.admin_err then
            table.insert(fs, string.format("label[0.30,%.2f;%s]",py+2.60,
                clr("#FF4444",data.admin_err)))
        end
        return table.concat(fs)
    end

    local view=data.av or "list"

    -- ---- LISTE AÉROPORTS ----
    if view=="list" then
        local airports=get_airports()
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]",py,CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py+0.00,clr("#88CCFF","Aéroports enregistrés")))
        table.insert(fs, string.format("button[11.2,%.2f;3.4,0.38;new_ap;+ Nouvel aéroport]",py+0.04))
        py=py+0.52
        if #airports==0 then
            table.insert(fs, string.format("label[0.20,%.2f;%s]",py,clr("#888888","Aucun aéroport.")))
        else
            local item_h=0.50
            local avail=CFG.Y_MAX-py
            local need_scroll=(#airports*item_h>avail)
            local list_h=math.min(#airports*item_h,avail)
            if need_scroll then table.insert(fs,scroll_box(0,py,CFG.X_MAX-0.28,list_h,"sc_ap")) end
            for i,ap in ipairs(airports) do
                local nrw=ap.runways and #ap.runways or 0
                local bpy=need_scroll and (i-1)*item_h or py
                table.insert(fs, string.format("box[0,%.2f;%.2f,%.2f;#001122]",bpy,CFG.X_MAX,item_h))
                table.insert(fs, string.format("label[0.20,%.2f;[%s] %s — %d piste%s]",
                    bpy+0.12,ap.id,ap.name,nrw,nrw>1 and "s" or ""))
                table.insert(fs, string.format("button[10.40,%.2f;2.0,0.38;ap_rw_%d;Pistes →]",bpy+0.06,i))
                table.insert(fs, string.format("button[12.50,%.2f;2.1,0.38;ap_del_%d;%s]",
                    bpy+0.06,i,fe(clr("#FF6666","✕ Suppr."))))
                if not need_scroll then py=py+item_h end
            end
            if need_scroll then
                table.insert(fs,"scroll_container_end[]")
                table.insert(fs, scroll_bar(CFG.X_MAX-0.26,py,list_h,"sc_ap"))
            end
        end
        return table.concat(fs)
    end

    -- ---- NOUVEAU AÉROPORT ----
    if view=="new_ap" then
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]",py,CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py+0.10,clr("#88CCFF","Créer un aéroport")))
        table.insert(fs, string.format("button[12.2,%.2f;2.4,0.38;av_back;← Retour]",py+0.04))
        py=py+0.58
        table.insert(fs, string.format("label[0.20,%.2f;Identifiant OACI (max 6 car. ex: LFPG) :]",py))
        py=py+0.36
        table.insert(fs, string.format("field[0.20,%.2f;4.5,0.64;ap_id;;%s]",py,fe(data.n_ap_id or "")))
        py=py+0.82
        table.insert(fs, string.format("label[0.20,%.2f;Nom complet de l'aéroport :]",py))
        py=py+0.36
        table.insert(fs, string.format("field[0.20,%.2f;10,0.64;ap_name;;%s]",py,fe(data.n_ap_name or "")))
        py=py+0.82
        table.insert(fs, string.format("label[0.20,%.2f;Position centre X/Y/Z (vide = position de l'ordi) :]",py))
        py=py+0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.5,0.64;ap_px;;%s]",py,fe(data.n_ap_x or "")))
        table.insert(fs, string.format("field[3.90,%.2f;3.5,0.64;ap_py;;%s]",py,fe(data.n_ap_y or "")))
        table.insert(fs, string.format("field[7.60,%.2f;3.5,0.64;ap_pz;;%s]",py,fe(data.n_ap_z or "")))
        py=py+0.82
        table.insert(fs, string.format("button[0.20,%.2f;4.5,0.64;ap_create;✔ Créer l'aéroport]",py))
        if data.n_ap_err then
            table.insert(fs, string.format("label[0.20,%.2f;%s]",py+0.76,clr("#FF4444",data.n_ap_err)))
        end
        return table.concat(fs)
    end

    -- ---- LISTE PISTES ----
    if view=="rw_list" and data.ai then
        local airports=get_airports()
        local ap=airports[data.ai]
        if not ap then data.av="list"; return tab_admin(data,mtos) end
        ap.runways=ap.runways or {}
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]",py,CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py+0.00,
            clr("#88CCFF","["..ap.id.."] "..ap.name.." — Pistes")))
        table.insert(fs, string.format("button[12.2,%.2f;2.4,0.38;av_back;← Retour]",py+0.04))
        table.insert(fs, string.format("button[9.10,%.2f;2.9,0.38;new_rw;+ Nouvelle piste]",py+0.04))
        py=py+0.52
        if #ap.runways==0 then
            table.insert(fs, string.format("label[0.20,%.2f;%s]",py,clr("#888888","Aucune piste.")))
        else
            local item_h=0.50
            local avail=CFG.Y_MAX-py
            local need_scroll=(#ap.runways*item_h>avail)
            local list_h=math.min(#ap.runways*item_h,avail)
            if need_scroll then table.insert(fs,scroll_box(0,py,CFG.X_MAX-0.28,list_h,"sc_rw2")) end
            for ri,rw in ipairs(ap.runways) do
                local bpy=need_scroll and (ri-1)*item_h or py
                local app_info=""
                if rw.approaches then
                    local p2={}
                    for rn,c in pairs(rw.approaches) do table.insert(p2,rn..":"..c) end
                    if #p2>0 then app_info=" App:"..table.concat(p2," ") end
                end
                table.insert(fs, string.format("box[0,%.2f;%.2f,%.2f;#001122]",bpy,CFG.X_MAX,item_h))
                table.insert(fs, string.format("label[0.20,%.2f;%s  |  %dm × %dm%s]",
                    bpy+0.12,rw.name or ("R"..ri),rw_len(rw),rw.width or 30,app_info))
                table.insert(fs, string.format("button[12.50,%.2f;2.1,0.38;rw_del_%d;%s]",
                    bpy+0.06,ri,fe(clr("#FF6666","✕ Suppr."))))
                if not need_scroll then py=py+item_h end
            end
            if need_scroll then
                table.insert(fs,"scroll_container_end[]")
                table.insert(fs, scroll_bar(CFG.X_MAX-0.26,py,list_h,"sc_rw2"))
            end
        end
        return table.concat(fs)
    end

    -- ---- NOUVELLE PISTE ----
    if view=="new_rw" and data.ai then
        local airports=get_airports()
        local ap=airports[data.ai]
        if not ap then data.av="list"; return tab_admin(data,mtos) end
        table.insert(fs, string.format("box[0,%.2f;%.2f,0.46;#002244]",py,CFG.X_MAX))
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py+0.00,
            clr("#88CCFF","Nouvelle piste — ["..ap.id.."] "..ap.name)))
        table.insert(fs, string.format("button[12.2,%.2f;2.4,0.38;av_back;← Retour]",py+0.04))
        py=py+0.58
        table.insert(fs, string.format("label[0.20,%.2f;Suffixe optionnel (L, R, C ou vide) :]",py))
        py=py+0.36
        table.insert(fs, string.format("field[0.20,%.2f;2.5,0.62;rw_suf;;%s]",py,fe(data.n_rw_suf or "")))
        py=py+0.80
        table.insert(fs, string.format("label[0.20,%.2f;Largeur (m) :]",py))
        py=py+0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.0,0.62;rw_wid;;%s]",py,fe(data.n_rw_wid or "30")))
        py=py+0.80
        table.insert(fs, string.format("label[0.20,%.2f;Extrémité 1 — X / Y / Z :]",py))
        py=py+0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.5,0.62;rw_p1x;;%s]",py,fe(data.n_rw_p1x or "")))
        table.insert(fs, string.format("field[3.90,%.2f;3.5,0.62;rw_p1y;;%s]",py,fe(data.n_rw_p1y or "")))
        table.insert(fs, string.format("field[7.60,%.2f;3.5,0.62;rw_p1z;;%s]",py,fe(data.n_rw_p1z or "")))
        py=py+0.80
        table.insert(fs, string.format("label[0.20,%.2f;Extrémité 2 — X / Y / Z :]",py))
        py=py+0.36
        table.insert(fs, string.format("field[0.20,%.2f;3.5,0.62;rw_p2x;;%s]",py,fe(data.n_rw_p2x or "")))
        table.insert(fs, string.format("field[3.90,%.2f;3.5,0.62;rw_p2y;;%s]",py,fe(data.n_rw_p2y or "")))
        table.insert(fs, string.format("field[7.60,%.2f;3.5,0.62;rw_p2z;;%s]",py,fe(data.n_rw_p2z or "")))
        py=py+0.80
        -- Coordonnées d'approche
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py,
            clr("#8888CC","Coord. d'approche optionnelles (X,Z) :")))
        py=py+0.36
        -- On récupère les deux numéros de piste pour afficher 2 champs
        local p1x_v=tonumber(data.n_rw_p1x); local p1z_v=tonumber(data.n_rw_p1z)
        local p2x_v=tonumber(data.n_rw_p2x); local p2z_v=tonumber(data.n_rw_p2z)
        local rn1,rn2="??","??"
        if p1x_v and p1z_v and p2x_v and p2z_v then
            local name=rwy_name({x=p1x_v,y=0,z=p1z_v},{x=p2x_v,y=0,z=p2z_v},data.n_rw_suf or "")
            local parts={}
            for pn in name:gmatch("[^/]+") do table.insert(parts,pn) end
            rn1=parts[1] or "01"; rn2=parts[2] or "19"
        end
        table.insert(fs, string.format("label[0.20,%.2f;Piste %s (X,Z) :]",py,rn1))
        table.insert(fs, string.format("field[3.50,%.2f;4.0,0.62;rw_app1;;%s]",py,fe(data.n_rw_app1 or "")))
        table.insert(fs, string.format("label[7.70,%.2f;Piste %s (X,Z) :]",py,rn2))
        table.insert(fs, string.format("field[11.0,%.2f;3.5,0.62;rw_app2;;%s]",py,fe(data.n_rw_app2 or "")))
        py=py+0.80
        table.insert(fs, string.format("label[0.20,%.2f;%s]",py,
            clr("#8888FF","Numéro calculé automatiquement depuis les coordonnées.")))
        py=py+0.42
        table.insert(fs, string.format("button[0.20,%.2f;4.5,0.62;rw_create;✔ Créer la piste]",py))
        if data.n_rw_err then
            table.insert(fs, string.format("label[0.20,%.2f;%s]",py+0.74,clr("#FF4444",data.n_rw_err)))
        end
        return table.concat(fs)
    end

    return table.concat(fs)
end

-- =============================================================
--  FORMSPEC PRINCIPALE
-- =============================================================
local function build_fs(app, mtos)
    local data=mtos.bdev:get_app_storage('ram','radar')
    data.tab=data.tab or "radar"

    local linked=data.active_airport or data.linked_airport
    local state=get_shared_atc(linked)
    local reqs=state.requests or {}
    local nl,nh=0,0
    for _,r in ipairs(reqs) do
        if r.status=="hold" then nh=nh+1 else nl=nl+1 end
    end

    local fs={}

    -- Barre onglets : y=0.32, h=0.55, 4 × 3.62u
    local tabs={
        {id="radar", label="Radar"},
        {id="myap",  label="Aéroports"},
        {id="atc",   label="ATC"},
        {id="admin", label="Admin"},
    }
    local tx=0.0
    for _,t in ipairs(tabs) do
        local act=data.tab==t.id
        local bg=act and "#005500" or "#002200"
        local fg=act and "#FFFFFF"  or "#88FF88"
        local lbl=t.label
        if t.id=="atc" then
            if nl>0 then fg=act and "#FFFFFF" or "#FF6666"; lbl=lbl.." ["..nl.."]"
            elseif nh>0 then fg=act and "#FFFFFF" or "#FFFF44"; lbl=lbl.." ["..nh.."⏸]" end
        end
        if t.id=="admin" then lbl=lbl..(data.admin_ok and "" or " 🔒") end
        table.insert(fs, string.format("box[%.2f,%.2f;3.62,%.2f;%s]",tx,CFG.TAB_Y,CFG.TAB_H,bg))
        table.insert(fs, string.format("button[%.2f,%.2f;3.62,%.2f;tab_%s;%s]",
            tx,CFG.TAB_Y,CFG.TAB_H,t.id,fe(clr(fg,lbl))))
        tx=tx+3.72
    end

    -- Contenu
    if     data.tab=="radar" then table.insert(fs, tab_radar(data,mtos))
    elseif data.tab=="myap"  then table.insert(fs, tab_myairport(data,mtos))
    elseif data.tab=="atc"   then table.insert(fs, tab_atc(data,mtos))
    elseif data.tab=="admin" then table.insert(fs, tab_admin(data,mtos))
    end

    return table.concat(fs)
end

-- =============================================================
--  HANDLE FIELDS
-- =============================================================
local function do_fields(app, mtos, sender, fields)
    local data=mtos.bdev:get_app_storage('ram','radar')
    data.tab          = data.tab          or "radar"
    data.radius       = data.radius       or CFG.default_radius
    data.planes       = data.planes       or {}
    data.trails       = data.trails       or {}
    data.center_pos   = data.center_pos   or {x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z}
    data.selected     = data.selected     or 0
    data.av           = data.av           or "list"
    data.atc_sub      = data.atc_sub      or "requests"

    local linked=data.active_airport or data.linked_airport

    -- Onglets
    for _,t in ipairs({"radar","myap","atc","admin"}) do
        if fields["tab_"..t] then
            if data.tab=="admin" and t~="admin" then
                data.admin_ok=false; data.admin_err=nil
            end
            if t=="admin" then data.admin_ok=false; data.admin_err=nil end
            data.tab=t
            return true
        end
    end

    -- ===== RADAR =====
    if data.tab=="radar" then
        -- Boutons avions EN PREMIER (avant dd_radius)
        for i=1,#data.planes+1 do
            if fields["btn_sel_"..i] then
                data.selected=(data.selected==i) and 0 or i
                return true
            end
        end
        -- Dropdown rayon
        if fields.dd_radius then
            local v=tonumber(fields.dd_radius)
            if v then
                data.radius=v; data.selected=0
                data.planes,data.trails=scan(
                    data.remote_center or data.center_pos,
                    data.radius, data.planes, data.trails, linked)
            end
            return true
        end
    end

    -- ===== AÉROPORTS =====
    if data.tab=="myap" then
        if fields.myap_sel then
            local nv=fields.myap_sel
            if nv~=data.myap_view then
                data.myap_ctrl_mode=nil; data.myap_ctrl_err=nil
            end
            data.myap_view=nv
            return true
        end
        -- Bouton "Prendre le contrôle" (nom fixe, viewing stocké dans data.myap_view)
        if fields.ctrl_request then
            data.myap_ctrl_mode=data.myap_view
            data.myap_ctrl_err=nil
            return true
        end
        if fields.ctrl_cancel then
            data.myap_ctrl_mode=nil; data.myap_ctrl_err=nil
            return true
        end
        if fields.ctrl_confirm then
            if fields.ctrl_pw==CFG.password_remote then
                local view=data.myap_ctrl_mode
                local ap=find_ap(view)
                if ap and ap.pos then
                    data.active_airport=view
                    data.remote_center={x=ap.pos.x,y=ap.pos.y,z=ap.pos.z}
                    active_nodes[pk(mtos.pos)]={
                        pos={x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z},
                        airport_id=view,
                    }
                end
                data.myap_ctrl_mode=nil; data.myap_ctrl_err=nil
                data.tab="radar"
            else
                data.myap_ctrl_err="Mot de passe incorrect."
            end
            return true
        end
        if fields.ctrl_return then
            data.active_airport=data.linked_airport
            data.remote_center=nil
            active_nodes[pk(mtos.pos)]={
                pos={x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z},
                airport_id=data.linked_airport,
            }
            data.tab="radar"
            return true
        end
    end

    -- ===== ADMIN =====
    if data.tab=="admin" then
        if fields.admin_login then
            if fields.admin_pw==CFG.password_admin then
                data.admin_ok=true; data.admin_err=nil; data.av="list"
            else data.admin_err="Mot de passe incorrect." end
            return true
        end
        if not data.admin_ok then return true end

        if fields.av_back then
            if     data.av=="new_ap"  then data.av="list"; data.ai=nil
            elseif data.av=="rw_list" then data.av="list"; data.ai=nil
            elseif data.av=="new_rw"  then data.av="rw_list"
            else   data.av="list" end
            return true
        end
        if fields.new_ap then
            data.av="new_ap"
            data.n_ap_id=""; data.n_ap_name=""
            data.n_ap_x=""; data.n_ap_y=""; data.n_ap_z=""
            data.n_ap_err=nil
            return true
        end
        if fields.ap_create then
            data.n_ap_id   = fields.ap_id   or data.n_ap_id   or ""
            data.n_ap_name = fields.ap_name or data.n_ap_name or ""
            data.n_ap_x    = fields.ap_px   or data.n_ap_x    or ""
            data.n_ap_y    = fields.ap_py   or data.n_ap_y    or ""
            data.n_ap_z    = fields.ap_pz   or data.n_ap_z    or ""
            local id=(data.n_ap_id):upper():gsub("[^A-Z0-9]",""):sub(1,6)
            if #id==0 then data.n_ap_err="Identifiant obligatoire."; return true end
            if #(data.n_ap_name or "")==0 then data.n_ap_err="Nom obligatoire."; return true end
            if find_ap(id) then data.n_ap_err="ID '"..id.."' déjà utilisé."; return true end
            local px=tonumber(data.n_ap_x); local pv=tonumber(data.n_ap_y); local pz=tonumber(data.n_ap_z)
            local pos=(px and pv and pz) and {x=px,y=pv,z=pz}
                   or {x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z}
            local airports=get_airports()
            table.insert(airports,{id=id,name=data.n_ap_name,pos=pos,runways={}})
            save_airports()
            data.av="list"; data.n_ap_err=nil
            return true
        end
        for i=1,60 do
            if fields["ap_del_"..i] then
                local airports=get_airports()
                if airports[i] then table.remove(airports,i); save_airports() end
                data.av="list"; return true
            end
            if fields["ap_rw_"..i] then
                data.av="rw_list"; data.ai=i; return true
            end
        end
        if fields.new_rw then
            data.av="new_rw"; data.n_rw_err=nil
            data.n_rw_suf=""; data.n_rw_wid="30"
            data.n_rw_app1=""; data.n_rw_app2=""
            for _,k in ipairs({"p1x","p1y","p1z","p2x","p2y","p2z"}) do data["n_rw_"..k]="" end
            return true
        end
        if fields.rw_create and data.ai then
            data.n_rw_suf  = fields.rw_suf  or data.n_rw_suf  or ""
            data.n_rw_wid  = fields.rw_wid  or data.n_rw_wid  or "30"
            data.n_rw_app1 = fields.rw_app1 or data.n_rw_app1 or ""
            data.n_rw_app2 = fields.rw_app2 or data.n_rw_app2 or ""
            for _,k in ipairs({"p1x","p1y","p1z","p2x","p2y","p2z"}) do
                data["n_rw_"..k]=fields["rw_"..k] or data["n_rw_"..k] or ""
            end
            local function rn(k) return tonumber(data["n_rw_"..k]) end
            local p1x,p1y,p1z=rn("p1x"),rn("p1y"),rn("p1z")
            local p2x,p2y,p2z=rn("p2x"),rn("p2y"),rn("p2z")
            if not(p1x and p1y and p1z and p2x and p2y and p2z) then
                data.n_rw_err="Toutes les coordonnées sont requises."; return true
            end
            local p1={x=p1x,y=p1y,z=p1z}; local p2={x=p2x,y=p2y,z=p2z}
            local suf=(data.n_rw_suf or ""):upper():gsub("[^LRC]",""):sub(1,1)
            local name=rwy_name(p1,p2,suf)
            -- Parse les numéros de piste pour stocker les approches
            local parts={}
            for pn in name:gmatch("[^/]+") do table.insert(parts,pn) end
            local approaches={}
            local app1=(data.n_rw_app1 or ""):match("^%s*(.-)%s*$")
            local app2=(data.n_rw_app2 or ""):match("^%s*(.-)%s*$")
            if app1~="" and parts[1] then approaches[parts[1]]=app1 end
            if app2~="" and parts[2] then approaches[parts[2]]=app2 end
            local airports=get_airports()
            local ap=airports[data.ai]
            if not ap then data.av="list"; return true end
            ap.runways=ap.runways or {}
            table.insert(ap.runways,{
                name=name, width=tonumber(data.n_rw_wid) or 30,
                p1=p1, p2=p2,
                approaches=(next(approaches) and approaches or nil),
            })
            save_airports()
            data.av="rw_list"; data.n_rw_err=nil
            return true
        end
        if data.ai then
            for ri=1,40 do
                if fields["rw_del_"..ri] then
                    local airports=get_airports()
                    local ap=airports[data.ai]
                    if ap and ap.runways and ap.runways[ri] then
                        table.remove(ap.runways,ri); save_airports()
                    end
                    return true
                end
            end
        end
    end

    -- ===== ATC =====
    if data.tab=="atc" then
        if fields.atcsub_req then data.atc_sub="requests"; return true end
        if fields.atcsub_rad then data.atc_sub="radio";    return true end

        local state=get_shared_atc(linked)
        local reqs=state.requests or {}
        local convs=state.conversations or {}

        -- Requêtes
        for ri=1,#reqs do
            local req=reqs[ri]
            if not req then break end

            if fields["atc_alt_set_"..ri] then
                local v=tonumber(fields["atc_alt_"..ri])
                if v and v>0 then req.alt=math.floor(v) end
                save_shared_atc(linked,state)
                return true
            end

            -- Auth piste individuelle
            local rw_done=false
            for rwi=1,20 do
                local ap=linked and find_ap(linked)
                local rw=ap and ap.runways and ap.runways[rwi]
                if rw then
                    local parts={}
                    for pn in (rw.name or ""):gmatch("[^/]+") do table.insert(parts,pn) end
                    for _,pn in ipairs(parts) do
                        if fields["atc_rw_"..ri.."_"..rwi.."_"..pn] then
                            local verb=req.req_type=="landing" and "Atterrissage" or "Décollage"
                            minetest.chat_send_player(req.player,
                                clr("#00FF88","[ATC "..(linked or "?").."] "
                                    ..verb.." autorisé — Piste "..pn))
                            table.remove(reqs,ri)
                            state.requests=reqs
                            save_shared_atc(linked,state)
                            rw_done=true; break
                        end
                    end
                    if rw_done then break end
                end
            end
            if rw_done then return true end

            -- Auth approche
            for rwi=1,20 do
                local ap=linked and find_ap(linked)
                local rw=ap and ap.runways and ap.runways[rwi]
                if rw then
                    local parts={}
                    for pn in (rw.name or ""):gmatch("[^/]+") do table.insert(parts,pn) end
                    for _,pn in ipairs(parts) do
                        if fields["atc_app_"..ri.."_"..rwi.."_"..pn] then
                            local coords=rw.approaches and rw.approaches[pn]
                            local msg
                            if coords then
                                -- Calcule la direction depuis le cap de la piste
                                local pn_num=tonumber(pn:match("%d+")) or 0
                                local cap_deg=pn_num*10
                                local dir=cap_to_dir(cap_deg)
                                msg=string.format(
                                    "[ATC %s] Approche piste %s : cap %s (%.0f°), coords approche %s. "..
                                    "Contactez la tour à l'approche.",
                                    linked or "?", pn, dir, cap_deg, coords)
                            else
                                -- Pas de coords d'approche : donne les coords de la piste
                                local pp=rw.p1 and
                                    string.format("%.0f,%.0f",rw.p1.x,rw.p1.z) or "?"
                                msg=string.format(
                                    "[ATC %s] Approche piste %s : coordonnées %.  "..
                                    "Aucune approche programmée, référez-vous aux coords de la piste (%s).",
                                    linked or "?", pn, pp)
                            end
                            minetest.chat_send_player(req.player,clr("#44FFCC",msg))
                            table.remove(reqs,ri)
                            state.requests=reqs
                            save_shared_atc(linked,state)
                            return true
                        end
                    end
                end
            end

            if fields["atc_auth_"..ri] then
                if req.req_type=="flyover" then
                    local alt=req.alt or 500
                    minetest.chat_send_player(req.player,
                        clr("#00FF88","[ATC "..(linked or "?").."] Survol autorisé à "
                            ..alt.."m / "..to_ft(alt).."ft"))
                else
                    minetest.chat_send_player(req.player,
                        clr("#00FF88","[ATC "..(linked or "?").."] Autorisé(e)"))
                end
                table.remove(reqs,ri); state.requests=reqs
                save_shared_atc(linked,state)
                return true
            end
            if fields["atc_ref_"..ri] then
                minetest.chat_send_player(req.player,
                    clr("#FF4444","[ATC "..(linked or "?").."] Refusé — Contactez la tour."))
                table.remove(reqs,ri); state.requests=reqs
                save_shared_atc(linked,state)
                return true
            end
            if fields["atc_hold_"..ri] then
                req.status="hold"
                minetest.chat_send_player(req.player,
                    clr("#FFAA00","[ATC "..(linked or "?").."] En attente — Maintenez votre position."))
                save_shared_atc(linked,state)
                return true
            end
            if fields["atc_del_"..ri] then
                table.remove(reqs,ri); state.requests=reqs
                save_shared_atc(linked,state)
                return true
            end
        end

        -- Radio
        for ci=1,#convs+1 do
            if fields["radio_sel_"..ci] then
                data.radio_sel=ci; data.radio_new_mode=false; data.radio_draft=""
                return true
            end
            if fields["radio_close_"..ci] then
                table.remove(convs,ci); state.conversations=convs
                save_shared_atc(linked,state)
                if data.radio_sel and data.radio_sel>=ci then
                    data.radio_sel=#convs>0 and math.max(1,ci-1) or nil
                end
                return true
            end
            if fields["radio_send_"..ci] then
                local conv=convs[ci]
                if conv then
                    local txt=(fields["radio_rep_"..ci] or data.radio_draft or ""):match("^%s*(.-)%s*$")
                    if txt~="" then
                        conv.messages=conv.messages or {}
                        table.insert(conv.messages,{from="atc",text=txt,time=os.time()})
                        -- Correction format commande : /atc AIRPORT msg texte
                        minetest.chat_send_player(conv.pilot,
                            clr("#00FFFF","[ATC "..(linked or "?").."] "..txt
                                .."  (Répondre: /atc "..(linked or "?").." msg <texte>)"))
                        save_shared_atc(linked,state)
                        data.radio_draft=""
                    end
                end
                return true
            end
        end
        for ci=1,#convs do
            if fields["radio_rep_"..ci] then data.radio_draft=fields["radio_rep_"..ci] end
        end
        if fields.radio_new then
            data.radio_new_mode=true; data.radio_new_target=""; return true
        end
        if fields.radio_new_cancel then data.radio_new_mode=false; return true end
        if fields.radio_new_target then data.radio_new_target=fields.radio_new_target end
        if fields.radio_new_open then
            local target=(fields.radio_new_target or data.radio_new_target or ""):match("^%s*(.-)%s*$")
            if target~="" then
                local idx=nil
                for ci,c in ipairs(convs) do if c.pilot==target then idx=ci; break end end
                if not idx then
                    table.insert(convs,{pilot=target,messages={}})
                    idx=#convs
                    state.conversations=convs
                    save_shared_atc(linked,state)
                end
                data.radio_sel=idx; data.radio_new_mode=false; data.radio_draft=""
            end
            return true
        end
    end

    return false
end

-- =============================================================
--  ENREGISTREMENT APP
-- =============================================================
laptop.register_app("radar_atc",{
    app_name="Radar ATC",
    app_icon="radar_atc_icon.png",
    app_info="Surveillance aérienne",

    formspec_func=function(app,mtos)
        local data=mtos.bdev:get_app_storage('ram','radar')
        if not data.init then
            data.init=true; data.tab="radar"
            data.radius=CFG.default_radius; data.planes={}; data.trails={}
            data.center_pos={x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z}
            data.selected=0; data.av="list"; data.atc_sub="requests"
            local la=linked_ap(mtos.pos)
            data.linked_airport=la and la.id or nil
            data.active_airport=data.linked_airport
        end
        active_nodes[pk(mtos.pos)]={
            pos={x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z},
            airport_id=data.active_airport or data.linked_airport,
        }
        local timer=app:get_timer()
        if not timer:is_started() then timer:start(CFG.timer_interval) end
        return build_fs(app,mtos)
    end,

    receive_fields_func=function(app,mtos,sender,fields)
        local data=mtos.bdev:get_app_storage('ram','radar')
        data.center_pos=data.center_pos or {x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z}
        active_nodes[pk(mtos.pos)]={
            pos={x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z},
            airport_id=data.active_airport or data.linked_airport,
        }
        return do_fields(app,mtos,sender,fields)
    end,

    on_timer=function(app,mtos)
        local data=mtos.bdev:get_app_storage('ram','radar')
        local cpos=data.remote_center or data.center_pos
                or {x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z}
        data.center_pos=data.center_pos or {x=mtos.pos.x,y=mtos.pos.y,z=mtos.pos.z}
        data.radius=data.radius or CFG.default_radius
        local linked=data.active_airport or data.linked_airport

        -- Scan avions
        local old_sel=(data.selected and data.selected>0 and data.planes)
                       and data.planes[data.selected] or nil
        local new_planes,new_trails=scan(cpos,data.radius,data.planes,data.trails,linked)

        -- Ne rebuild le formspec QUE si quelque chose a changé
        local changed=(#new_planes~=#(data.planes or {}))
        if not changed then
            for i,p in ipairs(new_planes) do
                local op=data.planes and data.planes[i]
                if not op or op.model~=p.model or op.owner~=p.owner
                   or math.abs(op.alt_m-p.alt_m)>2 or op.has_req~=p.has_req then
                    changed=true; break
                end
            end
        end
        -- Vérifie aussi si l'état ATC partagé a changé
        if data._atc_dirty then changed=true; data._atc_dirty=false end

        data.planes=new_planes; data.trails=new_trails

        if old_sel then
            data.selected=0
            for i,p in ipairs(data.planes) do
                if p.model==old_sel.model and p.owner==old_sel.owner then
                    data.selected=i; break
                end
            end
        end

        -- Retourne true seulement si changement (évite de fermer les dropdowns)
        return changed
    end,
})

-- =============================================================
--  COMMANDES /ATC
-- =============================================================
local function in_aircraft(name)
    local p=minetest.get_player_by_name(name)
    if not p then return false,nil,nil end
    local seat=p:get_attach()
    if not seat then return false,nil,nil end
    local function ck(o)
        if not o then return false,nil,nil end
        local e=o:get_luaentity()
        if e and e._vehicle_name then
            return true, e._vehicle_name, e.owner
        end
        return false,nil,nil
    end
    local ok,model,owner=ck(seat)
    if ok then return ok,model,owner end
    return ck(seat:get_attach())
end

local function push_req(airport_id,req)
    for _,info in pairs(active_nodes) do
        if info.airport_id==airport_id then
            local mt=laptop.os_get(info.pos)
            if mt then
                local d=mt.bdev:get_app_storage('ram','radar')
                d._atc_dirty=true
                if not d._save_scheduled then
                    d._save_scheduled=true
                    minetest.after(1.5,function()
                        local mt2=laptop.os_get(info.pos)
                        if mt2 then
                            local d2=mt2.bdev:get_app_storage('ram','radar')
                            d2._save_scheduled=false; mt2:save()
                        end
                    end)
                end
            end
        end
    end
end

local function push_radio(airport_id,from,txt)
    local state=get_shared_atc(airport_id)
    state.conversations=state.conversations or {}
    local idx=nil
    for ci,c in ipairs(state.conversations) do
        if c.pilot==from then idx=ci; break end
    end
    if not idx then
        table.insert(state.conversations,{pilot=from,messages={}})
        idx=#state.conversations
    end
    table.insert(state.conversations[idx].messages,{from=from,text=txt,time=os.time()})
    save_shared_atc(airport_id,state)
end

minetest.register_chatcommand("atc",{
    params="<ID|airport> <landing|takeoff|flyover|approach|msg> [param]",
    description=table.concat({
        "Commandes ATC depuis un avion :",
        "  /atc airport             — trouver l'aéroport le plus proche",
        "  /atc LFPG landing        — demande d'atterrissage",
        "  /atc LFPG takeoff        — demande de décollage",
        "  /atc LFPG flyover 500    — demande de survol à 500m",
        "  /atc LFPG approach       — demander des instructions d'approche",
        "  /atc LFPG msg <texte>    — message radio libre (dans un avion requis)",
    },"\n"),
    func=function(name,param)
        local args={}
        for w in param:gmatch("%S+") do table.insert(args,w) end
        local player=minetest.get_player_by_name(name)
        if not player then return false,"Joueur introuvable." end

        -- /atc airport
        if args[1] and args[1]:lower()=="airport" then
            local ap,d=nearest_ap(player:get_pos())
            if ap then
                return true,clr("#88CCFF",
                    string.format("[ATC] Plus proche : [%s] %s — %dm",ap.id,ap.name,math.floor(d)))
            end
            return true,clr("#FFAA44","[ATC] Aucun aéroport enregistré.")
        end

        local aid=args[1] and args[1]:upper()
        local action=args[2] and args[2]:lower()
        if not aid or not action then
            return false,"Usage : /atc <ID|airport> <landing|takeoff|flyover|approach|msg> [param]"
        end

        local ap=find_ap(aid)
        if not ap then
            return false,clr("#FF4444","[ATC] '"..aid.."' inconnu. Essayez /atc airport")
        end

        -- Toutes les actions nécessitent d'être dans un avion
        local ok,model,owner=in_aircraft(name)
        if not ok then
            return false,clr("#FF4444","[ATC] Vous devez être à bord d'un avion.")
        end

        if action=="msg" then
            local txt=table.concat(args," ",3):match("^%s*(.-)%s*$")
            if txt=="" then return false,"Usage : /atc "..aid.." msg <texte>" end
            push_radio(aid,name,txt)
            return true,clr("#FFFF44","[ATC "..aid.."] Message radio envoyé.")
        end

        local valid={landing=true,takeoff=true,flyover=true,approach=true}
        if not valid[action] then
            return false,"Action invalide : landing, takeoff, flyover, approach, msg"
        end

        local alt=tonumber(args[3])
        if action=="flyover" and not alt then
            return false,"Précisez l'altitude : /atc "..aid.." flyover 500"
        end

        local state=get_shared_atc(aid)
        state.requests=state.requests or {}

        -- Anti-doublon
        for _,r in ipairs(state.requests) do
            if r.player==name and r.req_type==action and (os.time()-(r.time or 0))<15 then
                return false,clr("#FFAA44","[ATC] Demande déjà envoyée, patientez.")
            end
        end

        local req={
            player=name, airport=aid, req_type=action,
            alt=alt, time=os.time(), status=nil,
            model=model, owner=owner,
        }
        table.insert(state.requests,req)
        save_shared_atc(aid,state)
        -- Notifie les nœuds
        push_req(aid,req)

        local has=false
        for _,info in pairs(active_nodes) do
            if info.airport_id==aid then has=true; break end
        end

        local tf={
            landing="d'atterrissage",
            takeoff="de décollage",
            flyover="de survol"..(alt and (" à "..alt.."m/"..to_ft(alt).."ft") or ""),
            approach="d'approche",
        }
        return true,clr("#FFFF44",
            "[ATC "..aid.."] Demande "..tf[action].." envoyée"
            ..(has and "" or " (aucune tour active)")..".")
    end,
})

-- =============================================================
--  settingstype.conf (généré si absent)
-- =============================================================
-- Les settings sont dans settingstype.conf à la racine du mod.
-- Valeurs par défaut : password_admin=maverick, password_remote=rafale

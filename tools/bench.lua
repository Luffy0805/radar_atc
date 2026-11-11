-- =============================================================
-- tools/bench.lua — banc d'essai des performances du radar (hors moteur)
--
-- Usage : luajit tools/bench.lua [--check] [dossier_du_mod]
--   --check : n'affiche que les écarts aux seuils et sort avec 1 s'il y en a
--             (lancé par `python3 tools/check.py tests`)
--
-- Charge le vrai init.lua (donc tout le mod) avec une API Luanti et un mod
-- laptop simulés, puis rejoue des scénarios : des laptops ouverts, des avions
-- qui volent au milieu d'autres entités (objets au sol, animaux…).
-- Chaque tick reproduit laptop : on_timer, puis formspec_func, puis écriture
-- de la métadonnée « formspec » SEULEMENT si elle a changé (Luanti n'envoie
-- une métadonnée aux joueurs proches que si sa valeur change).
--
-- Mesures : entités examinées, objets remontés de C++ vers Lua, fouilles de
-- blocs, formspecs envoyés, octets envoyés aux joueurs, temps Lua (indicatif :
-- les fonctions simulées tournent en Lua au lieu de C++).
-- Le dossier en argument permet de comparer deux versions du mod :
--   git archive <commit> | tar -x -C /tmp/ancien && luajit tools/bench.lua /tmp/ancien/
-- =============================================================

local CHECK = arg[1] == "--check"
local ROOT = arg[CHECK and 2 or 1] or ((arg[0] or ""):match("^(.-)tools[/\\]bench%.lua$") or "./")
if ROOT == "" then ROOT = "./" end
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end

-- ---------------------------------------------------------------
--  Statistiques
-- ---------------------------------------------------------------
local stats

local function reset_stats()
    stats = { entities_visited = 0, objects_to_lua = 0, node_searches = 0,
              formspecs_sent = 0, bytes_sent = 0, fs_bytes_total = 0, fs_count = 0,
              fs_max = 0, fs_invalid = 0, lua_seconds = 0 }
end

-- Formspec bien formé : chaque élément « nom[...] » fermé, aucun « [ » ou
-- « ] » non échappé à l'intérieur (un nom de joueur non échappé casse l'écran)
local function formspec_ok(fs)
    local i, n, inside = 1, #fs, false
    while i <= n do
        local c = fs:sub(i, i)
        if c == "\\" then
            i = i + 2
        else
            if c == "[" then
                if inside then return false end
                inside = true
            elseif c == "]" then
                if not inside then return false end
                inside = false
            end
            i = i + 1
        end
    end
    return not inside
end

-- ---------------------------------------------------------------
--  Sérialisation réelle (get_shared_atc et get_airports désérialisent
--  vraiment, comme dans Luanti)
-- ---------------------------------------------------------------
local function ser(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            out[#out + 1] = "["; ser(k, out); out[#out + 1] = "]="; ser(val, out); out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        out[#out + 1] = tostring(v)
    else
        out[#out + 1] = "nil"
    end
end

-- ---------------------------------------------------------------
--  Heure virtuelle : os.time/os.date avancent avec la simulation
--  (sinon l'horloge affichée et l'âge des demandes ne bougeraient pas)
-- ---------------------------------------------------------------
local VTIME = os.time()
local real_time, real_date = os.time, os.date
os.time = function(t) if t then return real_time(t) end return math.floor(VTIME) end
os.date = function(fmt, t) return real_date(fmt, t or math.floor(VTIME)) end

-- ---------------------------------------------------------------
--  Monde simulé
-- ---------------------------------------------------------------
local STORE = {}
local entities = {}       -- [id] = luaentity
local players = {}        -- liste d'ObjectRef simulés
local globalsteps, mods_loaded = {}, {}
local app_def

local function new_object(pos, vel, ent)
    local o = { pos = pos, vel = vel or {x = 0, y = 0, z = 0}, ent = ent }
    function o:get_pos() return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end
    function o:get_velocity() return {x = self.vel.x, y = self.vel.y, z = self.vel.z} end
    function o:is_player() return false end
    function o:get_luaentity() return self.ent end
    function o:get_attach() return nil end
    function o:remove() end
    function o:set_armor_groups() end
    return o
end

local function new_player(name, pos)
    local p = { name = name, pos = pos }
    function p:get_pos() return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end
    function p:is_player() return true end
    function p:get_player_name() return self.name end
    function p:get_attach() return nil end
    return p
end

local next_id = 1
local function add_entity(ent, pos, vel)
    ent.object = new_object(pos, vel, ent)
    entities[next_id] = ent
    next_id = next_id + 1
    return ent
end

local function add_aircraft(pilot, pos, vel)
    return add_entity({ name = "test:plane", _vehicle_name = "PA-28", _max_plane_hp = 50,
        _climb_rate = 0, driver_name = pilot, owner = pilot, _yaw = 0, hp_max = 50,
        _energy = 8, _max_fuel = 10, _power_lever = 60 }, pos, vel)
end

local function move_world(dt)
    for _, e in pairs(entities) do
        local o = e.object
        o.pos.x = o.pos.x + o.vel.x * dt
        o.pos.y = o.pos.y + o.vel.y * dt
        o.pos.z = o.pos.z + o.vel.z * dt
        -- vol en rond autour de l'aéroport : rotation lente du vecteur vitesse
        if e._vehicle_name then
            local a = 0.05 * dt
            local vx, vz = o.vel.x, o.vel.z
            o.vel.x = vx * math.cos(a) - vz * math.sin(a)
            o.vel.z = vx * math.sin(a) + vz * math.cos(a)
        end
    end
end

-- ---------------------------------------------------------------
--  API Luanti simulée
-- ---------------------------------------------------------------
local function fake_translate(s, ...)
    local args = {...}
    return (s:gsub("@(.)", function(c)
        if c:match("%d") then return tostring(args[tonumber(c)]) end
        if c == "n" then return "\n" end
        return c
    end))
end

local noop = function() end
local function meta_ref()
    local m = { fields = {} }
    function m:set_string(k, v) self.fields[k] = v end
    function m:get_string(k) return self.fields[k] or "" end
    function m:get_int(k) return tonumber(self.fields[k]) or 0 end
    function m:set_int(k, v) self.fields[k] = v end
    function m:mark_as_private() end
    return m
end

minetest = {
    settings = { get = function() return nil end, get_bool = function(_, _, d) return d end },
    get_translator = function() return fake_translate end,
    formspec_escape = function(s) return (tostring(s):gsub("[%[%];,\\]", "\\%0")) end,
    colorize = function(c, t) return "\27(c@" .. c .. ")" .. t .. "\27(c@#ffffff)" end,
    get_color_escape_sequence = function(c) return "\27(c@" .. c .. ")" end,
    get_modpath = function(name) return name == "radar_atc" and ROOT:sub(1, -2) or nil end,
    get_mod_storage = function()
        return {
            get_string = function(_, k) return STORE[k] or "" end,
            set_string = function(_, k, v) STORE[k] = v end,
            get_int    = function(_, k) return tonumber(STORE[k]) or 0 end,
            set_int    = function(_, k, v) STORE[k] = tostring(v) end,
        }
    end,
    serialize = function(v) local out = {"return "}; ser(v, out); return table.concat(out) end,
    deserialize = function(s)
        local f = loadstring(s or "")
        if not f then return nil end
        setfenv(f, {})
        local ok, r = pcall(f)
        return ok and r or nil
    end,
    register_privilege = noop, register_chatcommand = noop, register_entity = noop,
    register_node = noop, register_lbm = noop, register_craftitem = noop, register_craft = noop,
    register_globalstep = function(f) globalsteps[#globalsteps + 1] = f end,
    register_on_mods_loaded = function(f) mods_loaded[#mods_loaded + 1] = f end,
    after = noop, log = noop, chat_send_player = noop,
    check_player_privs = function() return false end,
    get_node = function() return {name = "air"} end,
    get_node_or_nil = function() return {name = "air"} end,
    get_meta = function() return meta_ref() end,
    get_node_timer = function() return { start = noop, stop = noop, is_started = function() return true end } end,
    add_entity = function() return nil end,
    find_nodes_in_area = function() stats.node_searches = stats.node_searches + 1; return {} end,
    get_objects_inside_radius = function(pos, r)
        local res, r2 = {}, r * r
        for _, e in pairs(entities) do
            stats.entities_visited = stats.entities_visited + 1
            local p = e.object.pos
            local dx, dy, dz = p.x - pos.x, p.y - pos.y, p.z - pos.z
            if dx * dx + dy * dy + dz * dz <= r2 then res[#res + 1] = e.object end
        end
        for _, pl in ipairs(players) do
            local p = pl.pos
            local dx, dy, dz = p.x - pos.x, p.y - pos.y, p.z - pos.z
            if dx * dx + dy * dy + dz * dz <= r2 then res[#res + 1] = pl end
        end
        stats.objects_to_lua = stats.objects_to_lua + #res
        return res
    end,
    get_connected_players = function() return players end,
    get_player_by_name = function(n)
        for _, p in ipairs(players) do if p.name == n then return p end end
    end,
    hash_node_position = function(p) return p.x .. "," .. p.y .. "," .. p.z end,
    get_us_time = function() return math.floor(VTIME * 1000000) end,
}
-- minetest.luaentities : parcourir la table compte comme des entités examinées
minetest.luaentities = setmetatable({}, {
    __pairs = function()
        return function(_, k)
            local nk, v = next(entities, k)
            if nk ~= nil then stats.entities_visited = stats.entities_visited + 1 end
            return nk, v
        end, nil, nil
    end,
})
core = minetest

-- LuaJIT n'honore pas __pairs : le mod appelle pairs(minetest.luaentities),
-- on remplace donc pairs par une version qui le respecte.
local raw_pairs = pairs
pairs = function(t)
    local mt = getmetatable(t)
    if mt and mt.__pairs then return mt.__pairs(t) end
    return raw_pairs(t)
end

local laptops_by_key = {}
laptop = {
    register_app = function(_, def) app_def = def end,
    os_get = function(pos) return laptops_by_key[pos.x .. "," .. pos.y .. "," .. pos.z] end,
}

reset_stats()
dofile(ROOT .. "init.lua")
STORE["rwy_names_fixed_v1"] = "1"
for _, f in ipairs(mods_loaded) do f() end

-- ---------------------------------------------------------------
--  Scénarios
-- ---------------------------------------------------------------
local function setup_world(n_aircraft, n_other, with_requests)
    entities, next_id = {}, 1
    -- 3 aéroports de 3 pistes, 4 pistes indépendantes
    local airports = {}
    for a = 1, 3 do
        local ax, az = (a - 1) * 900, ((a - 1) % 2) * 600   -- AP1 sous les laptops
        local ap = {id = "AP" .. a, name = "Aeroport " .. a, pos = {x = ax, y = 10, z = az},
                    has_transponder = true, runways = {}}
        for r = 1, 3 do
            local ang = math.rad(r * 50)
            local len = 300
            ap.runways[r] = {name = string.format("%02d/%02d", r * 5, r * 5 + 18), width = 30,
                p1 = {x = ax, y = 10, z = az},
                p2 = {x = ax + math.sin(ang) * len, y = 10, z = az + math.cos(ang) * len}}
        end
        airports[a] = ap
    end
    STORE["airports_v5"] = minetest.serialize(airports)
    local strips = {}
    for s = 1, 4 do
        strips[s] = {name = "Piste " .. s, width = 20, note = "",
            p1 = {x = -1500 + s * 200, y = 5, z = -800}, p2 = {x = -1400 + s * 200, y = 5, z = -1000}}
    end
    STORE["indep_strips_v1"] = minetest.serialize(strips)
    local reqs = {}
    for i = 1, n_aircraft do
        local ang = i / n_aircraft * 2 * math.pi
        local pilot = "pilote" .. i
        add_aircraft(pilot, {x = 450 + math.sin(ang) * 1200, y = 80 + i * 15, z = 300 + math.cos(ang) * 1200},
            {x = math.cos(ang) * 35, y = 0, z = -math.sin(ang) * 35})
        if with_requests and i <= 3 then
            reqs[#reqs + 1] = {player = pilot, airport = "AP1", req_type = "landing", time = os.time() - 20 * i,
                               model = "PA-28", owner = pilot}
        end
    end
    STORE["atc_AP1"] = minetest.serialize({requests = reqs, conversations = {}})
    for i = 1, n_other do
        add_entity({name = "__builtin:item"}, {x = (i * 37) % 3000 - 1500, y = 5, z = (i * 53) % 3000 - 1500})
    end
end

local function run(title, opt)
    -- recharger le mod à neuf : caches vides, comme après un redémarrage
    reset_stats()
    setup_world(opt.aircraft, opt.other, opt.requests)
    globalsteps, mods_loaded = {}, {}
    dofile(ROOT .. "init.lua")
    STORE["rwy_names_fixed_v1"] = "1"
    for _, f in ipairs(mods_loaded) do f() end

    players = {}
    for i = 1, opt.players do
        players[i] = new_player("joueur" .. i, {x = 5 + i, y = 10, z = 5 + (opt.players_far and 400 or 0)})
    end

    local laptops = {}
    laptops_by_key = {}
    for l = 1, opt.laptops do
        local pos = {x = l * 2, y = 10, z = 2}
        local ram = {}
        local mtos = { pos = pos, bdev = { get_app_storage = function() return ram end },
                       save = noop, meta = meta_ref() }
        laptops_by_key[pos.x .. "," .. pos.y .. "," .. pos.z] = mtos
        local app = { get_timer = function() return { start = noop, is_started = function() return true end } end }
        local L = { mtos = mtos, app = app, ram = ram, shown = nil }
        -- ouverture de l'application (laptop : set_app → formspec_func)
        L.shown = app_def.formspec_func(app, mtos)
        ram.tab = opt.tab or "radar"
        ram.radius = opt.radius or 3000
        laptops[l] = L
    end
    reset_stats()

    local interval = CFG.timer_interval
    local STEP = 0.1
    for _ = 1, opt.ticks do
        for _ = 1, math.floor(interval / STEP + 0.5) do
            move_world(STEP)
            VTIME = VTIME + STEP
            local t0 = os.clock()
            for _, gs in ipairs(globalsteps) do gs(STEP) end
            stats.lua_seconds = stats.lua_seconds + (os.clock() - t0)
        end
        for _, L in ipairs(laptops) do
            local t0 = os.clock()
            app_def.on_timer(L.app, L.mtos)                -- pass_to_app("on_timer", true)
            local fs = app_def.formspec_func(L.app, L.mtos) -- reshow = true
            stats.lua_seconds = stats.lua_seconds + (os.clock() - t0)
            if fs ~= false and fs ~= nil then
                stats.fs_count = stats.fs_count + 1
                stats.fs_bytes_total = stats.fs_bytes_total + #fs
                if #fs > stats.fs_max then stats.fs_max = #fs end
                if not formspec_ok(fs) then stats.fs_invalid = stats.fs_invalid + 1 end
                if fs ~= L.shown then                       -- set_string : envoi si la valeur change
                    L.shown = fs
                    stats.formspecs_sent = stats.formspecs_sent + 1
                    local near = 0
                    for _, pl in ipairs(players) do
                        local dx, dz = pl.pos.x - L.mtos.pos.x, pl.pos.z - L.mtos.pos.z
                        if dx * dx + dz * dz <= 100 * 100 then near = near + 1 end
                    end
                    stats.bytes_sent = stats.bytes_sent + #fs * near
                end
            end
        end
    end

    local secs = opt.ticks * interval
    if CHECK then return stats end
    print(string.format("\n%s  (%d laptops, %d avions, %d autres entités, %d joueurs%s, %d s simulées)",
        title, opt.laptops, opt.aircraft, opt.other, opt.players, opt.players_far and " loin" or " proches", secs))
    print(string.format("  entités examinées        : %8d  (%d/s)", stats.entities_visited, stats.entities_visited / secs))
    print(string.format("  objets remontés à Lua    : %8d", stats.objects_to_lua))
    print(string.format("  fouilles de blocs        : %8d", stats.node_searches))
    print(string.format("  formspecs construits     : %8d  (taille moyenne %d octets)", stats.fs_count,
        stats.fs_count > 0 and stats.fs_bytes_total / stats.fs_count or 0))
    print(string.format("  formspecs envoyés        : %8d", stats.formspecs_sent))
    print(string.format("  octets envoyés (réseau)  : %8d  (%.1f Ko/s)", stats.bytes_sent, stats.bytes_sent / secs / 1024))
    print(string.format("  temps Lua (indicatif)    : %8.1f ms", stats.lua_seconds * 1000))
    return stats
end

BENCH = {run = run, setup_world = setup_world}   -- pour le débogage
if BENCH_NO_RUN then return end
local base = {laptops = 3, other = 400, players = 2, ticks = 20}
local function with(t) local r = {} for k, v in pairs(base) do r[k] = v end for k, v in pairs(t) do r[k] = v end return r end

if not CHECK then
    print("Banc d'essai radar_atc — " .. ROOT)
    run("1. Aéroport calme, onglet Radar", with{aircraft = 0})
    run("2. Trafic, onglet Radar", with{aircraft = 8})
    run("3. Trafic, personne près des laptops", with{aircraft = 8, players_far = true})
    run("4. Trafic, onglet ATC avec 3 demandes", with{aircraft = 8, tab = "atc", requests = true})
    run("5. Trafic, onglet Admin", with{aircraft = 8, tab = "admin"})
    return
end

-- ---------------------------------------------------------------
--  --check : seuils de non-régression (le radar ne doit plus faire laguer)
-- ---------------------------------------------------------------
local failures = 0
local function expect(ok, msg)
    if not ok then failures = failures + 1; print("ÉCHEC  performance : " .. msg) end
end

local calm = run("calme", with{aircraft = 0})
expect(calm.formspecs_sent <= base.laptops,
    "aéroport calme : l'écran est renvoyé " .. calm.formspecs_sent .. " fois en 60 s (attendu : aucun renvoi après l'ouverture)")
local traffic = run("trafic", with{aircraft = 8})
local single = run("trafic, 1 laptop", with{aircraft = 8, laptops = 1})
expect(traffic.entities_visited <= single.entities_visited,
    string.format("entités examinées : %d avec 3 laptops contre %d avec 1 (le suivi doit être partagé)",
        traffic.entities_visited, single.entities_visited))
expect(traffic.fs_max <= 8000, "écran radar de " .. traffic.fs_max .. " octets avec 8 avions (seuil : 8000)")
local far = run("loin", with{aircraft = 8, players_far = true})
expect(far.entities_visited == 0 and far.fs_count == 0,
    string.format("personne près des laptops : %d entités examinées, %d écrans construits (attendu : 0)",
        far.entities_visited, far.fs_count))
local admin = run("admin", with{aircraft = 8, tab = "admin"})
expect(admin.fs_count == 0, "onglet Admin : " .. admin.fs_count .. " redessins automatiques (attendu : 0)")
local atc = run("atc", with{aircraft = 8, tab = "atc", requests = true})
for name, st in pairs({calme = calm, trafic = traffic, atc = atc}) do
    expect(st.fs_invalid == 0, name .. " : " .. st.fs_invalid .. " formspec(s) mal formé(s)")
end
expect(traffic.node_searches == 0, "trafic : " .. traffic.node_searches .. " fouilles de blocs (attendu : 0)")
print(string.format("Performance : %d contrôle(s) en échec", failures))
os.exit(failures > 0 and 1 or 0)

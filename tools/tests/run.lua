-- =============================================================
-- tools/tests/run.lua — tests unitaires des fonctions pures de radar_atc
--
-- Lancer :  luajit tools/tests/run.lua      (ou python3 tools/check.py tests)
-- Le moteur Luanti n'est pas lancé : l'API minetest est simulée ci-dessous,
-- puis config.lua et utils.lua sont chargés tels quels.
--
-- Ajouter un test       : test("ce qui est vérifié", function() eq(obtenu, attendu) end)
-- Bug pas encore corrigé : bug_connu("comportement attendu", function() ... end)
--   → signalé sans faire échouer la suite ; une fois le bug corrigé, le test
--     passe : le transformer alors en test().
-- Convention géographique du mod : +X = est, +Z = nord.
-- =============================================================

local ROOT = (arg and arg[0] or ""):match("^(.-)tools[/\\]tests[/\\]run%.lua$") or "../../"

-- ---- API minetest simulée (le strict nécessaire pour config.lua, storage.lua et utils.lua)
local function fake_translate(s, ...)
    local args = {...}
    return (s:gsub("@(.)", function(c)
        if c:match("%d") then return tostring(args[tonumber(c)]) end
        if c == "n" then return "\n" end
        return c
    end))
end

minetest = {
    settings        = { get = function() return nil end,
                        get_bool = function(_, _, default) return default end },
    get_translator  = function() return fake_translate end,
    formspec_escape = function(s) return (tostring(s):gsub("[%[%];,\\]", "\\%0")) end,
    colorize        = function(_, text) return text end,
    log             = function() end,
}
core = minetest

-- mod_storage simulé : serialize() range la table et renvoie une étiquette
local STORE, SERIAL = {}, {}
minetest.get_mod_storage = function()
    return {
        get_string = function(_, k) return type(STORE[k]) == "string" and STORE[k] or "" end,
        set_string = function(_, k, v) STORE[k] = v end,
        get_int    = function(_, k) return tonumber(STORE[k]) or 0 end,
        set_int    = function(_, k, v) STORE[k] = v end,
    }
end
minetest.serialize   = function(t) SERIAL[#SERIAL + 1] = t; return "T" .. #SERIAL end
minetest.deserialize = function(s) return SERIAL[tonumber(s:sub(2))] end
local MODS_LOADED = {}
minetest.register_on_mods_loaded = function(fn) MODS_LOADED[#MODS_LOADED + 1] = fn end

dofile(ROOT .. "config.lua")
dofile(ROOT .. "storage.lua")
dofile(ROOT .. "utils.lua")
local storage_get_airports = get_airports

-- ---- Mini-cadre de test
local passed, failed, known = 0, 0, 0

local function eq(got, expected, label)
    if got ~= expected then
        error(string.format("%s : attendu %s, obtenu %s",
            label or "valeur", tostring(expected), tostring(got)), 2)
    end
end

local function near(got, expected, tol, label)
    if type(got) ~= "number" or math.abs(got - expected) > (tol or 1e-9) then
        error(string.format("%s : attendu %s ± %s, obtenu %s",
            label or "valeur", tostring(expected), tostring(tol), tostring(got)), 2)
    end
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("ÉCHEC  " .. name)
        print("        " .. tostring(err))
    end
end

local function bug_connu(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("CORRIGÉ  " .. name .. " — transformer ce bug_connu() en test()")
    else
        known = known + 1
        print("BUG CONNU  " .. name)
        print("        " .. tostring(err))
    end
end

-- Point situé à `dist` m de O, au cap vrai `deg` (0 = nord = +Z, 90 = est = +X)
local O = {x = 0, y = 0, z = 0}
local function at(deg, dist)
    local r = math.rad(deg)
    return {x = math.sin(r) * dist, y = 0, z = math.cos(r) * dist}
end

-- =============================================================
--  Tests
-- =============================================================
test("head2card : points cardinaux et limites des secteurs", function()
    eq(head2card(0), "N");   eq(head2card(11), "N");  eq(head2card(12), "NNE")
    eq(head2card(90), "E");  eq(head2card(180), "S"); eq(head2card(270), "W")
    eq(head2card(359), "N")
end)

test("rwy_num : arrondi à la dizaine, 0 et 360 donnent 36", function()
    eq(rwy_num(0), 36);   eq(rwy_num(4), 36);   eq(rwy_num(5), 1)
    eq(rwy_num(94), 9);   eq(rwy_num(95), 10)
    eq(rwy_num(354), 35); eq(rwy_num(355), 36)
end)

test("rwy_name : pistes nord-sud et est-ouest, dans les deux sens", function()
    eq(rwy_name(O, at(0, 100), ""), "18/36")
    eq(rwy_name(O, at(180, 100), ""), "18/36")
    eq(rwy_name(O, at(90, 100), ""), "09/27")
    eq(rwy_name(O, at(270, 100), ""), "09/27")
end)

test("rwy_name : suffixe C conservé, L/R en paire opposée, suffixe invalide ignoré", function()
    eq(rwy_name(O, at(90, 100), "C"), "09C/27C")
    eq(rwy_name(O, at(90, 100), "x"), "09/27")
    local n = rwy_name(O, at(90, 100), "L")
    local a, b = n:match("^09([LR])/27([LR])$")
    assert(a and b and a ~= b, "L/R attendus en paire opposée, obtenu " .. n)
end)

test("rwy_name suit le cap réel : piste 030°/210° → 03/21, comme /atc navigate", function()
    eq(rwy_name(O, at(30, 100), ""), "03/21", "piste 030°")
    eq(rwy_name(O, at(210, 100), ""), "03/21", "piste 210°")
    eq(rwy_name(O, at(44, 100), ""), "04/22", "piste 044°")
    local n = rwy_name(O, {x = 100, y = 0, z = 100}, "")  -- 45° pile
    assert(n == "05/23" or n == "04/22", "45° : paire cohérente attendue, obtenu " .. n)
    eq(rwy_name(O, at(300, 100), ""), "12/30", "piste 300°")
    near(bearing(O, at(30, 100)), 30, 1e-6, "bearing 030°")
end)

test("migration des noms de piste (ancien calcul en miroir nord/sud)", function()
    -- ancien nom de la piste 030°/210° : 15/33 ; suffixe saisi L → 15R/33L
    local diag = {name = "15R/33L", p1 = O, p2 = at(30, 100),
                  approaches = {["15R"] = "1,2", ["33L"] = "3,4"}}
    local ns   = {name = "18/36", p1 = O, p2 = at(0, 100), approaches = {["18"] = "5,6"}}
    local hand = {name = "Grande piste", p1 = O, p2 = at(30, 100)}
    STORE["airports_v5"] = minetest.serialize({{id = "AP", runways = {diag, ns, hand}}})
    for _, fn in ipairs(MODS_LOADED) do fn() end
    local rws = storage_get_airports()[1].runways
    eq(rws[1].name, "03R/21L", "diagonale renommée, suffixe sur le même bout")
    -- 15R était le bout p1→p2, devenu 03R ; 33L le bout p2→p1, devenu 21L
    eq(rws[1].approaches["03R"], "1,2", "approche du bout p1→p2")
    eq(rws[1].approaches["21L"], "3,4", "approche du bout p2→p1")
    eq(rws[1].approaches["15R"], nil, "ancienne clé retirée")
    eq(rws[2].name, "18/36", "piste nord-sud inchangée")
    eq(rws[2].approaches["18"], "5,6", "approche nord-sud inchangée")
    eq(rws[3].name, "Grande piste", "nom saisi à la main conservé")
    eq(STORE["rwy_names_fixed_v1"], 1, "drapeau posé")
    rws[1].name = "15R/33L"
    for _, fn in ipairs(MODS_LOADED) do fn() end
    eq(rws[1].name, "15R/33L", "la migration ne tourne qu'une fois")
end)

test("réglages : valeur non numérique → défaut, hors bornes → bornée, mots de passe lus", function()
    local conf = {
        ["radar_atc.timer_interval"]       = "abc",
        ["radar_atc.transponder_link_r"]   = "500",
        ["radar_atc.trail_len"]            = "-3",
        ["radar_atc.radar_password_admin"] = "s3cret",
    }
    local saved = minetest.settings
    minetest.settings = {
        get      = function(_, k) return conf[k] end,
        get_bool = function(_, k, d) if k == "radar_atc.transponder_enabled" then return false end return d end,
    }
    local ok, err = pcall(dofile, ROOT .. "config.lua")
    local c = CFG
    minetest.settings = saved
    dofile(ROOT .. "config.lua")
    assert(ok, err)
    eq(c.timer_interval, 3, "timer_interval invalide")
    eq(c.transponder_link_r, 79, "transponder_link_r plafonné")
    eq(c.trail_len, 0, "trail_len borné à 0")
    eq(c.radar_password_admin, "s3cret", "mot de passe admin")
    eq(c.radar_password_remote, "airport", "mot de passe distant par défaut")
    eq(c.transponder_enabled, false, "booléen lu")
end)

test("w2r : centre, est, nord en haut de l'écran, hors portée", function()
    local sx, sy = w2r(O, O, 1000)
    near(sx, CFG.RW / 2); near(sy, CFG.RH / 2)
    near((w2r({x = 500, y = 0, z = 0}, O, 1000)), CFG.RW * 0.75, 1e-9, "500 m à l'est")
    local _, ny = w2r({x = 0, y = 0, z = 500}, O, 1000)
    assert(ny < CFG.RH / 2, "le nord (+Z) doit être en haut du radar")
    eq((w2r({x = 2000, y = 0, z = 0}, O, 1000)), nil, "point hors portée")
end)

test("clip_segment : segment intérieur intact, traversant coupé, extérieur ignoré", function()
    local a, b = {x = -100, y = 0, z = 0}, {x = 100, y = 0, z = 0}
    local x1, y1, x2, y2 = clip_segment(a, b, O, 1000)
    local ax, ay = w2r(a, O, 1000)
    local bx, by = w2r(b, O, 1000)
    near(x1, ax); near(y1, ay); near(x2, bx); near(y2, by)
    x1, y1, x2, y2 = clip_segment({x = -5000, y = 0, z = 0}, {x = 5000, y = 0, z = 0}, O, 1000)
    near(x1, 0.05, 1e-9, "bord gauche"); near(x2, CFG.RW - 0.25, 1e-9, "bord droit")
    near(y1, CFG.RH / 2); near(y2, CFG.RH / 2)
    eq((clip_segment({x = -100, y = 0, z = 5000}, {x = 100, y = 0, z = 5000}, O, 1000)), nil,
        "segment entièrement au nord du radar")
end)

test("fmt_alt : niveau de vol affiché à partir de FL010", function()
    eq(fmt_alt(100), "100m | 328ft")
    eq(fmt_alt(1000), "FL033 | 1000m | 3281ft")
end)

test("distances, conversions et clé de position", function()
    eq(d2d({x = 0, y = 0, z = 0}, {x = 3, y = 50, z = 4}), 5, "d2d ignore l'altitude")
    eq(d3d({x = 0, y = 0, z = 0}, {x = 2, y = 3, z = 6}), 7)
    eq(to_kmh(10), 36); eq(to_kt(10), 19); eq(to_ft(1), 3)
    eq(pk({x = 1.7, y = -2.2, z = 3}), "1_-3_3")
end)

test("linked_ap : aéroport le plus proche dans le rayon airport_link_r", function()
    local saved = get_airports
    get_airports = function()
        return { {id = "FAR",  pos = {x = 5000, y = 0, z = 0}},
                 {id = "NEAR", pos = {x = 100,  y = 0, z = 0}} }
    end
    local ap = linked_ap(O)
    eq(ap and ap.id, "NEAR")
    eq(linked_ap({x = 20000, y = 0, z = 0}), nil, "aucun aéroport dans le rayon")
    get_airports = saved
end)

-- =============================================================
print(string.format("Résultat : %d test(s) OK, %d échec(s), %d bug(s) connu(s)", passed, failed, known))
os.exit(failed > 0 and 1 or 0)

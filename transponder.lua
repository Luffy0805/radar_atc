-- =============================================================
-- radar_atc/transponder.lua  —  Antenne Radar ASR + Antenne de liaison
-- =============================================================

-- Signale la présence/absence d'un transpondeur à l'aéroport le plus proche.
-- Appelé par on_construct et on_destruct du nœud transponder.
local function transponder_notify(pos, present)
    local ap = linked_ap(pos)  -- aéroport dans airport_link_r blocs
    if not ap then return end
    local airports = get_airports()
    for i, a in ipairs(airports) do
        if a.id == ap.id then
            airports[i].has_transponder = present
            save_airports()
            return
        end
    end
end

-- Vérifie qu'un transpondeur est associé à l'aéroport actif.
-- Utilise le flag stocké (fonctionne même si les chunks sont distants).
-- ap_center = position de l'aéroport (pour fallback find_nodes si chunk chargé)
function transponder_ok(ap_center, radius)
    if not CFG.transponder_enabled then return true end
    if radius <= CFG.transponder_free_radius then return true end
    if not ap_center then return false end
    -- Chercher l'aéroport dont la position correspond à ap_center
    for _, a in ipairs(get_airports()) do
        if a.pos then
            local dx = math.abs(a.pos.x - ap_center.x)
            local dy = math.abs(a.pos.y - ap_center.y)
            local dz = math.abs(a.pos.z - ap_center.z)
            if dx < 2 and dy < 2 and dz < 2 then
                -- Aéroport trouvé : utiliser le flag persistant
                if a.has_transponder then return true end
                -- Fallback : vérification physique si chunk chargé
                local r = CFG.transponder_link_r or 75
                local nodes = minetest.find_nodes_in_area(
                    {x=ap_center.x-r, y=ap_center.y-r, z=ap_center.z-r},
                    {x=ap_center.x+r, y=ap_center.y+r, z=ap_center.z+r},
                    {"radar_atc:transponder"}
                )
                if #nodes > 0 then
                    -- Mettre à jour le flag
                    for i, ai in ipairs(get_airports()) do
                        if ai.id == a.id then
                            get_airports()[i].has_transponder = true
                            save_airports()
                        end
                    end
                    return true
                end
                return false
            end
        end
    end
    -- Aéroport non trouvé : fallback physique
    local r = CFG.transponder_link_r or 75
    local nodes = minetest.find_nodes_in_area(
        {x=ap_center.x-r, y=ap_center.y-r, z=ap_center.z-r},
        {x=ap_center.x+r, y=ap_center.y+r, z=ap_center.z+r},
        {"radar_atc:transponder"}
    )
    return #nodes > 0
end

-- Vérifie qu'une antenne de liaison existe près de l'ORDINATEUR (ordi_pos).
-- Aucune configuration requise : sa simple présence suffit.
function link_antenna_ok(ordi_pos)
    if not ordi_pos then return false end
    local r = CFG.transponder_link_r or 75
    local nodes = minetest.find_nodes_in_area(
        {x=ordi_pos.x-r, y=ordi_pos.y-r, z=ordi_pos.z-r},
        {x=ordi_pos.x+r, y=ordi_pos.y+r, z=ordi_pos.z+r},
        {"radar_atc:link_antenna"}
    )
    return #nodes > 0
end

-- ─────────────────────────────────────────────────────────────
--  OFFSETS
-- ─────────────────────────────────────────────────────────────
local BASE_Y      = -1.00
local DISH_Y      =  3.00
local WAKE_RADIUS = 48
local SLEEP_CHECK =  2.0

-- =============================================================
--  ENTITE SOCLE (fixe)
-- =============================================================
minetest.register_entity("radar_atc:radar_base_entity", {
    initial_properties = {
        physical=false, collide_with_objects=false, pointable=false,
        static_save=false, visual="mesh", mesh="radar_base.obj",
        textures={"radar_dish_palette.png"}, visual_size={x=5,y=5,z=5}, glow=0,
    },
    _node_pos = nil,
    on_activate = function(self) self.object:set_armor_groups({immortal=1}) end,
    on_step = function(self)
        if self._node_pos then
            if minetest.get_node(self._node_pos).name ~= "radar_atc:transponder" then
                self.object:remove()
            end
        end
    end,
    on_deactivate = function(self) end,
})

-- =============================================================
--  ENTITE ANTENNE (tournante)
-- =============================================================
minetest.register_entity("radar_atc:radar_dish", {
    initial_properties = {
        physical=false, collide_with_objects=false, pointable=false,
        static_save=false, visual="mesh", mesh="radar_dish.obj",
        textures={"radar_dish_palette.png"}, visual_size={x=10,y=10,z=10}, glow=0,
    },
    _node_pos    = nil,
    _yaw         = 0,
    _sleep_timer = 0,
    _sleeping    = false,

    on_activate = function(self) self.object:set_armor_groups({immortal=1}) end,

    on_step = function(self, dtime)
        if self._node_pos then
            if minetest.get_node(self._node_pos).name ~= "radar_atc:transponder" then
                self.object:remove(); return
            end
        end
        if self._sleeping then
            self._sleep_timer = self._sleep_timer + dtime
            if self._sleep_timer < SLEEP_CHECK then return end
            self._sleep_timer = 0
        end
        local pos = self.object:get_pos()
        if not pos then return end
        local player_near = false
        for _, obj in ipairs(minetest.get_objects_inside_radius(pos, WAKE_RADIUS)) do
            if obj:is_player() then player_near = true; break end
        end
        if not player_near then self._sleeping = true; return end
        self._sleeping = false
        local speed = CFG.transponder_rotation_speed or 0.4
        self._yaw = (self._yaw + speed * dtime) % (2 * math.pi)
        self.object:set_rotation({x=0, y=self._yaw, z=0})
    end,
    on_deactivate = function(self) end,
})

-- =============================================================
--  SPAWN / REMOVE / CHECK
--  Anti-doublon : on compte les entités AVANT de spawner.
--  Si la bonne quantité est déjà là, on ne fait rien.
-- =============================================================
local function count_dish_entities(pos)
    local dish_count = 0
    local base_count = 0
    -- Balayer toute la hauteur possible des deux entités
    local ymin = pos.y + math.min(BASE_Y, DISH_Y) - 2
    local ymax = pos.y + math.max(BASE_Y, DISH_Y) + 4
    -- get_objects_inside_radius centré au milieu
    local cy = (ymin + ymax) / 2
    local cr = (ymax - ymin) / 2 + 2
    for _, obj in ipairs(minetest.get_objects_inside_radius(
            {x=pos.x, y=cy, z=pos.z}, cr)) do
        local ent = obj:get_luaentity()
        if ent then
            local np = ent._node_pos
            if np and np.x==pos.x and np.y==pos.y and np.z==pos.z then
                if ent.name == "radar_atc:radar_dish"        then dish_count = dish_count + 1 end
                if ent.name == "radar_atc:radar_base_entity" then base_count = base_count + 1 end
            end
        end
    end
    return dish_count, base_count
end

local function remove_all(pos)
    local ymin = pos.y + math.min(BASE_Y, DISH_Y) - 2
    local ymax = pos.y + math.max(BASE_Y, DISH_Y) + 4
    local cy = (ymin + ymax) / 2
    local cr = (ymax - ymin) / 2 + 2
    for _, obj in ipairs(minetest.get_objects_inside_radius(
            {x=pos.x, y=cy, z=pos.z}, cr)) do
        local ent = obj:get_luaentity()
        if ent then
            local n = ent.name or ""
            if n == "radar_atc:radar_dish" or n == "radar_atc:radar_base_entity" then
                -- Vérifier que c'est bien lié à CE nœud
                local np = ent._node_pos
                if np and np.x==pos.x and np.y==pos.y and np.z==pos.z then
                    obj:remove()
                end
            end
        end
    end
end

local function spawn_one(ename, offset, pos)
    local ep = {x=pos.x, y=pos.y+offset, z=pos.z}
    local obj = minetest.add_entity(ep, ename)
    if obj then
        local ent = obj:get_luaentity()
        if ent then ent._node_pos = {x=pos.x, y=pos.y, z=pos.z} end
    end
end

-- spawn_all : vérifie d'abord qu'on n'a pas déjà les entités
local function spawn_all(pos)
    local dish_n, base_n = count_dish_entities(pos)
    if dish_n >= 1 and base_n >= 1 then return end  -- déjà présentes, rien à faire
    -- Si doublon partiel : nettoyer et repartir proprement
    if dish_n > 1 or base_n > 1 then remove_all(pos) end
    if dish_n == 0 then spawn_one("radar_atc:radar_dish",        DISH_Y, pos) end
    if base_n == 0 then spawn_one("radar_atc:radar_base_entity", BASE_Y, pos) end
end

local function check_and_respawn(pos)
    local dish_n, base_n = count_dish_entities(pos)
    if dish_n > 1 or base_n > 1 then
        -- Doublon détecté : purge complète puis respawn propre
        remove_all(pos)
        spawn_one("radar_atc:radar_dish",        DISH_Y, pos)
        spawn_one("radar_atc:radar_base_entity", BASE_Y, pos)
    elseif dish_n == 0 or base_n == 0 then
        spawn_all(pos)
    end
end

-- =============================================================
--  NŒUD ANCRE — Antenne Radar ASR
-- =============================================================
minetest.register_node("radar_atc:transponder", {
    description         = "Antenne Radar ASR",
    drawtype            = "nodebox",
    tiles               = {"radar_atc_radar_base.png"},
    inventory_image     = "radar_atc_transponder_item.png",
    wield_image         = "radar_atc_transponder_item.png",
    paramtype           = "light",
    sunlight_propagates = true,
    groups              = {cracky=2},
    sounds              = minetest.get_modpath("default")
                          and default.node_sound_metal_defaults() or {},
    selection_box = {type="fixed", fixed={-0.5,-0.5,-0.5, 0.5,0.5,0.5}},
    collision_box = {type="fixed", fixed={-0.5,-0.5,-0.5, 0.5,0.5,0.5}},
    node_box = {
        type="fixed",
        fixed={
            {-0.50,-0.50,-0.50,  0.50, 0.50, 0.50},  -- cube plein (collision complète)
        },
    },
    on_construct = function(pos)
        minetest.get_meta(pos):set_string("infotext","Antenne Radar ASR\n(active)")
        minetest.after(0.5, spawn_all, pos)
        minetest.get_node_timer(pos):start(10)
        minetest.after(0.1, function() transponder_notify(pos, true) end)
    end,
    on_destruct = function(pos)
        remove_all(pos)
        transponder_notify(pos, false)
    end,
    on_timer    = function(pos) check_and_respawn(pos); return true end,
})

-- LBM : au chargement du chunk, on démarre le timer
-- (pas de spawn direct ici — le timer appellera check_and_respawn après 10s,
--  ce qui évite la double-spawn LBM + on_construct/timer)
minetest.register_lbm({
    name              = "radar_atc:respawn_dish",
    nodenames         = {"radar_atc:transponder"},
    run_at_every_load = true,
    action = function(pos)
        -- On utilise minetest.after avec un délai aléatoire [1.0, 2.5]
        -- pour éviter que tous les transponders chargent en même temps
        -- ET pour laisser le temps aux entités déjà sérialisées de s'activer
        local delay = 1.0 + math.random() * 1.5
        minetest.after(delay, function()
            -- Vérifier que le nœud est toujours là
            if minetest.get_node(pos).name == "radar_atc:transponder" then
                check_and_respawn(pos)
                minetest.get_node_timer(pos):start(10)
            end
        end)
    end,
})


-- =============================================================
--  ITEMS DE CRAFT  (non posables, composants techniques)
-- =============================================================
local function register_craft_item(name, desc, texture)
    minetest.register_craftitem("radar_atc:" .. name, {
        description = desc,
        inventory_image = texture,
        groups = {not_in_creative_inventory=0},
    })
end

register_craft_item("module_com",
    "Module de communication ATC\n(Composant — non posable)",
    "radar_atc_module_com.png")

register_craft_item("parabole",
    "Parabole de réception\n(Composant — non posable)",
    "radar_atc_parabole.png")

register_craft_item("waveguide",
    "Guide d'onde hyperfréquence\n(Composant — non posable)",
    "radar_atc_waveguide.png")

register_craft_item("magnetron",
    "Magnétron radar\n(Composant — non posable)",
    "radar_atc_magnetron.png")

register_craft_item("rotator",
    "Moteur de rotation azimut\n(Composant — non posable)",
    "radar_atc_rotator.png")

-- Crafts des composants eux-mêmes
if minetest.get_modpath("default") then
    -- Module de communication : circuit mese + cuivre + or
    minetest.register_craft({
        output = "radar_atc:module_com",
        recipe = {
            {"default:gold_ingot",    "default:mese_crystal",  "default:gold_ingot"},
            {"default:copper_ingot",  "default:steel_ingot",   "default:copper_ingot"},
            {"default:gold_ingot",    "default:mese_crystal",  "default:gold_ingot"},
        },
    })
    -- Parabole : acier + diamant (surface polie) + verre
    minetest.register_craft({
        output = "radar_atc:parabole",
        recipe = {
            {"default:steel_ingot",   "",                      "default:steel_ingot"},
            {"default:steel_ingot",   "default:diamond",       "default:steel_ingot"},
            {"",                      "default:steel_ingot",   ""},
        },
    })
    -- Guide d'onde : cuivre + or (haute conductivité)
    minetest.register_craft({
        output = "radar_atc:waveguide 2",
        recipe = {
            {"default:copper_ingot",  "default:gold_ingot",    "default:copper_ingot"},
            {"default:copper_ingot",  "",                      "default:copper_ingot"},
            {"default:copper_ingot",  "default:gold_ingot",    "default:copper_ingot"},
        },
    })
    -- Magnétron : mese + acier + aimant (obsidienne)
    minetest.register_craft({
        output = "radar_atc:magnetron",
        recipe = {
            {"default:obsidian",      "default:steel_ingot",   "default:obsidian"},
            {"default:steel_ingot",   "default:mese",          "default:steel_ingot"},
            {"default:obsidian",      "default:steel_ingot",   "default:obsidian"},
        },
    })
    -- Moteur de rotation : acier + cuivre + mese
    minetest.register_craft({
        output = "radar_atc:rotator",
        recipe = {
            {"default:steel_ingot",   "default:copper_ingot",  "default:steel_ingot"},
            {"default:copper_ingot",  "default:mese_crystal",  "default:copper_ingot"},
            {"default:steel_ingot",   "default:copper_ingot",  "default:steel_ingot"},
        },
    })
end

if minetest.get_modpath("default") then
    -- Transponder ASR : magnétron + parabole + moteur + module com + acier
    minetest.register_craft({
        output = "radar_atc:transponder",
        recipe = {
            {"radar_atc:parabole",    "radar_atc:magnetron",   "radar_atc:parabole"},
            {"radar_atc:waveguide",   "radar_atc:rotator",     "radar_atc:waveguide"},
            {"default:steelblock",    "radar_atc:module_com",  "default:steelblock"},
        },
    })
end

-- =============================================================
--  ANTENNE DE LIAISON  radar_atc:link_antenna
--
--  Permet de prendre le contrôle d'un aéroport distant
--  SANS mot de passe (ou en alternative au mot de passe).
--  L'opérateur configure l'ID de l'aéroport cible dans les
--  métadonnées du nœud via l'interface de droite-clic.
-- =============================================================
minetest.register_node("radar_atc:link_antenna", {
    description         = "Antenne de liaison ATC",
    drawtype            = "mesh",
    mesh                = "link_antenna.obj",
    tiles               = {"link_antenna_tex.png"},
    inventory_image     = "radar_atc_link_antenna.png",
    wield_image         = "radar_atc_link_antenna.png",
    visual_size         = {x=3, y=3, z=3},
    paramtype           = "light",
    paramtype2          = "facedir",
    sunlight_propagates = true,
    groups              = {cracky=2},
    sounds              = minetest.get_modpath("default")
                          and default.node_sound_metal_defaults() or {},
    selection_box = {type="fixed", fixed={-1.5,-0.5,-1.5, 1.5, 2.5, 1.5}},
    collision_box = {type="fixed", fixed={-0.5, -0.5,-0.5,  0.5,  0.5,  0.5}},

    on_construct = function(pos)
        minetest.get_meta(pos):set_string("infotext",
            "Antenne de liaison ATC\n" ..
            "Autorise la connexion à tout aéroport sans mot de passe\n" ..
            "depuis un radar situé à moins de " ..
            tostring(CFG.transponder_link_r or 75) .. " blocs.")
    end,
})

if minetest.get_modpath("default") then
    -- Antenne de liaison : parabole + module com + guide d'onde + acier
    minetest.register_craft({
        output = "radar_atc:link_antenna",
        recipe = {
            {"",                    "radar_atc:parabole",    ""},
            {"radar_atc:waveguide", "radar_atc:module_com",  "radar_atc:waveguide"},
            {"default:steelblock",  "radar_atc:rotator",     "default:steelblock"},
        },
    })
end

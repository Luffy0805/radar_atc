-- =============================================================
-- radar_atc/transponder.lua  —  ASR Radar Antenna + Antenne de liaison
-- =============================================================

-- Signals the presence/absence of a transponder to the nearest airport.
-- Called by on_construct and on_destruct of the transponder node.
local S = minetest.get_translator("radar_atc")

local function transponder_notify(pos, present)
    local ap = linked_ap(pos)  -- airport within airport_link_r blocks
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

-- Checks that a transponder is associated with the active airport.
-- Uses stored flag (works even if chunks are distant).
-- ap_center = position de l'aéroport (pour fallback find_nodes si chunk chargé)
function transponder_ok(ap_center, radius)
    if not CFG.transponder_enabled then return true end
    if radius <= CFG.transponder_free_radius then return true end
    if not ap_center then return false end
    -- Find the airport whose position matches ap_center
    for _, a in ipairs(get_airports()) do
        if a.pos then
            local dx = math.abs(a.pos.x - ap_center.x)
            local dy = math.abs(a.pos.y - ap_center.y)
            local dz = math.abs(a.pos.z - ap_center.z)
            if dx < 2 and dy < 2 and dz < 2 then
                -- Airport found: use the persistent flag
                if a.has_transponder then return true end
                -- Fallback: physical check if chunk is loaded
                local r = CFG.transponder_link_r or 75
                local nodes = minetest.find_nodes_in_area(
                    {x=ap_center.x-r, y=ap_center.y-r, z=ap_center.z-r},
                    {x=ap_center.x+r, y=ap_center.y+r, z=ap_center.z+r},
                    {"radar_atc:transponder"}
                )
                if #nodes > 0 then
                    -- Update the flag
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
    -- Airport not found: physical fallback
    local r = CFG.transponder_link_r or 75
    local nodes = minetest.find_nodes_in_area(
        {x=ap_center.x-r, y=ap_center.y-r, z=ap_center.z-r},
        {x=ap_center.x+r, y=ap_center.y+r, z=ap_center.z+r},
        {"radar_atc:transponder"}
    )
    return #nodes > 0
end

-- Checks that a link antenna exists near the COMPUTER (ordi_pos).
-- No configuration required: its mere presence is enough.
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
--  OFFSETS (mesh pivot adjustments)
-- ─────────────────────────────────────────────────────────────
local BASE_Y      = -1.00
local DISH_Y      =  3.00
local WAKE_RADIUS = 48
local SLEEP_CHECK =  2.0

-- =============================================================
--  BASE ENTITY (fixed, no rotation)
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
--  DISH ENTITY (rotating)
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
--  Anti-duplicate: count entities BEFORE spawning.
--  If the right quantity is already present, do nothing.
-- =============================================================
local function count_dish_entities(pos)
    local dish_count = 0
    local base_count = 0
    -- Scan the full possible height range of both entities
    local ymin = pos.y + math.min(BASE_Y, DISH_Y) - 2
    local ymax = pos.y + math.max(BASE_Y, DISH_Y) + 4
    -- get_objects_inside_radius centered in the middle
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

-- spawn_all: first checks we do not already have the entities
local function spawn_all(pos)
    local dish_n, base_n = count_dish_entities(pos)
    if dish_n >= 1 and base_n >= 1 then return end  -- already present, nothing to do
    -- Partial duplicate: clean up and restart properly
    if dish_n > 1 or base_n > 1 then remove_all(pos) end
    if dish_n == 0 then spawn_one("radar_atc:radar_dish",        DISH_Y, pos) end
    if base_n == 0 then spawn_one("radar_atc:radar_base_entity", BASE_Y, pos) end
end

local function check_and_respawn(pos)
    local dish_n, base_n = count_dish_entities(pos)
    if dish_n > 1 or base_n > 1 then
        -- Duplicate detected: full purge then clean respawn
        remove_all(pos)
        spawn_one("radar_atc:radar_dish",        DISH_Y, pos)
        spawn_one("radar_atc:radar_base_entity", BASE_Y, pos)
    elseif dish_n == 0 or base_n == 0 then
        spawn_all(pos)
    end
end

-- =============================================================
--  ANCHOR NODE — ASR Radar Antenna
-- =============================================================
minetest.register_node("radar_atc:transponder", {
    description         = S("ASR Radar Antenna"),
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
    collision_box = {type="fixed", fixed={-0.5,-0.5,-0.5, 0.5,0.5, 0.5}},
    node_box = {
        type="fixed",
        fixed={
            {-0.50,-0.50,-0.50,  0.50, 0.50, 0.50},  -- cube plein (collision complète)
        },
    },
    on_construct = function(pos)
        minetest.get_meta(pos):set_string("infotext","ASR Radar Antenna\n(active)")
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

-- LBM: on chunk load, start the timer
-- (no direct spawn here — the timer will call check_and_respawn after 10s,
--  which avoids double-spawn LBM + on_construct/timer)
minetest.register_lbm({
    name              = "radar_atc:respawn_dish",
    nodenames         = {"radar_atc:transponder"},
    run_at_every_load = true,
    action = function(pos)
        -- Use minetest.after with a random delay [1.0, 2.5]
        -- to avoid all transponders loading at the same time
        -- AND to give time for already-serialized entities to activate
        local delay = 1.0 + math.random() * 1.5
        minetest.after(delay, function()
            -- Check that the node is still there
            if minetest.get_node(pos).name == "radar_atc:transponder" then
                check_and_respawn(pos)
                minetest.get_node_timer(pos):start(10)
            end
        end)
    end,
})


-- =============================================================
--  CRAFT ITEMS  (non-placeable, technical components)
-- =============================================================
local function register_craft_item(name, desc, texture)
    minetest.register_craftitem("radar_atc:" .. name, {
        description = desc,
        inventory_image = texture,
        groups = {not_in_creative_inventory=1},
    })
end

register_craft_item("module_com",
    S("ATC Communication Module\n(Component — not placeable)"),
    "radar_atc_module_com.png")

register_craft_item("parabole",
    S("Reception Dish\n(Component — not placeable)"),
    "radar_atc_parabole.png")

register_craft_item("waveguide",
    S("Microwave Waveguide\n(Component — not placeable)"),
    "radar_atc_waveguide.png")

register_craft_item("magnetron",
    S("Radar Magnetron\n(Component — not placeable)"),
    "radar_atc_magnetron.png")

register_craft_item("rotator",
    S("Azimuth Rotator Motor\n(Component — not placeable)"),
    "radar_atc_rotator.png")

-- Component crafts
if minetest.get_modpath("default") then
    -- Communication module: mese circuit + copper + gold
    minetest.register_craft({
        output = "radar_atc:module_com",
        recipe = {
            {"default:gold_ingot",    "default:mese_crystal",  "default:gold_ingot"},
            {"default:copper_ingot",  "default:steel_ingot",   "default:copper_ingot"},
            {"default:gold_ingot",    "default:mese_crystal",  "default:gold_ingot"},
        },
    })
    -- Reception dish: steel + diamond (polished surface)
    minetest.register_craft({
        output = "radar_atc:parabole",
        recipe = {
            {"default:steel_ingot",   "",                      "default:steel_ingot"},
            {"default:steel_ingot",   "default:diamond",       "default:steel_ingot"},
            {"",                      "default:steel_ingot",   ""},
        },
    })
    -- Waveguide: copper + gold (high conductivity)
    minetest.register_craft({
        output = "radar_atc:waveguide 2",
        recipe = {
            {"default:copper_ingot",  "default:gold_ingot",    "default:copper_ingot"},
            {"default:copper_ingot",  "",                      "default:copper_ingot"},
            {"default:copper_ingot",  "default:gold_ingot",    "default:copper_ingot"},
        },
    })
    -- Magnetron: mese + steel + magnet (obsidian)
    minetest.register_craft({
        output = "radar_atc:magnetron",
        recipe = {
            {"default:obsidian",      "default:steel_ingot",   "default:obsidian"},
            {"default:steel_ingot",   "default:mese",          "default:steel_ingot"},
            {"default:obsidian",      "default:steel_ingot",   "default:obsidian"},
        },
    })
    -- Rotation motor: steel + copper + mese
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
    -- ASR Transponder: magnetron + dish + rotator + com module + steel
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
--  LINK ANTENNA  radar_atc:link_antenna
--
--  Allows taking control of a remote airport
--  WITHOUT a password (or as an alternative to the password).
-- =============================================================

-- =============================================================
--  LINK ANTENNA ENTITY (fixed mesh, no rotation)
-- =============================================================
minetest.register_entity("radar_atc:link_antenna_entity", {
    initial_properties = {
        physical=false, collide_with_objects=false, pointable=false,
        static_save=false, visual="mesh", mesh="link_antenna.obj",
        textures={"link_antenna_tex.png"}, visual_size={x=15,y=15,z=15}, glow=0,
    },
    _node_pos = nil,
    on_activate = function(self) self.object:set_armor_groups({immortal=1}) end,
    on_step = function(self)
        if self._node_pos then
            if minetest.get_node(self._node_pos).name ~= "radar_atc:link_antenna" then
                self.object:remove()
            end
        end
    end,
    on_deactivate = function(self) end,
})

local LINK_PIVOT_Y = - 0.5    -- mesh bottom pivot = anchor node level

local function spawn_link(pos)
    local ep = {x=pos.x, y=pos.y + LINK_PIVOT_Y, z=pos.z}
    local obj = minetest.add_entity(ep, "radar_atc:link_antenna_entity")
    if obj then
        local ent = obj:get_luaentity()
        if ent then ent._node_pos = {x=pos.x,y=pos.y,z=pos.z} end
    end
end

local function remove_link(pos)
    local cp = {x=pos.x, y=pos.y+LINK_PIVOT_Y, z=pos.z}
    for _, obj in ipairs(minetest.get_objects_inside_radius(cp, 3.0)) do
        local ent = obj:get_luaentity()
        if ent and ent.name=="radar_atc:link_antenna_entity" then obj:remove() end
    end
end

local function check_link(pos)
    local cp = {x=pos.x, y=pos.y+LINK_PIVOT_Y, z=pos.z}
    for _, obj in ipairs(minetest.get_objects_inside_radius(cp, 3.0)) do
        local ent = obj:get_luaentity()
        if ent and ent.name=="radar_atc:link_antenna_entity" then return end
    end
    spawn_link(pos)
end

minetest.register_node("radar_atc:link_antenna", {
    description         = S("ATC Link Antenna"),
    drawtype            = "nodebox",
    tiles               = {"radar_atc_radar_base.png"},
    inventory_image     = "radar_atc_link_antenna.png",
    paramtype           = "light",
    sunlight_propagates = true,
    groups              = {cracky=2},
    sounds              = minetest.get_modpath("default")
                          and default.node_sound_metal_defaults() or {},
    selection_box = {type="fixed", fixed={-0.5,-0.5,-0.5, 0.5,0.2,0.5}},
    collision_box = {type="fixed", fixed={-0.5,-0.5,-0.5, 0.5,0.5, 0.5}},
    node_box      = {type="fixed", fixed={{-0.45,-0.5,-0.45, 0.45, 0.0,0.45}}},

    on_construct = function(pos)
        minetest.get_meta(pos):set_string("infotext",
            "ATC Link Antenna\n" ..
            S("Allows connection to any airport without password\nfrom a radar within @1 blocks.", CFG.transponder_link_r or 75))
        minetest.after(0.5, spawn_link, pos)
        minetest.get_node_timer(pos):start(12)
    end,
    on_destruct = function(pos) remove_link(pos) end,
    on_timer    = function(pos) check_link(pos); return true end,
})

minetest.register_lbm({
    name              = "radar_atc:respawn_link",
    nodenames         = {"radar_atc:link_antenna"},
    run_at_every_load = true,
    action = function(pos)
        minetest.get_node_timer(pos):start(12)
        minetest.after(1.0 + math.random() * 1.5, function()
            if minetest.get_node(pos).name == "radar_atc:link_antenna" then
                check_link(pos)
            end
        end)
    end,
})

if minetest.get_modpath("default") then
    -- Link antenna: dish + waveguide + com module (no rotator)
    minetest.register_craft({
        output = "radar_atc:link_antenna",
        recipe = {
            {"",                    "radar_atc:parabole",   ""},
            {"radar_atc:waveguide", "radar_atc:module_com", "radar_atc:waveguide"},
            {"default:steelblock",  "radar_atc:magnetron",  "default:steelblock"},
        },
    })
end

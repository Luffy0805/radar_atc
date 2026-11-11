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
            if (airports[i].has_transponder or false) ~= present then
                airports[i].has_transponder = present
                save_airports()
            end
            return
        end
    end
end

-- =============================================================
--  NODE SEARCH AROUND A POSITION (transponder, link antenna)
--  find_nodes_in_area() on a cube of radius r reads (2r+1)³ nodes
--  (3.4 million for r = 75) and loads every mapblock of the cube from
--  the database. It used to run on every radar refresh (every 3 s per
--  open laptop), which could lag a server until it had to be restarted.
--  Results are now cached for SEARCH_TTL seconds (cleared as soon as a
--  transponder or link antenna is placed or removed), and an area whose
--  centre is not loaded is never searched (no loading from disk).
-- =============================================================
local SEARCH_TTL   = 60
local search_cache = {}   -- [nodename .. "@" .. pk(pos)] = {t = os.time(), found = bool}

local function clear_search_cache()
    search_cache = {}
end

local function node_in_cube(center, nodename)
    local key = nodename .. "@" .. pk(center)
    local c = search_cache[key]
    local now = os.time()
    if c and now - c.t < SEARCH_TTL then return c.found end
    if minetest.get_node_or_nil(center) == nil then
        -- area not loaded: do not load ~1000 mapblocks; keep the last answer
        return c and c.found or false
    end
    local r = CFG.transponder_link_r
    local nodes = minetest.find_nodes_in_area(
        {x=center.x-r, y=center.y-r, z=center.z-r},
        {x=center.x+r, y=center.y+r, z=center.z+r},
        {nodename})
    local found = #nodes > 0
    search_cache[key] = {t = now, found = found}
    return found
end

-- Checks that a transponder serves the radar centred on ap_center.
-- 1. stored flag of the airport at that position, or of the nearest airport
--    within airport_link_r (kept up to date when a transponder is placed,
--    removed or loaded);
-- 2. otherwise a physical search around ap_center (cached, loaded areas only).
function transponder_ok(ap_center, radius)
    if not CFG.transponder_enabled then return true end
    if radius <= CFG.transponder_free_radius then return true end
    if not ap_center then return false end
    local ap
    for _, a in ipairs(get_airports()) do
        if a.pos and math.abs(a.pos.x - ap_center.x) < 2 and math.abs(a.pos.y - ap_center.y) < 2
           and math.abs(a.pos.z - ap_center.z) < 2 then
            ap = a; break
        end
    end
    ap = ap or linked_ap(ap_center)
    if ap and ap.has_transponder then return true end
    if not node_in_cube(ap_center, "radar_atc:transponder") then return false end
    if ap then
        ap.has_transponder = true   -- remember it: next time the flag is enough
        save_airports()
    end
    return true
end

-- Checks that a link antenna exists near the COMPUTER (ordi_pos).
-- No configuration required: its mere presence is enough.
function link_antenna_ok(ordi_pos)
    if not ordi_pos then return false end
    return node_in_cube(ordi_pos, "radar_atc:link_antenna")
end

-- ─────────────────────────────────────────────────────────────
--  OFFSETS (mesh pivot adjustments)
-- ─────────────────────────────────────────────────────────────
local BASE_Y       = -1.00
local DISH_Y       =  3.00
local ORPHAN_CHECK =  2.0   -- s between two "is my node still there?" checks

-- on_step shared by the decoration entities: removes the entity when its
-- anchor node is gone (e.g. removed without on_destruct, by WorldEdit).
-- Checked every ORPHAN_CHECK s instead of every server step.
local function orphan_step(nodename)
    return function(self, dtime)
        self._check = (self._check or 0) + dtime
        if self._check < ORPHAN_CHECK then return end
        self._check = 0
        if self._node_pos and minetest.get_node(self._node_pos).name ~= nodename then
            self.object:remove()
        end
    end
end

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
    on_step = orphan_step("radar_atc:transponder"),
})

-- =============================================================
--  DISH ENTITY (rotating)
--  automatic_rotate: the client turns the dish by itself. It used to be
--  turned by the server with set_rotation() at every server step, which
--  sent a rotation update to every player around ~10 times per second.
-- =============================================================
minetest.register_entity("radar_atc:radar_dish", {
    initial_properties = {
        physical=false, collide_with_objects=false, pointable=false,
        static_save=false, visual="mesh", mesh="radar_dish.obj",
        textures={"radar_dish_palette.png"}, visual_size={x=10,y=10,z=10}, glow=0,
        automatic_rotate = CFG.transponder_rotation_speed,
    },
    _node_pos = nil,
    on_activate = function(self) self.object:set_armor_groups({immortal=1}) end,
    on_step = orphan_step("radar_atc:transponder"),
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
                -- Verify that this is indeed linked to THIS node
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
            {-0.50,-0.50,-0.50,  0.50, 0.50, 0.50},  -- full cube (complete collision)
        },
    },
    on_construct = function(pos)
        minetest.get_meta(pos):set_string("infotext","ASR Radar Antenna\n(active)")
        minetest.after(0.5, spawn_all, pos)
        minetest.get_node_timer(pos):start(10)
        minetest.after(0.1, function() transponder_notify(pos, true) end)
        clear_search_cache()
    end,
    on_destruct = function(pos)
        remove_all(pos)
        transponder_notify(pos, false)
        clear_search_cache()
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
                -- keeps the airport flag right, even for a transponder placed
                -- before its airport was created
                transponder_notify(pos, true)
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
        groups = {},
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

-- =============================================================
--  CRAFT RECIPES — Minetest Game (default)
-- =============================================================

if minetest.get_modpath("default") then
    -- Communication module: gold + mese crystal (circuitry) + copper
    minetest.register_craft({
        output = "radar_atc:module_com",
        recipe = {
            {"default:gold_ingot",   "default:mese_crystal", "default:gold_ingot"},
            {"default:copper_ingot", "default:steel_ingot",  "default:copper_ingot"},
            {"default:gold_ingot",   "default:mese_crystal", "default:gold_ingot"},
        },
    })

    -- Reception dish: steel (shaped reflector) + diamond (polished surface)
    minetest.register_craft({
        output = "radar_atc:parabole",
        recipe = {
            {"default:steel_ingot", "",               "default:steel_ingot"},
            {"default:steel_ingot", "default:diamond","default:steel_ingot"},
            {"",                    "default:steel_ingot", ""},
        },
    })

    -- Waveguide: copper + gold tubes (high conductivity), yields 2
    minetest.register_craft({
        output = "radar_atc:waveguide 2",
        recipe = {
            {"default:copper_ingot", "default:gold_ingot",   "default:copper_ingot"},
            {"default:copper_ingot", "",                     "default:copper_ingot"},
            {"default:copper_ingot", "default:gold_ingot",   "default:copper_ingot"},
        },
    })

    -- Magnetron: obsidian (magnetic) + steel + mese block (high-power emitter)
    minetest.register_craft({
        output = "radar_atc:magnetron",
        recipe = {
            {"default:obsidian",     "default:steel_ingot",  "default:obsidian"},
            {"default:steel_ingot",  "default:mese",         "default:steel_ingot"},
            {"default:obsidian",     "default:steel_ingot",  "default:obsidian"},
        },
    })

    -- Azimuth rotator motor: steel + copper windings + mese crystal
    minetest.register_craft({
        output = "radar_atc:rotator",
        recipe = {
            {"default:steel_ingot",  "default:copper_ingot", "default:steel_ingot"},
            {"default:copper_ingot", "default:mese_crystal", "default:copper_ingot"},
            {"default:steel_ingot",  "default:copper_ingot", "default:steel_ingot"},
        },
    })

    -- ASR Transponder: dish + magnetron + waveguide + rotator + com module
    minetest.register_craft({
        output = "radar_atc:transponder",
        recipe = {
            {"radar_atc:parabole",  "radar_atc:magnetron",  "radar_atc:parabole"},
            {"radar_atc:waveguide", "radar_atc:rotator",    "radar_atc:waveguide"},
            {"default:steelblock",  "radar_atc:module_com", "default:steelblock"},
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
    on_step = orphan_step("radar_atc:link_antenna"),
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
        clear_search_cache()
    end,
    on_destruct = function(pos) remove_link(pos); clear_search_cache() end,
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
    -- Link antenna: dish + waveguide + com module + magnetron
    minetest.register_craft({
        output = "radar_atc:link_antenna",
        recipe = {
            {"",                    "radar_atc:parabole",   ""},
            {"radar_atc:waveguide", "radar_atc:module_com", "radar_atc:waveguide"},
            {"default:steelblock",  "radar_atc:magnetron",  "default:steelblock"},
        },
    })
end

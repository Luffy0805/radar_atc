-- =============================================================
-- radar_atc/transponder.lua  —  Antenne Radar ASR (réaliste)
-- =============================================================

function transponder_ok(radar_pos, radius)
    if not CFG.transponder_enabled then return true end
    if radius <= CFG.transponder_free_radius then return true end
    local r = CFG.transponder_link_r or 75
    local nodes = minetest.find_nodes_in_area(
        {x=radar_pos.x-r, y=radar_pos.y-r, z=radar_pos.z-r},
        {x=radar_pos.x+r, y=radar_pos.y+r, z=radar_pos.z+r},
        {"radar_atc:transponder"}
    )
    return #nodes > 0
end

-- ─────────────────────────────────────────────────────────────
--  OFFSETS  (à ajuster si nécessaire)
--
--  Minetest : y=0 du mesh OBJ = position Y de l'entité
--  visual_size=10 => 1 unité OBJ = 1 bloc
--
--  radar_base.obj  : y=0 (bas piédestal) → y=4.40 (sommet mât)
--  radar_dish.obj  : y=-1.85 (bas mât)   → y=~1.80 (sommet IFF)
--                    pivot y=0 = bas de la bague de rotation
--
--  On pose le nœud ancre au sol.
--  BASE : entité à nœud.y + BASE_Y  → bas du piédestal à nœud.y + BASE_Y
--  DISH : entité à nœud.y + DISH_Y  → pivot antenne sur le mât de la base
-- ─────────────────────────────────────────────────────────────
local BASE_Y      = -1.00   -- le bas du socle OBJ arrive à 0.5 blocs au-dessus du nœud ancre
local DISH_Y      = 3.00   -- pivot antenne = sommet du mât base (4.40) + BASE_Y (0.50)

local WAKE_RADIUS = 48
local SLEEP_CHECK = 2.0

-- =============================================================
--  ENTITE SOCLE (fixe)
-- =============================================================
minetest.register_entity("radar_atc:radar_base_entity", {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        static_save          = false,
        visual               = "mesh",
        mesh                 = "radar_base.obj",
        textures             = {"radar_dish_palette.png"},
        visual_size          = {x=5, y=5, z=5},
        glow                 = 0,
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
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        static_save          = false,
        visual               = "mesh",
        mesh                 = "radar_dish.obj",
        textures             = {"radar_dish_palette.png"},
        visual_size          = {x=10, y=10, z=10},
        glow                 = 0,
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
-- =============================================================
local function spawn_all(pos)
    local function place(ename, offset)
        local ep = {x=pos.x, y=pos.y+offset, z=pos.z}
        local obj = minetest.add_entity(ep, ename)
        if obj then
            local ent = obj:get_luaentity()
            if ent then ent._node_pos = {x=pos.x,y=pos.y,z=pos.z} end
        end
    end
    place("radar_atc:radar_base_entity", BASE_Y)
    place("radar_atc:radar_dish",        DISH_Y)
end

local function remove_all(pos)
    for dy = 0, math.ceil(DISH_Y)+2 do
        for _, obj in ipairs(minetest.get_objects_inside_radius(
                {x=pos.x, y=pos.y+dy, z=pos.z}, 3.0)) do
            local ent = obj:get_luaentity()
            if ent then
                local n = ent.name or ""
                if n=="radar_atc:radar_dish" or n=="radar_atc:radar_base_entity" then
                    obj:remove()
                end
            end
        end
    end
end

local function check_and_respawn(pos)
    local dish_ok, base_ok = false, false
    for dy = 0, math.ceil(DISH_Y)+2 do
        for _, obj in ipairs(minetest.get_objects_inside_radius(
                {x=pos.x, y=pos.y+dy, z=pos.z}, 3.0)) do
            local ent = obj:get_luaentity()
            if ent then
                if ent.name=="radar_atc:radar_dish"        then dish_ok=true end
                if ent.name=="radar_atc:radar_base_entity" then base_ok=true end
            end
        end
    end
    if not dish_ok or not base_ok then remove_all(pos); spawn_all(pos) end
end

-- =============================================================
--  NŒUD ANCRE
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
            {-0.45,-0.50,-0.45,  0.45,-0.40, 0.45},  -- platine sol
            {-0.08,-0.40,-0.08,  0.08, 0.50, 0.08},  -- tige de fixation
        },
    },
    on_construct = function(pos)
        minetest.get_meta(pos):set_string("infotext","Antenne Radar ASR\n(active)")
        minetest.after(0.5, spawn_all, pos)
        minetest.get_node_timer(pos):start(10)
    end,
    on_destruct = function(pos) remove_all(pos) end,
    on_timer    = function(pos) check_and_respawn(pos); return true end,
})

minetest.register_lbm({
    name              = "radar_atc:respawn_dish",
    nodenames         = {"radar_atc:transponder"},
    run_at_every_load = true,
    action = function(pos)
        minetest.get_node_timer(pos):start(10)
        minetest.after(1.5, spawn_all, pos)
    end,
})

if minetest.get_modpath("default") then
    minetest.register_craft({
        output = "radar_atc:transponder",
        recipe = {
            {"default:diamondblock",	"default:mese",			"default:diamondblock"},
            {"default:steelblock",		"dye:red",				"default:steelblock"},
            {"default:diamondblock",    "default:steelblock",	"default:diamondblock"},
        },
    })
end

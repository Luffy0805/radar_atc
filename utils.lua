-- =============================================================
-- radar_atc/utils.lua  —  Conversions, geography, formspec helpers
-- =============================================================

-- =============================================================
--  UNIT CONVERSIONS
-- =============================================================
function yaw2head(y)
    return math.floor(((math.deg(y) + 180) % 360) + 0.5) % 360
end

function head2card(h)
    local d = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                "S","SSW","SW","WSW","W","WNW","NW","NNW"}
    return d[math.floor((h + 11.25) / 22.5) % 16 + 1]
end

function d2d(a, b)
    return math.floor(math.sqrt((a.x-b.x)^2 + (a.z-b.z)^2) + 0.5)
end

function d3d(a, b)
    return math.floor(math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2) + 0.5)
end

function hspd(v)  return math.sqrt((v.x or 0)^2 + (v.z or 0)^2) end
function to_kmh(ms) return math.floor(ms * 3.6 + 0.5) end
function to_kt(ms)  return math.floor(ms * 1.944 + 0.5) end
function to_ft(y)   return math.floor(y * 3.281 + 0.5) end
function to_fl(y)   return math.floor(y * 3.281 / 100 + 0.5) end

function fmt_alt(y)
    local m = math.floor(y + 0.5); local f = to_ft(y); local l = to_fl(y)
    if l >= 10 then return string.format("FL%03d | %dm | %dft", l, m, f) end
    return string.format("%dm | %dft", m, f)
end

function fmt_spd(ms)
    return string.format("%dkm/h | %dkt", to_kmh(ms), to_kt(ms))
end

function climb_s(r)
    if not r then return "~" end
    if r > 0.3  then return "^" end
    if r < -0.3 then return "v" end
    return "~"
end

-- =============================================================
--  GEOGRAPHY / AIRPORTS
-- =============================================================
function bearing(p1, p2)
    return math.deg(math.atan2(p2.x - p1.x, -(p2.z - p1.z))) % 360
end

function rwy_num(b)
    local n = math.floor((b + 5) / 10) % 36
    return n == 0 and 36 or n
end

function rwy_name(p1, p2, suffix)
    local b1 = bearing(p1, p2)
    local n1 = rwy_num(b1); local n2 = rwy_num((b1 + 180) % 360)
    local s = (suffix or ""):upper():gsub("[^LRC]", ""):sub(1, 1)
    local so = s == "L" and "R" or (s == "R" and "L" or s)
    local lo, hi = n1, n2
    if n1 > n2 then lo, hi = n2, n1; s, so = so, s end
    return string.format("%02d%s/%02d%s", lo, so, hi, s)
end

-- Heading → cardinal direction text
function cap_to_dir(cap)
    local dirs = {"north","north-northeast","northeast","east-northeast",
                  "east","east-southeast","southeast","south-southeast",
                  "south","south-southwest","southwest","west-southwest",
                  "west","west-northwest","northwest","north-northwest"}
    return dirs[math.floor((cap + 11.25) / 22.5) % 16 + 1]
end

function nearest_ap(pos)
    local best, bd = nil, math.huge
    for _, a in ipairs(get_airports()) do
        if a.pos then
            local d = d3d(pos, a.pos)
            if d < bd then bd = d; best = a end
        end
    end
    return best, bd
end

function linked_ap(cpos)
    local best, bd = nil, math.huge
    for _, a in ipairs(get_airports()) do
        if a.pos then
            local d = d3d(cpos, a.pos)
            if d <= CFG.airport_link_r and d < bd then bd = d; best = a end
        end
    end
    return best
end

function rw_len(rw)
    if not (rw.p1 and rw.p2) then return 0 end
    return d3d(rw.p1, rw.p2)
end

-- =============================================================
--  RADAR PROJECTION
-- =============================================================
function w2r(tp, cp, radius)
    local dx = (tp.x - cp.x) / radius
    local dz = -(tp.z - cp.z) / radius
    local sx = CFG.RW / 2 + dx * CFG.RW / 2
    local sy = CFG.RH / 2 + dz * CFG.RH / 2
    -- Returns nil if outside radar (no clamping at center)
    if sx < 0.05 or sx > CFG.RW - 0.25 or sy < 0.05 or sy > CFG.RH - 0.25 then
        return nil, nil
    end
    return sx, sy
end

-- Clip the segment [p1→p2] (world coords) to the radar rectangle.
-- Returns (x1,y1, x2,y2) in formspec coords, or nil if the segment is
-- entirely outside the radar.
-- Liang-Barsky algorithm: preserves exactly the p1→p2 orientation.
function clip_segment(p1, p2, cp, radius)
    local xmin, xmax = 0.05, CFG.RW - 0.25
    local ymin, ymax = 0.05, CFG.RH - 0.25

    -- Project both endpoints to formspec coords
    local ax = CFG.RW / 2 + (p1.x - cp.x) / radius * CFG.RW / 2
    local ay = CFG.RH / 2 - (p1.z - cp.z) / radius * CFG.RH / 2
    local bx = CFG.RW / 2 + (p2.x - cp.x) / radius * CFG.RW / 2
    local by = CFG.RH / 2 - (p2.z - cp.z) / radius * CFG.RH / 2

    local dx = bx - ax
    local dy = by - ay
    local t0, t1 = 0.0, 1.0

    -- Liang-Barsky: 4 edges
    local function clip(p, q)
        if p == 0 then return q >= 0 end  -- parallel: inside if q>=0
        local r = q / p
        if p < 0 then
            if r > t1 then return false end
            if r > t0 then t0 = r end
        else
            if r < t0 then return false end
            if r < t1 then t1 = r end
        end
        return true
    end

    if not clip(-dx, ax - xmin) then return nil end
    if not clip( dx, xmax - ax) then return nil end
    if not clip(-dy, ay - ymin) then return nil end
    if not clip( dy, ymax - ay) then return nil end

    if t0 > t1 then return nil end

    return ax + t0 * dx, ay + t0 * dy,
           ax + t1 * dx, ay + t1 * dy
end

-- Compat: kept to avoid breaking any existing calls.
-- Prefer clip_segment for drawing segments.
function w2r_clamp(tp, cp, radius)
    local dx = (tp.x - cp.x) / radius
    local dz = -(tp.z - cp.z) / radius
    local sx = CFG.RW / 2 + dx * CFG.RW / 2
    local sy = CFG.RH / 2 + dz * CFG.RH / 2
    local x0, y0 = CFG.RW / 2, CFG.RH / 2
    local xmin, xmax = 0.05, CFG.RW - 0.25
    local ymin, ymax = 0.05, CFG.RH - 0.25
    if sx >= xmin and sx <= xmax and sy >= ymin and sy <= ymax then
        return sx, sy
    end
    local rx, ry = sx - x0, sy - y0
    local t = 1.0
    if rx > 0 then t = math.min(t, (xmax - x0) / rx)
    elseif rx < 0 then t = math.min(t, (xmin - x0) / rx) end
    if ry > 0 then t = math.min(t, (ymax - y0) / ry)
    elseif ry < 0 then t = math.min(t, (ymin - y0) / ry) end
    return x0 + rx * t, y0 + ry * t
end

-- =============================================================
--  FORMSPEC HELPERS
-- =============================================================
function fe(s)  return minetest.formspec_escape(tostring(s or "")) end
function clr(c, t) return minetest.colorize(c, tostring(t or "")) end

function mkdd(x, y, w, name, items, sel_val)
    local idx = 1; local strs = {}
    for i, v in ipairs(items) do
        strs[i] = tostring(v)
        if v == sel_val then idx = i end
    end
    return string.format("dropdown[%.2f,%.2f;%.2f,0.60;%s;%s;%d]",
        x, y, w, name, table.concat(strs, ","), idx)
end

function scroll_box(x, y, w, h, name)
    return string.format("scroll_container[%.2f,%.2f;%.2f,%.2f;%s;vertical]", x, y, w, h, name)
end

function scroll_bar(x, y, h, name)
    return string.format("scrollbar[%.2f,%.2f;0.25,%.2f;vertical;%s;0]", x, y, h, name)
end

-- Position key (to identify a node in active_nodes)
function pk(pos)
    return math.floor(pos.x).."_"..math.floor(pos.y).."_"..math.floor(pos.z)
end

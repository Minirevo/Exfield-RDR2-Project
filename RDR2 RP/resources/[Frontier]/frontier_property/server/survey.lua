local MIN_VERTICES = 3
local MAX_VERTICES = 64
local WORLD_LIMIT = 1000000

local function coordinate(value)
    return type(value) == 'number' and value == value and math.abs(value) <= WORLD_LIMIT
end

local function turn(a, b, c)
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
end

local function onSegment(a, b, p)
    return turn(a, b, p) == 0 and p.x >= math.min(a.x, b.x) and p.x <= math.max(a.x, b.x)
        and p.y >= math.min(a.y, b.y) and p.y <= math.max(a.y, b.y)
end

local function intersects(a, b, c, d)
    local ca, da, ac, bc = turn(a, b, c), turn(a, b, d), turn(c, d, a), turn(c, d, b)
    if ca == 0 and onSegment(a, b, c) or da == 0 and onSegment(a, b, d)
        or ac == 0 and onSegment(c, d, a) or bc == 0 and onSegment(c, d, b) then
        return true
    end
    return ((ca > 0 and da < 0) or (ca < 0 and da > 0))
        and ((ac > 0 and bc < 0) or (ac < 0 and bc > 0))
end

local function nextIndex(index, count)
    return index % count + 1
end

local function polygon(points)
    if type(points) ~= 'table' or #points < MIN_VERTICES or #points > MAX_VERTICES then
        return nil, 'invalid_vertex_count'
    end
    local normalized, seen = {}, {}
    for i = 1, #points do
        local p = points[i]
        if type(p) ~= 'table' or not coordinate(p.x) or not coordinate(p.y) then
            return nil, 'invalid_coordinate'
        end
        local x, y = math.floor(p.x * 100 + 0.5), math.floor(p.y * 100 + 0.5)
        local key = x .. ':' .. y
        if seen[key] then return nil, 'duplicate_vertex' end
        seen[key], normalized[i] = true, { x = x, y = y }
    end
    local area2, n = 0, #normalized
    for i, a in ipairs(normalized) do
        local j = nextIndex(i, n)
        local b, c = normalized[j], normalized[nextIndex(j, n)]
        if onSegment(a, b, c) or onSegment(b, c, a) then return nil, 'overlapping_edge' end
        area2 = area2 + a.x * b.y - a.y * b.x
        for k = i + 2, n do
            if not (i == 1 and k == n)
                and intersects(a, b, normalized[k], normalized[nextIndex(k, n)]) then
                return nil, 'self_intersection'
            end
        end
    end
    if area2 == 0 then return nil, 'zero_area' end
    return normalized, math.abs(area2) / 20000
end

-- Classify a point without division on the integer grid. Boundary is distinct.
local function locate(points, point)
    local inside = false
    for i, a in ipairs(points) do
        local b = points[nextIndex(i, #points)]
        if onSegment(a, b, point) then return 'boundary' end
        if (a.y > point.y) ~= (b.y > point.y) and (turn(a, b, point) > 0) == (b.y > a.y) then
            inside = not inside
        end
    end
    return inside and 'interior' or 'outside'
end

local function contact(left, right)
    for i, a in ipairs(left) do
        local b = left[nextIndex(i, #left)]
        for j, c in ipairs(right) do
            if intersects(a, b, c, right[nextIndex(j, #right)]) then return true end
        end
    end
    return false
end

function ValidatePropertySurvey(points, allowedZone, blockedZones)
    local plot, area = polygon(points)
    if not plot then return nil, area end
    if area < PropertyConfig.SurveyMinArea or area > PropertyConfig.SurveyMaxArea then
        return nil, 'invalid_area'
    end
    local zone = polygon(allowedZone)
    if not zone then return nil, 'invalid_allowed_zone' end
    if contact(plot, zone) then return nil, 'outside_zone' end
    for _, point in ipairs(plot) do
        if locate(zone, point) ~= 'interior' then return nil, 'outside_zone' end
    end
    if type(blockedZones) ~= 'table' then return nil, 'invalid_blocked_zones' end
    for _, blockedPoints in ipairs(blockedZones) do
        local blocked = polygon(blockedPoints)
        if not blocked then return nil, 'invalid_blocked_zone' end
        if contact(plot, blocked) or locate(plot, blocked[1]) ~= 'outside'
            or locate(blocked, plot[1]) ~= 'outside' then
            return nil, 'blocked_overlap'
        end
    end
    return area
end

-- Call only with authoritative allowed and blocked polygons, in metres.
exports('ValidatePropertySurvey', ValidatePropertySurvey)

local validate
exports = function(name, fn)
    assert(name == 'ValidatePropertySurvey')
    validate = fn
end
local root = ... or '.'
dofile(root .. '/config.lua')
dofile(root .. '/server/survey.lua')
local function points(...)
    local v, result = { ... }, {}
    for i = 1, #v, 2 do result[#result + 1] = { x = v[i], y = v[i + 1] } end
    return result
end
local zone = points(0,0, 100,0, 100,100, 0,100)
local square = points(10,10, 20,10, 20,20, 10,20)
assert(validate(square, zone, {}) == 100)
assert(validate(points(10,20, 20,20, 20,10, 10,10), zone, {}) == 100)
local function rejects(expected, plot, allowed, blocked)
    local area, issue = validate(plot, allowed, blocked)
    assert(not area and issue == expected, tostring(issue))
end
rejects('self_intersection', points(10,10, 20,20, 20,10, 10,20), zone, {})
rejects('duplicate_vertex', points(10,10, 20,10, 20,20, 10.004,10), zone, {})
rejects('overlapping_edge', points(10,10, 20,10, 18,10, 18,20, 10,20), zone, {})
rejects('invalid_area', points(10,10, 11,10, 11,11, 10,11), zone, {})
rejects('outside_zone', points(0,0, 10,0, 10,10, 0,10), zone, {})
rejects('outside_zone', points(30,30, 70,30, 70,70, 30,70),
    points(0,0, 100,0, 100,100, 60,100, 60,40, 40,40, 40,100, 0,100), {})
rejects('blocked_overlap', square, zone, { points(20,10, 25,10, 25,15, 20,15) })
rejects('blocked_overlap', square, zone, { points(11,11, 12,11, 12,12, 11,12) })
rejects('blocked_overlap', square, zone, { points(5,5, 25,5, 25,25, 5,25) })
rejects('invalid_blocked_zone', square, zone, { {} })
print('Property survey geometry passed')

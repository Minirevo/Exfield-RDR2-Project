-- Watson's Cabin. Check the stand points and furnishable volume on the server's game build.
PropertyHouses = {
    watson = {
        label = 'Watson’s Cabin',
        interior = 53250,
        door = {x=-1815.15,y=654.96,z=130.88},
        entry = {x=-1817.71,y=658.42,z=131.30},
        min = {x=-1820.2,y=656.4,z=130.85},
        max = {x=-1815.9,y=660.4,z=133.25},
        capacity = 25,
    },
}

function PropertyHouseWithin(point, room, margin)
    return point.x >= room.min.x+margin and point.x <= room.max.x-margin
        and point.y >= room.min.y+margin and point.y <= room.max.y-margin
        and point.z >= room.min.z and point.z <= room.max.z
end

function PropertyHouseNear(a, b, radius)
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 <= radius^2
end

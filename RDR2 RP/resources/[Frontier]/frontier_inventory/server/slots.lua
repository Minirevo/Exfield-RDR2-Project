local function copy(stack, quantity)
    return { item = stack.item, quantity = quantity, metadata = stack.metadata, instance = stack.instance }
end

function Inventory.Weight(container)
    local weight = 0
    for _, stack in pairs(container.slots) do
        weight = weight + Inventory.items[stack.item].grams * stack.quantity
    end
    return weight
end

local function compatible(a, b)
    return a.item == b.item and a.metadata == b.metadata and not a.instance and not b.instance
end

function Inventory.Place(container, stack, at)
    local def = Inventory.items[stack.item]
    if not def then return false, 'invalid_item' end
    if Inventory.Weight(container) + stack.quantity * def.grams > container.weight_limit then
        return false, 'weight'
    end
    local left = stack.quantity
    if at then
        if not Inventory.Int(at, container.slot_limit) then return false, 'invalid_slot' end
        local existing = container.slots[at]
        if existing then
            if not compatible(existing, stack) or existing.quantity + left > def.maxStack then
                return false, 'stack_conflict'
            end
            existing.quantity = existing.quantity + left
        else
            if left > def.maxStack then return false, 'stack_conflict' end
            container.slots[at] = copy(stack, left)
        end
        return true
    end
    for slot = 1, container.slot_limit do
        local existing = container.slots[slot]
        if existing and compatible(existing, stack) then
            local merged = math.min(left, def.maxStack - existing.quantity)
            existing.quantity = existing.quantity + merged
            left = left - merged
            if left == 0 then return true end
        end
    end
    for slot = 1, container.slot_limit do
        if not container.slots[slot] then
            local quantity = math.min(left, def.maxStack)
            container.slots[slot] = copy(stack, quantity)
            left = left - quantity
            if left == 0 then return true end
        end
    end
    return false, 'slots'
end

function Inventory.Take(container, slot, quantity)
    if not Inventory.Int(slot, container.slot_limit) then return false, 'invalid_slot' end
    local stack = container.slots[slot]
    if not stack then return false, 'not_found' end
    if not Inventory.Int(quantity, stack.quantity) then return false, 'quantity' end
    local removed = copy(stack, quantity)
    stack.quantity = stack.quantity - quantity
    if stack.quantity == 0 then container.slots[slot] = nil end
    return true, removed
end

function Inventory.Move(container, from, to, quantity, split)
    if from == to or not Inventory.Int(to, container.slot_limit) then return false, 'invalid_slot' end
    local existing = container.slots[from]
    if split and (container.slots[to] or not existing or not Inventory.Int(quantity, existing.quantity - 1)) then
        return false, 'stack_conflict'
    end
    local ok, stack = Inventory.Take(container, from, quantity)
    if not ok then return false, stack end
    return Inventory.Place(container, stack, to)
end

function Inventory.Present(container, forBrowser)
    local slots, used = {}, 0
    for slot, stack in pairs(container.slots) do
        local item = Inventory.items[stack.item]
        used = used + 1
        slots[#slots + 1] = { slot = slot, item = stack.item, name = item.name, description = item.description,
            quantity = stack.quantity, grams = item.grams, usable = item.usable, drop = item.drop,
            transfer = item.transfer, store = item.store, metadata = stack.metadata, instance = stack.instance,
            category=item.category, icon=item.icon, maxStack=item.maxStack, classification=item.classification, beltEligible=Inventory.BeltEligible(stack.item) }
    end
    table.sort(slots, function(a, b) return a.slot < b.slot end)
    return { slots = slots, capacity = container.slot_limit, weight = Inventory.Weight(container),
        weightLimit = container.weight_limit, available = container.slot_limit - used, label = container.label, revision = container.revision }
end

local core = exports.frontier_core
local last = {}

function NearbyPropertyAgent(source)
    local ped = GetPlayerPed(source)
    if ped == 0 or GetPlayerRoutingBucket(source) ~= 0 then return nil end
    local pos = GetEntityCoords(ped)
    for _, agent in ipairs(PropertyAgents) do
        if (pos.x-agent.x)^2+(pos.y-agent.y)^2+(pos.z-agent.z)^2 <= 16 then return agent end
    end
end

local function activePropertyRows()
    return MySQL.query.await([[SELECT p.id,p.label,p.property_type,p.interior_key,
        po.price_cents,po.deposit_cents,po.duration_seconds,po.allow_furnish,po.offer_version,
        EXISTS(SELECT 1 FROM frontier_property_rentals r WHERE r.property_id=p.id
            AND (r.state='reserved' OR (r.state='active' AND r.ends_at>UTC_TIMESTAMP()))) AS occupied
        FROM frontier_properties p JOIN frontier_property_private_offers po
        ON po.property_id=p.id AND EXISTS (SELECT 1 FROM frontier_property_ownership o
             WHERE o.property_id=p.id AND o.party_type='character' AND o.party_id=po.landlord_id AND o.share_bps=10000)
        WHERE p.status='active' AND p.property_type='building' AND p.interior_key IS NOT NULL
        ORDER BY p.label,p.id LIMIT 100]])
end

RegisterNetEvent('frontier_property:agentRequest', function()
    local source = source
    local actor, agent = core:GetPlayerCharacterId(source), NearbyPropertyAgent(source)
    if not actor or not agent or GetGameTimer() < (last[source] or 0) then return end
    last[source] = GetGameTimer()+2000
    local listings = {}
    for _, row in ipairs(activePropertyRows()) do
        listings[#listings+1]={
            id=row.id,label=row.label,kind='Privat',price=row.price_cents,deposit=row.deposit_cents,
            duration=row.duration_seconds,furnish=tonumber(row.allow_furnish)==1,
            version=row.offer_version,available=tonumber(row.occupied)~=1,
        }
    end
    local rooms=GetPropertyFurnishingRooms()
    local plans={}
    for key, plan in pairs(PropertyConfig.ConstructionPlans) do
        plans[#plans+1]={key=key,label=plan.label or key,radius=plan.radius,value=plan.value,available=plan.verifiedInterior==true,interior=plan.interiorName or 'Innenraum nicht verifiziert',stages=plan.stages}
    end
    table.sort(plans,function(a,b) return a.key<b.key end)
    local leases=MySQL.query.await([[SELECT p.id,p.label FROM frontier_property_rentals r
        JOIN frontier_properties p ON p.id=r.property_id WHERE r.tenant_id=? AND r.state='active'
        AND r.ends_at>UTC_TIMESTAMP() AND p.status='active' ORDER BY r.id DESC LIMIT 40]],{actor})
    for _, row in ipairs(leases) do row.enter=rooms[row.id] and rooms[row.id].entry~=nil or false end
    local owns = MySQL.query.await([[SELECT p.id,p.label,o.share_bps AS share
        FROM frontier_property_ownership o JOIN frontier_properties p ON p.id=o.property_id
        WHERE o.party_type='character' AND o.party_id=? AND p.status='active'
        ORDER BY p.label LIMIT 40]],{actor})
    local recovery = MySQL.query.await([[SELECT id,model_key AS model FROM frontier_property_furniture
        WHERE owner_id=? AND state='recovery' ORDER BY id LIMIT 40]],{actor})
    local sales = MySQL.query.await([[SELECT s.id,p.label,s.price_cents AS price,s.assumed_lease_id AS lease,
        (s.buyer_id=?) AS buyer FROM frontier_property_sales s
        JOIN frontier_properties p ON p.id=s.property_id
        WHERE s.state='offered' AND (s.buyer_id=? OR EXISTS
            (SELECT 1 FROM frontier_property_sale_approvals a WHERE a.sale_id=s.id AND a.owner_id=?))
        ORDER BY s.id DESC LIMIT 40]],{actor,actor,actor})
    if core:GetPlayerCharacterId(source)~=actor or NearbyPropertyAgent(source)~=agent then return end
    TriggerClientEvent('frontier_property:agentOpen',source,
        {town=agent.town,listings=listings,owns=owns,recovery=recovery,sales=sales,leases=leases,plans=plans})
end)

AddEventHandler('playerDropped',function() last[source]=nil end)

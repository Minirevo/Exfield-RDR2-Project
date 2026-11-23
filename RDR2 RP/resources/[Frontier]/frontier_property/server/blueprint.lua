local inventory, core=exports.frontier_inventory,exports.frontier_core
local item='frontier_blueprint'
local registered=false

CreateThread(function()
    while not registered do
        local ok,defined=pcall(function()
            return inventory:RegisterItem(item,{name='Bauplan',description='Wiederverwendbarer Bauplan des Grundbuchamts.',
                category='Bau',grams=50,maxStack=1,usable=true,transfer=false,drop=false,store=false})
        end)
        if ok and defined then
            local available,result=pcall(function()
                return inventory:RegisterUsableItem(item,function() return true end,'keep')
            end)
            registered=available and result==true
        end
        if not registered then Wait(10000) end
    end
end)

local function tell(player,text)
    TriggerClientEvent('chat:addMessage',player,{args={'Frontier Bauamt',text}})
end

RegisterCommand('bauplan',function(player)
    if player<=0 then return end
    local actor=core:GetPlayerCharacterId(player)
    if not actor or not registered or not NearbyPropertyAgent(player) then return end
    local ok,held=inventory:HasItem(player,item,1)
    if not ok or core:GetPlayerCharacterId(player)~=actor or not NearbyPropertyAgent(player) then return end
    if held then return tell(player,'Du besitzt bereits einen Bauplan.') end
    local issued=inventory:AddItem(player,item,1,nil,'property:blueprint:'..actor)
    if core:GetPlayerCharacterId(player)==actor then
        tell(player,issued and 'Bauplan ausgestellt. Benutze ihn im Inventar auf deinem Grundstück.'
            or 'Der Bauplan konnte nicht ausgestellt werden.')
    end
end,false)

AddEventHandler('frontier:inventoryItemUsed',function(player,actor,used)
    if used~=item or core:GetPlayerCharacterId(player)~=actor or GetPlayerRoutingBucket(player)~=0 then return end
    CreateThread(function()
        local plots=MySQL.query.await([[SELECT p.id,p.label,l.polygon_json FROM frontier_land_claims l
            JOIN frontier_properties p ON p.id=l.property_id AND p.status='active'
            JOIN frontier_property_ownership o ON o.property_id=p.id AND o.party_type='character' AND o.party_id=?
            WHERE l.state='owned']],{actor})
        if core:GetPlayerCharacterId(player)~=actor or GetPlayerRoutingBucket(player)~=0 then return end
        local ped=GetPlayerPed(player)
        if ped==0 then return end
        local point=GetEntityCoords(ped)
        for _, plot in ipairs(plots) do
            if ConstructionFitsProperty(json.decode(plot.polygon_json),point,0) then
                local plans={}
                for key, plan in pairs(PropertyConfig.ConstructionPlans) do
                    plans[#plans+1]={key=key,label=plan.label or key,radius=plan.radius,value=plan.value,
                        stages=plan.stages,available=plan.verifiedInterior==true,
                        interior=plan.interiorName or 'Nicht im Spiel verifiziert'}
                end
                table.sort(plans,function(a,b) return a.key<b.key end)
                return TriggerClientEvent('frontier_property:blueprintOpen',player,
                    {town='Baukatalog',catalogue=true,owns={{id=plot.id,label=plot.label}},plans=plans})
            end
        end
        tell(player,'Benutze den Bauplan auf einem eigenen vermessenen Grundstück.')
    end)
end)

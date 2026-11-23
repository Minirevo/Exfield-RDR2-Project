local core=exports.frontier_core
local economy=exports.frontier_economy
local requested={}
local permissions={enter=true,construct=true,furnish=true,use_facility=true,furnish_move=true,furnish_remove=true}

local function throttle(player,time)
    local now=GetGameTimer()
    if (requested[player] or 0)>now then return true end
    requested[player]=now+time
    return false
end

local function show(player,actor)
    local properties=MySQL.query.await([[SELECT p.id,p.label,
        EXISTS(SELECT 1 FROM frontier_property_ownership o
            WHERE o.property_id=p.id AND o.party_type='character' AND o.party_id=?) AS owner,
        EXISTS(SELECT 1 FROM frontier_property_rentals r
            WHERE r.property_id=p.id AND r.tenant_id=? AND r.state='active' AND r.ends_at>UTC_TIMESTAMP()) AS tenant
        FROM frontier_properties p WHERE p.status='active' AND (
            EXISTS(SELECT 1 FROM frontier_property_ownership o
                WHERE o.property_id=p.id AND o.party_type='character' AND o.party_id=?)
            OR EXISTS(SELECT 1 FROM frontier_property_permissions a
                WHERE a.property_id=p.id AND a.character_id=? AND a.allow_access=1)
            OR EXISTS(SELECT 1 FROM frontier_property_rentals r
                WHERE r.property_id=p.id AND r.tenant_id=? AND r.state='active' AND r.ends_at>UTC_TIMESTAMP())
        ) ORDER BY p.label,p.id]],{actor,actor,actor,actor,actor})
    local online={}
    for _, raw in ipairs(GetPlayers()) do
        local source=tonumber(raw)
        local id=core:GetPlayerCharacterId(source)
        if id and id~=actor then online[#online+1]={source=source,character=id,label=GetPlayerName(source)} end
    end
    for _, property in ipairs(properties) do
        if tonumber(property.owner)==1 then
            property.grants=MySQL.query.await([[SELECT character_id AS character,permission_key AS permission
                FROM frontier_property_permissions WHERE property_id=? AND allow_access=1
                ORDER BY character_id,permission_key]],{property.id})
        end
    end
    if core:GetPlayerCharacterId(player)~=actor then return end
    TriggerClientEvent('frontier_property:manageOpen',player,{properties=properties,online=online})
end

RegisterNetEvent('frontier_property:manageRequest',function()
    local player=source
    local actor=core:GetPlayerCharacterId(player)
    if actor and not throttle(player,900) then show(player,actor) end
end)

RegisterNetEvent('frontier_property:manageAction',function(data)
    local player=source
    if throttle(player,700) then return end
    local actor=core:GetPlayerCharacterId(player)
    local id=type(data)=='table' and data.id
    if not actor or math.type(id)~='integer' or id<1 or id>9007199254740991 then return end
    local action, name, grantee, capability, allowed=data.action,'','','',0
    if action=='rename' then
        if type(data.name)~='string' or #data.name>256 or data.name:find('%c') or data.name:find('%^%d') then return end
        name=data.name:match('^%s*(.-)%s*$')
        local count=utf8.len(name)
        if not count or count<PropertyConfig.MinPropertyName or count>PropertyConfig.MaxPropertyName then
            return TriggerClientEvent('frontier_property:manageResult',player,'Der Name hat eine ungültige Länge.')
        end
    elseif action=='permission' then
        if not permissions[data.permission] or type(data.character)~='string' or #data.character~=34
            or not data.character:match('^f_[a-f0-9]+$') or type(data.allow)~='boolean' then return end
        grantee,capability,allowed=data.character,data.permission,data.allow and 1 or 0
        if allowed==1 and (math.type(data.player)~='integer' or core:GetPlayerCharacterId(data.player)~=grantee) then return end
    elseif action=='offer' then
        local price, hours, deposit=data.price,data.hours,data.deposit
        if math.type(price)~='integer' or price<1 or price>9000000000000
            or math.type(hours)~='integer' or hours<1 or hours>8760
            or math.type(deposit)~='integer' or deposit<0 or deposit>9000000000000-price
            or type(data.furnish)~='boolean' then
            return TriggerClientEvent('frontier_property:manageResult',player,'Miete, Dauer oder Kaution ist ungültig.')
        end
        local ok, accounts=economy:GetCharacterAccounts(player)
        if not ok or accounts.characterId~=actor or core:GetPlayerCharacterId(player)~=actor then return end
        local rows=MySQL.query.await('CALL frontier_property_rent_offer_v2(?,?,?,?,?,?,?)',
            {id,actor,accounts.bank.id,price,hours*3600,data.furnish and 1 or 0,deposit})
        if core:GetPlayerCharacterId(player)~=actor then return end
        local item=rows and rows[1] and rows[1][1]
        return TriggerClientEvent('frontier_property:manageResult',player,
            item and tonumber(item.accepted)==1 and 'Mietangebot gespeichert.'
            or 'Dieses Objekt kann durch dich nicht zur Miete angeboten werden.')
    elseif action~='unlist' then return end
    local result=MySQL.query.await('CALL frontier_property_manage_v1(?,?,?,?,?,?,?)',
        {id,actor,action,name,grantee,capability,allowed})
    if core:GetPlayerCharacterId(player)~=actor then return end
    local receipt=result and result[1] and result[1][1]
    local labels={ok='Änderung gespeichert.',duplicate_name='Dieser Name ist bereits vergeben.',
        denied='Für diese Änderung fehlt dir die Berechtigung oder das Angebot ist nicht mehr vorhanden.'}
    TriggerClientEvent('frontier_property:manageResult',player,labels[receipt and receipt.result] or labels.denied)
    if receipt and receipt.result=='ok' then show(player,actor) end
end)

AddEventHandler('playerDropped',function() requested[source]=nil end)

local _ENV=PropertyRuntime
local function authorized(src)
    return src>0 and C.AdminTesting.Enabled==true and IsPlayerAceAllowed(src,C.AdminTesting.Ace)
end
local function adminCommand(name,fn)
    RegisterCommand(name,function(source,args)
        local src=tonumber(source) or 0
        if src==0 then print('[frontier_property] '..name..' is an in-game command.'); return end
        if not authorized(src) then return notice(src,'Property test commands are disabled or permission denied.') end
        fn(src,args)
    end,false)
end
local function log(src,msg)
    print(('[frontier_property] Admin %d (%s): %s'):format(src,tostring(cid(src)),msg))
end
adminCommand('propertyfinish',function(src,args)
    run(src,function()
        local pos=position(src)
        if not pos or pos.bucket~=0 or not cid(src) then return notice(src,'Be outside on a loaded character.') end
        local best,dist,claim
        for _,s in pairs(S.settlements) do
            if s.status=='active' and not (s.listing and s.listing.active) then
                for _,b in pairs(s.buildings) do
                    local n=R.distance(pos,b)
                    if not b.complete and (not args[1] or b.id==args[1]) and n<=C.AdminTesting.FinishDistance and math.abs(pos.z-b.z)<=C.MaxHeightOffset and (not dist or n<dist) then
                        best,dist,claim=b,n,s
                    end
                end
            end
        end
        if not best then return notice(src,'No eligible unfinished construction nearby.') end
        best.stage=#best.stages+1
        best.progress=0;best.delivered={};best.complete=true
        save()
        for worker,w in pairs(workers) do
            if w.sid==claim.id and w.bid==best.id then workers[worker]=nil;notice(worker,'Construction completed by administrator.') end
        end
        log(src,'instant completion '..best.id..' ('..best.exterior..')')
        notice(src,'Instantly completed '..best.exterior..'. No materials or money charged.')
        TriggerClientEvent(E..'refresh',src)
    end)
end)
adminCommand('propertymodels',function(src)
    local keys={}
    for key in pairs(C.Exteriors) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do notice(src,key..' = '..C.Exteriors[key].model) end
    for key in pairs(C.AdminTesting.AssetModels or {}) do notice(src,key..' (direct asset test)') end
    notice(src,'Camp models: camp_fire, camp_tent, camp_chest, camp_site')
end)
adminCommand('propertyspawn',function(src,args)
    local pos=position(src)
    if not pos or pos.bucket~=0 or not cid(src) then return notice(src,'Be outside on a loaded character.') end
    local key=args[1]
    local def=key and C.Exteriors[key]
    local direct=key and (C.AdminTesting.AssetModels or {})[key]
    local model=def and def.model or (direct and key)
    if key and not model then
        local camp=key:match('^camp_(%a+)$')
        if camp then model=C.Camp[camp] end
    end
    if not model then return notice(src,'Usage: /propertyspawn <catalogue key>. See /propertymodels.') end
    local distance=tonumber(args[2]) or (def and def.radius+3 or direct or 5)
    if not R.finite(distance) or distance<3 or distance>25 then return notice(src,'Distance must be between 3 and 25 metres.') end
    log(src,'temporary model test '..model)
    TriggerClientEvent(E..'adminSpawn',src,{model=model,distance=distance})
end)
adminCommand('propertyclear',function(src)
    TriggerClientEvent(E..'adminClear',src)
end)

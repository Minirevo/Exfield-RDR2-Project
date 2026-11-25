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
local assetCursor={}
local function assetKeys()
    local keys={}
    for key in pairs(C.AdminTesting.AssetModels or {}) do keys[#keys+1]=key end
    table.sort(keys)
    return keys
end
local function testSpawn(src,key,distance)
    local pos=position(src)
    if not pos or pos.bucket~=0 or not cid(src) then notice(src,'Be outside on a loaded character.'); return false end
    local assembly=key and C.TestAssemblies[key]
    if assembly then
        distance=distance or assembly.distance
        if not R.finite(distance) or distance<3 or distance>25 then notice(src,'Distance must be between 3 and 25 metres.'); return false end
        log(src,'temporary assembly test '..key)
        TriggerClientEvent(E..'adminAssembly',src,{key=key,distance=distance})
        return true
    end
    local def=key and C.Exteriors[key]
    local direct=key and (C.AdminTesting.AssetModels or {})[key]
    local model=def and def.model or (direct and key)
    if key and not model then
        local camp=key:match('^camp_(%a+)$')
        if camp then model=C.Camp[camp] end
    end
    if not model then notice(src,'Usage: /propertyspawn <model or catalogue key>. See /propertymodels.'); return false end
    distance=distance or (def and def.radius+3 or direct or 5)
    if not R.finite(distance) or distance<3 or distance>25 then notice(src,'Distance must be between 3 and 25 metres.'); return false end
    log(src,'temporary model test '..model)
    TriggerClientEvent(E..'adminSpawn',src,{model=model,distance=distance})
    return true
end
adminCommand('propertymodels',function(src)
    local keys=assetKeys()
    for i,key in ipairs(keys) do
        local msg=('%02d/%02d %s'):format(i,#keys,key)
        notice(src,msg)
    end
    local assemblies={}
    for key in pairs(C.TestAssemblies) do assemblies[#assemblies+1]=key end
    table.sort(assemblies)
    notice(src,'Assembly tests: '..table.concat(assemblies,', '))
    notice(src,'Use /propertyspawn <name>, /propertynext [number], /propertyprev, /propertyclear. Camp models: camp_fire, camp_tent, camp_chest, camp_site.')
end)
adminCommand('propertyspawn',function(src,args)
    if args[2] and not tonumber(args[2]) then return notice(src,'Distance must be a number.') end
    if testSpawn(src,args[1],tonumber(args[2])) then
        for i,key in ipairs(assetKeys()) do if key==args[1] then assetCursor[src]=i;break end end
    end
end)
local function cycle(src,step,args)
    local keys=assetKeys()
    if #keys==0 then return notice(src,'No test assets configured.') end
    local index
    if args[1] then
        index=tonumber(args[1])
        if not index or index%1~=0 or index<1 or index>#keys then return notice(src,'Asset number must be between 1 and '..#keys) end
    else
        local previous=assetCursor[src] or (step>0 and 0 or 1)
        index=(previous-1+step)%#keys+1
    end
    if testSpawn(src,keys[index]) then
        assetCursor[src]=index
        notice(src,('Testing %d/%d: %s'):format(index,#keys,keys[index]))
    end
end
adminCommand('propertynext',function(src,args) cycle(src,1,args) end)
adminCommand('propertyprev',function(src,args) cycle(src,-1,args) end)
adminCommand('propertyclear',function(src)
    TriggerClientEvent(E..'adminClear',src)
end)
AddEventHandler('playerDropped',function() assetCursor[tonumber(source)]=nil end)

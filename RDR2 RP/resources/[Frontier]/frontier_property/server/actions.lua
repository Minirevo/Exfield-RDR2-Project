local _ENV=PropertyRuntime
function request(src,action,d)
    local id=cid(src)
    if not id or type(d)~='table' then return end
    local s=settlement(d.sid); local b=s and type(d.bid)=='string' and s.buildings[d.bid] or nil
    if action=='market' then view(src,'market'); return end
    if action=='shop' then
        if nearShop(src) then view(src,'shop') else notice(src,'Approach a property general store (Valentine, Rhodes or Blackwater).') end
        return
    end
    if action=='exit' then exit(src); return end
    if action=='cancelPreview' then previews[src]=nil; return end
    if action=='interior' then local x,y=findVisit(src); if x then view(src,'interior',x,y) end; return end
    if action=='camp' then if nearCamp(src,s) and (owner(s,id) or s.members[id]) then view(src,'camp',s) end; return end
    if action=='chest' then
        if s and not (s.listing and s.listing.active) and allowed(s,id,'storage') and close(src,{x=s.x+2,y=s.y,z=s.z},C.InteractionDistance) then inv:OpenStorage(src,chestId(s.id)) end; return
    end
    if action=='site' then
        if b and s.status=='active' and close(src,b,C.InteractionDistance) and (allowed(s,id,'work') or allowed(s,id,'deliver')) then view(src,'site',s,b) end; return
    end
    if action=='fixture' then
        local f=s and s.furniture and s.furniture[d.bid]
        if s and s.status=='active' and f and (f.item=='property_storage' or f.item=='property_counter') and close(src,f,C.InteractionDistance) and GetResourceState('frontier_business')=='started' then
            TriggerEvent('frontier_business:fixture',src,s.id,d.bid)
        end
        return
    end
    if action=='enter' then return end
    if action=='furnitureMenu' then local plot=plotAt(src,id);if plot then view(src,'furnitureMenu',plot) end;return end
    if action=='buyItem' then
        if not nearShop(src) then return notice(src,'You are too far from the general store.') end
        if type(d.item)~='string' then return notice(src,'Select a shop item.') end
        local def=d.item==C.Kit.id and C.Kit or C.Tools[d.item] or C.Furniture[d.item]
        if not def then return notice(src,'This item is not sold here.') end
        local a=account(src,id);if not a then return notice(src,'Your bank account is unavailable.') end
        queue({kind='shop',actor=id,src=src,item=d.item,account=a,amount=def.price})
        notice(src,'Purchase queued: '..def.name)
        return
    end
    if action=='buySettlement' then
        if not s or s.status~='active' or not s.listing or not s.listing.active or owner(s,id) or occupied(s.id) or s.debt>0 then return end
        if GetResourceState('frontier_business')=='started' and exports.frontier_business:PlotHasBusinessFixtures(s.id) then return notice(src,'Resolve registered commercial furniture before selling this plot.') end
        if tonumber(d.price)~=s.listing.price then return end
        local a=account(src,id); local payments=shares(s,s.listing.price)
        if a and payments then queue({kind='sale',actor=id,src=src,sid=s.id,account=a,amount=s.listing.price,payouts=payments}) end
        return
    end
    if action=='place' then
        local p=previews[src]; previews[src]=nil
        if not p or p.actor~=id or p.untilTime<os.time() or not R.point(d) or not R.finite(d.heading) then return end
        s=settlement(p.sid); b=s and p.bid and s.buildings[p.bid] or nil
        if not s or s.status~='active' or (s.listing and s.listing.active) then return notice(src,'Settlement is unavailable or listed for sale.') end
        local pos=position(src)
        if not pos or not R.near(pos,d,C.PlacementDistance) or math.abs(pos.z-d.z)>C.MaxHeightOffset then return notice(src,'Invalid placement range.') end
        if p.mode=='furniture' or p.mode=='moveFurniture' then
            if pos.bucket~=0 or not allowed(s,id,'furnish') or R.distance(s,d)>s.radius or R.distance(s,pos)>s.radius then return notice(src,'Furniture must remain on your plot.') end
            local f=C.Furniture[p.item];if not f then return end
            s.furniture=s.furniture or {}
            for k,v in pairs(s.furniture) do
                if k~=p.fid then
                    if R.near(v,d,0.5) then return notice(src,'Furniture overlaps.') end
                end
            end
            local furniture={item=p.item,x=d.x,y=d.y,z=d.z,heading=d.heading%360}
            if p.mode=='moveFurniture' then
                if not s.furniture[p.fid] then return end
                s.furniture[p.fid]=furniture;save();notice(src,'Furniture moved.')
            else queue({kind='furniture',actor=id,src=src,sid=s.id,fid=uuid(),item=p.item,furniture=furniture,physical=true}) end
            return
        end
        local e=C.Exteriors[p.exterior]; local i=nil
        if pos.bucket~=0 or not allowed(s,id,p.mode=='move' and 'move' or 'build') or not e or not R.fits(s,d,e.radius,p.mode=='move' and p.bid or nil) then return notice(src,'Building must fit inside the claim and avoid other structures.') end
        if p.mode=='move' then
            if not b or not b.complete or occupied(s.id) or b.exterior~=p.exterior then return end
            -- Furniture is plot-owned and stays at its world position on relocation.
            b.x,b.y,b.z,b.heading=d.x,d.y,d.z,d.heading%360
        else
            local bid=uuid(); if i then
                S.nextBucket=S.nextBucket+1
                if S.nextBucket>C.InteriorBucketLimit then error('bucket range exhausted') end
            end
            s.buildings[bid]={id=bid,exterior=p.exterior,interior=nil,x=d.x,y=d.y,z=d.z,heading=d.heading%360,radius=e.radius,
                stages=buildingStages(e,i),stage=1,delivered={},progress=0,complete=false,capacity=R.capacity(e,i),
                furniture={},bucket=S.nextBucket,locked=true,value=e.value+(i and i.value or 0)}
        end
        save(); notice(src,'Placement saved.'); return
    end
    if action=='stopWork' then workers[src]=nil; return end
    if not s or s.status~='active' then return end
    if s.listing and s.listing.active and action~='unlist' and action~='approve' and action~='tax' then return notice(src,'Cancel the market listing before changing this settlement.') end
    if action=='deliver' or action=='work' then
        if not b or b.complete or not close(src,b) then return end
        local stage=b.stages[b.stage]; if not stage then return end
        if action=='deliver' and allowed(s,id,'deliver') then
            local count=tonumber(d.quantity)
            if type(d.item)~='string' or not count or count%1~=0 or count<1 or count>(stage.materials[d.item] or 0)-(b.delivered[d.item] or 0) then return end
            queue({kind='deliver',actor=id,src=src,sid=s.id,bid=b.id,item=d.item,qty=count})
        elseif action=='work' and allowed(s,id,'work') then
            workers[src]={sid=s.id,bid=b.id,actor=id}; notice(src,'Construction work started; stay nearby with the required tools.')
        end
        return
    end
    if action=='moveFurniture' or action=='removeFurniture' then
        if not allowed(s,id,'furnish') or type(d.fid)~='string' then return end
        local f=(s.furniture or {})[d.fid]
        if f then
            if (f.item=='property_storage' or f.item=='property_counter') and (GetResourceState('frontier_business')~='started' or exports.frontier_business:FixtureBound(d.fid)) then return notice(src,'Unregister and empty functional furniture before moving or picking it up.') end
            if plotAt(src,id)~=s or not close(src,f,C.PlacementDistance) then return notice(src,'Approach the furniture first.') end
            if action=='moveFurniture' then beginPreview(src,s,nil,nil,nil,action,d.fid,f.item)
            else queue({kind=action,actor=id,src=src,sid=s.id,fid=d.fid,item=f.item,physical=true}) end
        elseif action=='removeFurniture' and b and b.furniture[d.fid] and nearCamp(src,s) then
            queue({kind=action,actor=id,src=src,sid=s.id,bid=b.id,fid=d.fid,item=b.furniture[d.fid].item})
        end
        return
    end
    if not nearCamp(src,s) then return end
    if action=='plan' and allowed(s,id,'build') then
        local e=type(d.exterior)=='string' and C.Exteriors[d.exterior]
        if not e then return end
        beginPreview(src,s,nil,d.exterior,nil,'build')
    elseif action=='rename' and allowed(s,id,'members') then
        if type(d.name)~='string' or #d.name<1 or #d.name>60 or not utf8.len(d.name) or d.name:find('%c') then return end
        s.name=d.name; save()
    elseif action=='map' and owner(s,id) then s.map=not s.map; save()
    elseif action=='member' and allowed(s,id,'members') then
        local target=tonumber(d.target); local other=target and target%1==0 and target>0 and cid(target)
        if type(d.character)=='string' and s.members[d.character] then other=d.character end
        if not other or other==id or s.owners[other] then return end
        if not owner(s,id) and s.members[other] then for _,k in ipairs(C.Permissions) do if s.members[other][k] and not allowed(s,id,k) then return notice(src,'Cannot manage a member with higher permissions.') end end end
        local rights={}; if type(d.rights)=='table' then for _,k in ipairs(C.Permissions) do if d.rights[k]==true and allowed(s,id,k) then rights[k]=true end end end
        if d.remove==true then s.members[other]=nil else s.members[other]=rights end
        save()
    elseif action=='coowner' and owner(s,id) and s.primary==id and not s.listing then
        local target=tonumber(d.target); local other=target and target%1==0 and target>0 and cid(target)
        if other and other~=id and bank(other) then s.owners[other]=true; s.members[other]=nil; save() end
    elseif action=='removeCoowner' and owner(s,id) and s.primary==id and not s.listing then
        -- Ownership is an economic right; removal is voluntary, never unilateral.
        notice(src,'Co-owners must relinquish their own share.')
    elseif action=='relinquish' and owner(s,id) and s.primary~=id and not s.listing then
        if d.confirm~='RELINQUISH' then return end
        s.owners[id]=nil; s.members[id]=nil; save()
    elseif action=='expand' and allowed(s,id,'expand') then
        local radius=s.radius+C.ExpansionStep
        local ok,err=R.claim(s,radius,S.settlements,s.id,C); if not ok then return notice(src,err) end
        local a=account(src,id); if a then queue({kind='expand',actor=id,src=src,sid=s.id,radius=radius,account=a,amount=R.expansion(s,C)}) end
    elseif action=='tax' and allowed(s,id,'finance') and s.debt>0 then
        local a=account(src,id); if a then queue({kind='tax',actor=id,src=src,sid=s.id,account=a,amount=s.debt}) end
    elseif action=='list' and owner(s,id) and s.debt==0 and not occupied(s.id) then
        if GetResourceState('frontier_business')=='started' and exports.frontier_business:PlotHasBusinessFixtures(s.id) then return notice(src,'Unregister commercial furniture before listing this plot.') end
        for _,b in pairs(s.buildings) do if C.Exteriors[b.exterior].farm and (GetResourceState('frontier_farming')~='started' or exports.frontier_farming:FacilityBound(b.id)) then return notice(src,'Release farm facilities before listing.') end end
        local price=tonumber(d.price)
        if not price or price%1~=0 or price<1 or price>100000000 then return end
        s.listing={price=price,approvals={[id]=true},active=false}
        local all=true; for who in pairs(s.owners) do if not s.listing.approvals[who] then all=false end end
        s.listing.active=all; save()
    elseif action=='approve' and owner(s,id) and s.listing then
        s.listing.approvals[id]=true; local all=true; for who in pairs(s.owners) do if not s.listing.approvals[who] then all=false end end
        s.listing.active=all; save()
    elseif action=='unlist' and owner(s,id) then s.listing=nil; save()
    elseif action=='abandon' and owner(s,id) and s.primary==id and not occupied(s.id) then
        if GetResourceState('frontier_business')=='started' and exports.frontier_business:PlotHasBusinessFixtures(s.id) then return notice(src,'Resolve registered commercial furniture before abandoning this plot.') end
        for _,b in pairs(s.buildings) do if C.Exteriors[b.exterior].farm and (GetResourceState('frontier_farming')~='started' or exports.frontier_farming:FacilityBound(b.id)) then return notice(src,'Release farm facilities before abandoning.') end end
        local count=0; for _ in pairs(s.owners) do count=count+1 end
        if count~=1 or s.debt>0 then return notice(src,'Co-owned or indebted settlements cannot be abandoned.') end
        if d.confirm~='ABANDON' then return end
        s.status='abandoned'; s.listing=nil; save()
    elseif action=='upgrade' and b and b.complete and allowed(s,id,'build') and not occupied(s.id) then
        local e=C.Exteriors[b.exterior]; local n=type(d.exterior)=='string' and C.Exteriors[d.exterior]
        local i=b.interior and C.Interiors[b.interior]
        if not n or n.category~=e.category or n.slots<=e.slots or n.interior~=e.interior or not R.fits(s,b,n.radius,b.id) then return notice(src,'Invalid upgrade.') end
        b.exterior=d.exterior; b.radius=n.radius; b.capacity=R.capacity(n,i); b.value=n.value+(i and i.value or 0)
        b.stages=buildingStages(n,nil); b.stage=1; b.delivered={}; b.progress=0; b.complete=false; save()
    elseif action=='move' and b and b.complete and allowed(s,id,'move') then if C.Exteriors[b.exterior].farm then return notice(src,'Farm structures cannot be moved in this release.') end; beginPreview(src,s,b,b.exterior,b.interior,'move')
    elseif action=='demolish' and b and allowed(s,id,'demolish') and not occupied(s.id) and d.confirm=='DEMOLISH' then
        if C.Exteriors[b.exterior].farm and (GetResourceState('frontier_farming')~='started' or exports.frontier_farming:FacilityBound(b.id)) then return notice(src,'Release the farming facility first.') end
        if next(b.furniture) then return notice(src,'Recover legacy furniture at camp before demolition.') end
        s.buildings[b.id]=nil; save()
    elseif action=='lock' then return notice(src,'Physical door locks are not implemented yet.')
    end
    if action~='plan' and action~='move' and s.status=='active' and (owner(s,id) or s.members[id]) then view(src,'camp',s) elseif s.status~='active' then TriggerClientEvent(E..'close',src) end
end
RegisterNetEvent(E..'action',function(action,d)
    local src=tonumber(source); if not src or src<=0 or type(action)~='string' or #action>32 then return end
    local now=GetGameTimer(); if rate[src] and now-rate[src]<200 then return end; rate[src]=now
    run(src,function() request(src,action,d) end,action=='exit')
end)
AddEventHandler('frontier:inventoryItemUsed',function(src,id,itemId)
    if itemId~=C.Kit.id and not C.Furniture[itemId] then return end
    CreateThread(function()
        run(src,function()
            if cid(src)~=id then return end
            local p=position(src); if not p or not R.point(p) then return end
            if itemId==C.Kit.id then
                if p.bucket~=0 then return end
                local ok,err=R.claim(p,C.InitialRadius,S.settlements,nil,C); if not ok then return notice(src,err) end
                local sid=uuid()
                local claim={id=sid,name='New settlement',x=p.x,y=p.y,z=p.z,radius=C.InitialRadius,owners={[id]=true},primary=id,
                    members={},buildings={},furniture={},status='active',debt=0,nextTax=os.time()+C.TaxPeriod}
                queue({kind='claim',actor=id,src=src,sid=sid,item=itemId,claim=claim})
            else
                local s=plotAt(src,id)
                if not s or (s.listing and s.listing.active) then return notice(src,'Stand on an authorized settlement first.') end
                TriggerClientEvent('frontier_inventory:close',src)
                beginPreview(src,s,nil,nil,nil,'furniture',nil,itemId)
            end
        end)
    end)
end)
exports('CanAccessCampStorage',function(src,storage)
    if not ready or next(S.jobs) or type(storage)~='string' then return false end
    local s=settlement(storage:match('^property_([a-f0-9]+)$'))
    return s and not (s.listing and s.listing.active) and allowed(s,cid(src),'storage') and close(src,{x=s.x+2,y=s.y,z=s.z},C.InteractionDistance) or false
end)
exports('GetProperty',function(id) local s=ready and settlement(id); if s and s.status=='active' then return public(s) end end)
exports('CanAccessProperty',function(id,sid,permission) return ready and allowed(settlement(sid),id,permission)==true end)

exports('GetBusinessFixture',function(sid,fid)
    if GetInvokingResource()~='frontier_business' or not ready then return end
    local s=settlement(sid);local f=s and s.furniture and s.furniture[fid]
    if not s or s.status~='active' or (s.listing and s.listing.active) or not f or (f.item~='property_storage' and f.item~='property_counter') then return end
    return {item=f.item,x=f.x,y=f.y,z=f.z,heading=f.heading}
end)
exports('GetOwnedPlots',function(who)
    if GetInvokingResource()~='frontier_business' or not ready then return {} end
    local out={};for id,s in pairs(S.settlements) do if owner(s,who) then out[#out+1]=public(s) end end;return out
end)

exports('GetBusinessFixtureRecovery',function(sid,fid)
    if GetInvokingResource()~='frontier_business' or not ready then return end
    local s=settlement(sid);local f=s and s.furniture and s.furniture[fid]
    if not f or (f.item~='property_storage' and f.item~='property_counter') then return end
    return {item=f.item,x=f.x,y=f.y,z=f.z,heading=f.heading}
end)

exports('GetFarmBuildings',function(src)
    if GetInvokingResource()~='frontier_farming' or not ready then return {} end
    local p=position(src);if not p or p.bucket~=0 then return {} end
    local result={}
    for sid,s in pairs(S.settlements) do if s.status=='active' and not s.listing and R.distance(p,s)<=s.radius+C.StreamDistance then
        for bid,b in pairs(s.buildings) do local e=C.Exteriors[b.exterior]
            if b.complete and e and e.farm and R.distance(p,b)<=C.StreamDistance then
                result[#result+1]={id=bid,plot=sid,x=b.x,y=b.y,z=b.z,heading=b.heading,kind=e.farm,size=e.size,width=e.width,length=e.length,personalOwner=s.primary}
            end
        end
    end end
    return result
end)
exports('FarmBuilding',function(sid,bid,who)
    if GetInvokingResource()~='frontier_farming' or not ready then return end
    local s=settlement(sid);local b=s and s.buildings[bid];local e=b and C.Exteriors[b.exterior]
    if not s or s.status~='active' or s.listing or not b or not b.complete or not e or not e.farm then return end
    return {id=bid,plot=sid,x=b.x,y=b.y,z=b.z,heading=b.heading,kind=e.farm,size=e.size,width=e.width,length=e.length,personalOwner=s.primary,owned=owner(s,who)==true}
end)

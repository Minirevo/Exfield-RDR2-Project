local _ENV=PropertyRuntime
function request(src,action,d)
    local id=cid(src)
    if not id or type(d)~='table' then return end
    local s=settlement(d.sid); local b=s and type(d.bid)=='string' and s.buildings[d.bid] or nil
    if action=='market' then view(src,'market'); return end
    if action=='shop' then if nearShop(src) then view(src,'shop') end; return end
    if action=='exit' then exit(src); return end
    if action=='cancelPreview' then previews[src]=nil; return end
    if action=='interior' then local x,y=findVisit(src); if x then view(src,'interior',x,y) end; return end
    if action=='camp' then if nearCamp(src,s) and (owner(s,id) or s.members[id]) then view(src,'camp',s) end; return end
    if action=='chest' then
        if allowed(s,id,'storage') and close(src,{x=s.x+2,y=s.y,z=s.z},C.InteractionDistance) then inv:OpenStorage(src,chestId(s.id)) end; return
    end
    if action=='site' then
        if b and s.status=='active' and close(src,b,C.InteractionDistance) and (allowed(s,id,'work') or allowed(s,id,'deliver')) then view(src,'site',s,b) end; return
    end
    if action=='enter' then if b then enter(src,s,b,id) end; return end
    if action=='buyItem' then
        if not nearShop(src) or type(d.item)~='string' then return end
        local def=d.item==C.Kit.id and C.Kit or C.Tools[d.item] or C.Furniture[d.item]; local a=account(src,id)
        if def and a then queue({kind='shop',actor=id,src=src,item=d.item,account=a,amount=def.price}) end
        return
    end
    if action=='buySettlement' then
        if not s or s.status~='active' or not s.listing or not s.listing.active or owner(s,id) or occupied(s.id) or s.debt>0 then return end
        if tonumber(d.price)~=s.listing.price then return end
        local a=account(src,id); local payments=shares(s,s.listing.price)
        if a and payments then queue({kind='sale',actor=id,src=src,sid=s.id,account=a,amount=s.listing.price,payouts=payments}) end
        return
    end
    if action=='place' then
        local p=previews[src]; previews[src]=nil
        if not p or p.actor~=id or p.untilTime<os.time() or not R.point(d) or not R.finite(d.heading) then return end
        s=settlement(p.sid); b=s and p.bid and s.buildings[p.bid] or nil
        if not s or s.status~='active' then return end
        local pos=position(src)
        if not pos or not R.near(pos,d,C.PlacementDistance) or math.abs(pos.z-d.z)>C.MaxHeightOffset then return notice(src,'Invalid placement range.') end
        if p.mode=='furniture' or p.mode=='moveFurniture' then
            if not b or not atInterior(src,s,b) or not allowed(s,id,'furnish') then return end
            local interior=C.Interiors[b.interior]; local f=C.Furniture[p.item]
            if not R.near(interior,d,interior.bounds) then return notice(src,'Outside room bounds.') end
            local used=0
            for k,v in pairs(b.furniture) do
                if k~=p.fid then
                    used=used+C.Furniture[v.item].slots
                    if R.near(v,d,0.5) then return notice(src,'Furniture overlaps.') end
                end
            end
            if used+f.slots>b.capacity then return notice(src,'Furnishing capacity reached.') end
            local furniture={item=p.item,x=d.x,y=d.y,z=d.z,heading=d.heading%360}
            if p.mode=='moveFurniture' then if not b.furniture[p.fid] then return end; b.furniture[p.fid]=furniture; save()
            else queue({kind='furniture',actor=id,src=src,sid=s.id,bid=b.id,fid=uuid(),item=p.item,furniture=furniture}) end
            return
        end
        local e=C.Exteriors[p.exterior]; local i=p.interior and C.Interiors[p.interior]
        if pos.bucket~=0 or not allowed(s,id,p.mode=='move' and 'move' or 'build') or not e or not R.fits(s,d,e.radius,p.mode=='move' and p.bid or nil) then return notice(src,'Building must fit inside the claim and avoid other structures.') end
        if p.mode=='move' then
            if not b or not b.complete or occupied(s.id) then return end
            b.x,b.y,b.z,b.heading=d.x,d.y,d.z,d.heading%360
        else
            local bid=uuid(); S.nextBucket=S.nextBucket+1
            if S.nextBucket>C.InteriorBucketLimit then error('bucket range exhausted') end
            s.buildings[bid]={id=bid,exterior=p.exterior,interior=p.interior,x=d.x,y=d.y,z=d.z,heading=d.heading%360,radius=e.radius,
                stages=buildingStages(e,i),stage=1,delivered={},progress=0,complete=false,capacity=R.capacity(e,i),
                furniture={},bucket=S.nextBucket,locked=true,value=e.value+(i and i.value or 0)}
        end
        save(); notice(src,'Placement saved.'); return
    end
    if not s or s.status~='active' then return end
    if action=='stopWork' then workers[src]=nil; return end
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
        if not b or not atInterior(src,s,b) or not allowed(s,id,'furnish') or type(d.fid)~='string' or not b.furniture[d.fid] then return end
        local f=b.furniture[d.fid]
        if action=='moveFurniture' then beginPreview(src,s,b,nil,nil,action,d.fid,f.item)
        else queue({kind=action,actor=id,src=src,sid=s.id,bid=b.id,fid=d.fid,item=f.item}) end
        return
    end
    if not nearCamp(src,s) then return end
    if action=='plan' and allowed(s,id,'build') then
        local e=type(d.exterior)=='string' and C.Exteriors[d.exterior]
        local i=type(d.interior)=='string' and C.Interiors[d.interior]
        if not e or (e.interior and not i) or (not e.interior and i) then return end
        beginPreview(src,s,nil,d.exterior,e.interior and d.interior or nil,'build')
    elseif action=='rename' and allowed(s,id,'members') then
        if type(d.name)~='string' or #d.name<1 or #d.name>60 or not utf8.len(d.name) or d.name:find('%c') then return end
        s.name=d.name; save()
    elseif action=='map' and owner(s,id) then s.map=not s.map; save()
    elseif action=='member' and allowed(s,id,'members') then
        local target=tonumber(d.target); local other=target and target%1==0 and target>0 and cid(target)
        if type(d.character)=='string' and s.members[d.character] then other=d.character end
        if not other or other==id or s.owners[other] then return end
        local rights={}; if type(d.rights)=='table' then for _,k in ipairs(C.Permissions) do if d.rights[k]==true and allowed(s,id,k) then rights[k]=true end end end
        if d.remove==true then s.members[other]=nil else s.members[other]=rights end
        save()
    elseif action=='coowner' and owner(s,id) and s.primary==id and not s.listing then
        local target=tonumber(d.target); local other=target and target%1==0 and target>0 and cid(target)
        if other and other~=id and bank(other) then s.owners[other]=true; s.members[other]=nil; save() end
    elseif action=='expand' and allowed(s,id,'expand') then
        local radius=s.radius+C.ExpansionStep
        local ok,err=R.claim(s,radius,S.settlements,s.id,C); if not ok then return notice(src,err) end
        local a=account(src,id); if a then queue({kind='expand',actor=id,src=src,sid=s.id,radius=radius,account=a,amount=R.expansion(s,C)}) end
    elseif action=='tax' and allowed(s,id,'finance') and s.debt>0 then
        local a=account(src,id); if a then queue({kind='tax',actor=id,src=src,sid=s.id,account=a,amount=s.debt}) end
    elseif action=='list' and owner(s,id) and s.debt==0 then
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
    elseif action=='move' and b and b.complete and allowed(s,id,'move') then beginPreview(src,s,b,b.exterior,b.interior,'move')
    elseif action=='demolish' and b and allowed(s,id,'demolish') and not occupied(s.id) and d.confirm=='DEMOLISH' then
        s.buildings[b.id]=nil; save()
    elseif action=='lock' and b and allowed(s,id,'members') then b.locked=not b.locked; save()
    end
    if action~='plan' and action~='move' and s.status=='active' then view(src,'camp',s) elseif s.status~='active' then TriggerClientEvent(E..'close',src) end
end
RegisterNetEvent(E..'action',function(action,d)
    local src=tonumber(source); if type(action)~='string' then return end
    local now=GetGameTimer(); if rate[src] and now-rate[src]<200 then return end; rate[src]=now
    run(src,function() request(src,action,d) end,action=='exit')
end)
AddEventHandler('frontier:inventoryItemUsed',function(src,id,itemId)
    if itemId~=C.Kit.id and not C.Furniture[itemId] then return end
    CreateThread(function()
        run(src,function()
            if cid(src)~=id then return end
            local p=position(src); if not p then return end
            if itemId==C.Kit.id then
                if p.bucket~=0 then return end
                local ok,err=R.claim(p,C.InitialRadius,S.settlements,nil,C); if not ok then return notice(src,err) end
                local sid=uuid()
                local claim={id=sid,name='New settlement',x=p.x,y=p.y,z=p.z,radius=C.InitialRadius,owners={[id]=true},primary=id,
                    members={},buildings={},status='active',debt=0,nextTax=os.time()+C.TaxPeriod}
                queue({kind='claim',actor=id,src=src,sid=sid,item=itemId,claim=claim})
            else
                local s,b=findVisit(src)
                if not s or not allowed(s,id,'furnish') then return notice(src,'Enter an authorized interior first.') end
                TriggerClientEvent('frontier_inventory:close',src)
                beginPreview(src,s,b,nil,nil,'furniture',nil,itemId)
            end
        end)
    end)
end)
exports('CanAccessCampStorage',function(src,storage)
    if not ready or next(S.jobs) or type(storage)~='string' then return false end
    local s=settlement(storage:match('^property_([a-f0-9]+)$'))
    return allowed(s,cid(src),'storage') and close(src,{x=s.x+2,y=s.y,z=s.z},C.InteractionDistance) or false
end)
exports('GetProperty',function(id) local s=ready and settlement(id); if s and s.status=='active' then return public(s) end end)
exports('CanAccessProperty',function(id,sid,permission) return ready and allowed(settlement(sid),id,permission)==true end)

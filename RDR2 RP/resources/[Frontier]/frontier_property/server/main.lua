local C,R=PropertyConfig,PropertyRules
local core,inv,eco=exports.frontier_core,exports.frontier_inventory,exports.frontier_economy
local E='frontier_property:'
local S,revision,ready,busy=nil,0,false,false
local rate,visits,workers,previews={}, {}, {}, {}
local function notice(src,msg) TriggerClientEvent(E..'notice',src,tostring(msg)) end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function position(src)
    local ped=GetPlayerPed(src)
    if ped==0 or not DoesEntityExist(ped) then return end
    local v=GetEntityCoords(ped)
    return {x=v.x,y=v.y,z=v.z,bucket=GetPlayerRoutingBucket(src)}
end
local function close(src,p,d,bucket)
    local v=position(src)
    return v and v.bucket==(bucket or 0) and R.near(v,p,d or C.InteractionDistance)
end
local function uuid() return MySQL.scalar.await('SELECT UUID()'):gsub('-','') end
local function load()
    local row=MySQL.single.await('SELECT revision,payload FROM frontier_property_v2_state WHERE id=1')
    assert(row,'Apply Frontier Property migration first')
    S=json.decode(row.payload); revision=tonumber(row.revision)
    S.settlements=S.settlements or {}; S.jobs=S.jobs or {}; S.visits=S.visits or {}
end
local function save()
    local n=MySQL.update.await('UPDATE frontier_property_v2_state SET payload=?,revision=revision+1 WHERE id=1 AND revision=?',{json.encode(S),revision})
    assert(n==1,'Property state revision conflict'); revision=revision+1
end
local function run(src,fn,allowPending)
    if not ready or busy or (not allowPending and next(S.jobs)) then if src then notice(src,'Property busy; try again shortly.') end; return end
    busy=true
    local ok,err=pcall(fn)
    if not ok then
        print('[frontier_property] '..tostring(err))
        local loaded=pcall(load)
        if not loaded then ready=false end
        if src then notice(src,'Request outcome uncertain. Refresh before retrying.') end
    end
    busy=false
end
local function allowed(s,id,perm)
    return s and s.status=='active' and id and (s.owners[id] or (s.members[id] and s.members[id][perm]==true))
end
local function owner(s,id) return s and s.status=='active' and id and s.owners[id] end
local function settlement(id) return type(id)=='string' and S.settlements[id] end
local function chestId(id) return 'property_'..id end
local function bank(id)
    return tonumber(MySQL.scalar.await("SELECT id FROM frontier_economy_accounts WHERE owner_type='character' AND owner_id=? AND account_type='bank' AND currency='USD'",{id}))
end
local function account(src,id)
    local ok,a=eco:GetCharacterAccounts(src)
    if ok and a.characterId==id and cid(src)==id then return a.bank.id end
end
local function opts(job,suffix) return {key='property:'..job.id..':'..suffix,reason='Frontier property '..job.kind,reference=job.id} end
local function queue(j)
    j.id=uuid(); S.jobs[j.id]=j; save()
end
local function endJob(j) S.jobs[j.id]=nil; save() end
local function failJob(j,msg)
    if j.src and cid(j.src)==j.actor then notice(j.src,msg) end
    endJob(j)
end
local function finishJob(j,msg)
    endJob(j)
    if j.src and cid(j.src)==j.actor then notice(j.src,msg or 'Done.'); TriggerClientEvent(E..'refresh',j.src) end
end
local function definite(code) return code=='insufficient_funds' or code=='quantity' or code=='slots' or code=='weight' or code=='capacity' or code=='insufficient_stock' end
local function item(j,add,key,itemId,qty)
    return inv:PropertyChangeCharacter(j.actor,itemId,qty,add,j.id..':'..key)
end
local function debit(j)
    if j.paid then return true end
    local ok,err=eco:DebitAccount(j.account,j.amount,opts(j,'debit'))
    if ok then j.paid=true; save(); return true end
    if definite(err) then failJob(j,err) end
    return false
end
local function take(j)
    local ok,err=item(j,false,'take',j.item,j.qty or 1)
    if ok then return true end
    if definite(err) then failJob(j,err) end
    return false
end
local function payout(j)
    for k,p in ipairs(j.payouts or {}) do
        if p.amount>0 and not p.done then
            local ok=eco:CreditAccount(p.account,p.amount,opts(j,'credit'..k))
            if not ok then return false end
            p.done=true; save()
        end
    end
    return true
end
local function shares(s,amount)
    local ids={}; for id in pairs(s.owners) do ids[#ids+1]=id end; table.sort(ids)
    local out={}; local rest=amount
    for i,id in ipairs(ids) do
        local a=bank(id); if not a then return end
        local n=i==#ids and rest or math.floor(amount/#ids)
        rest=rest-n; out[#out+1]={account=a,amount=n}
    end
    return out
end
local function process(j)
    local s=settlement(j.sid)
    if j.kind=='claim' then
        if not take(j) then return end
        local ok=inv:CreateStorage({id=chestId(j.sid),name='Settlement chest',slots=C.StorageSlots,grams=C.StorageGrams,ace=''})
        if not ok then return end
        S.settlements[j.sid]=j.claim
        finishJob(j,'Settlement established!')
    elseif j.kind=='shop' then
        if not debit(j) then return end
        if not j.refund then
            local ok,err=item(j,true,'grant',j.item,1)
            if ok then finishJob(j,'Item purchased.'); return end
            if not definite(err) then return end
            j.refund=true; save()
        end
        if eco:CreditAccount(j.account,j.amount,opts(j,'refund')) then finishJob(j,'Inventory full; payment refunded.') end
    elseif j.kind=='expand' then
        if not debit(j) then return end
        s.radius=j.radius; finishJob(j,'Territory expanded.')
    elseif j.kind=='tax' then
        if not debit(j) then return end
        s.debt=math.max(0,s.debt-j.amount)
        if s.debt==0 then s.overdue=nil end
        finishJob(j,'Tax paid.')
    elseif j.kind=='deliver' then
        if not take(j) then return end
        local b=s.buildings[j.bid]
        b.delivered[j.item]=(b.delivered[j.item] or 0)+j.qty
        finishJob(j,'Materials delivered.')
    elseif j.kind=='furniture' then
        if not take(j) then return end
        s.buildings[j.bid].furniture[j.fid]=j.furniture
        finishJob(j,'Furniture placed.')
    elseif j.kind=='removeFurniture' then
        local ok,err=item(j,true,'return',j.item,1)
        if ok then s.buildings[j.bid].furniture[j.fid]=nil; finishJob(j,'Furniture returned to inventory.')
        elseif definite(err) then failJob(j,err) end
    elseif j.kind=='sale' then
        if not debit(j) then return end
        if not payout(j) then return end
        s.owners={[j.actor]=true}; s.primary=j.actor; s.members={}; s.listing=nil
        finishJob(j,'Settlement purchased, including chest and furniture.')
    elseif j.kind=='foreclose' then
        if not payout(j) then return end
        s.status='abandoned'; s.listing=nil; finishJob(j)
    end
end
local function buildingStages(e,i)
    local a,b={},{}
    for k,n in pairs(e.materials) do local first=math.max(1,math.floor(n*0.4)); a[k]=first; if n>first then b[k]=n-first end end
    local stages={{label='Foundation',materials=a,tools={'property_hammer'},seconds=math.max(10,math.floor(e.seconds*0.4))},
        {label='Structure',materials=b,tools={'property_hammer','property_saw'},seconds=math.max(10,math.floor(e.seconds*0.6))}}
    if i then stages[#stages+1]={label='Interior',materials=i.materials,tools={'property_hammer','property_saw'},seconds=i.seconds} end
    return stages
end
local function buildingInfo(b)
    return {id=b.id,exterior=b.exterior,interior=b.interior,x=b.x,y=b.y,z=b.z,heading=b.heading,radius=b.radius,
        stage=b.stage,stages=b.stages,delivered=b.delivered,progress=b.progress,complete=b.complete,capacity=b.capacity,furniture=b.furniture,locked=b.locked}
end
local function public(s)
    return {id=s.id,name=s.name,x=s.x,y=s.y,z=s.z,radius=s.radius,map=s.map==true}
end
local function occupied(sid)
    for _,v in pairs(visits) do if v.sid==sid then return true end end
    return false
end
local function view(src,kind,s,b)
    local id=cid(src)
    if not id then return end
    local data={kind=kind,catalogue=C.Exteriors,interiors=C.Interiors,permissions=C.Permissions,shop={C.Kit},market={}}
    for key,t in pairs(C.Tools) do data.shop[#data.shop+1]={id=key,name=t.name,grams=t.grams,price=t.price} end
    for key,t in pairs(C.Furniture) do data.shop[#data.shop+1]={id=key,name=t.name,grams=t.grams,price=t.price} end
    if s then
        data.settlement=public(s); data.settlement.debt=s.debt; data.settlement.tax=R.tax(s,C)
        data.settlement.expansion=R.expansion(s,C); data.settlement.owner=owner(s,id)==true
        data.settlement.rights={}; for _,perm in ipairs(C.Permissions) do data.settlement.rights[perm]=allowed(s,id,perm)==true end
        if allowed(s,id,'members') then data.settlement.members=s.members; data.settlement.owners=s.owners end
        data.settlement.listing=s.listing
        data.buildings={}; for _,x in pairs(s.buildings) do
            local info=buildingInfo(x); info.furniture=nil; data.buildings[#data.buildings+1]=info
        end
        if b then data.building=buildingInfo(b); if kind~='interior' then data.building.furniture=nil end end
    end
    if kind=='market' then
        for _,x in pairs(S.settlements) do if x.status=='active' and x.listing and x.listing.active then
            data.market[#data.market+1]={id=x.id,name=x.name,radius=x.radius,price=x.listing.price,buildings=(function() local n=0; for _ in pairs(x.buildings) do n=n+1 end; return n end)()}
        end end
    end
    TriggerClientEvent(E..'menu',src,data)
end
local function nearCamp(src,s) return s and s.status=='active' and close(src,s) end
local function nearShop(src)
    for _,p in ipairs(C.Shops) do if close(src,p,5) then return true end end
end
local function atInterior(src,s,b)
    local v=visits[src]; local i=b and C.Interiors[b.interior]
    return v and i and v.sid==s.id and v.bid==b.id and v.actor==cid(src) and close(src,i,i.bounds+2,b.bucket)
end
local function findVisit(src)
    local v=visits[src]; local s=v and settlement(v.sid); local b=s and s.buildings[v.bid]
    if s and b and atInterior(src,s,b) and (not b.locked or allowed(s,cid(src),'enter')) then return s,b end
end
local function exit(src)
    local v=visits[src]
    if not v then return end
    local ped=GetPlayerPed(src)
    if ped~=0 then SetPlayerRoutingBucket(src,0); SetEntityCoords(ped,v.x,v.y,v.z,false,false,false,false) end
    visits[src]=nil; S.visits[v.actor]=nil; save()
    TriggerClientEvent(E..'interior',src,false)
end
local function enter(src,s,b,id)
    if not b.complete or not b.interior or (b.locked and not allowed(s,id,'enter')) or not close(src,b,b.radius+C.InteractionDistance) then return end
    local i=C.Interiors[b.interior]; if not i then return end
    local pos=position(src); if not pos or visits[src] then return end; local v={sid=s.id,bid=b.id,actor=id,x=pos.x,y=pos.y,z=pos.z}
    S.visits[id]=v; save(); visits[src]=v
    SetPlayerRoutingBucket(src,b.bucket)
    SetEntityCoords(GetPlayerPed(src),i.x,i.y,i.z,false,false,false,false)
    TriggerClientEvent(E..'interior',src,{anchor=i,settlement=s.id,building=b.id})
end
local function beginPreview(src,s,b,exterior,interior,mode,fid,itemId)
    local id=cid(src)
    previews[src]={sid=s.id,bid=b and b.id,exterior=exterior,interior=interior,mode=mode,fid=fid,item=itemId,actor=id,untilTime=os.time()+120}
    local isFurniture=mode=='furniture' or mode=='moveFurniture'
    local model=isFurniture and C.Furniture[itemId].model or C.Exteriors[exterior].model
    local origin=b and mode=='move' and {x=b.x,y=b.y,z=b.z,heading=b.heading} or nil
    if mode=='moveFurniture' then origin=b.furniture[fid] end
    local blockers={}
    if not isFurniture then for k,v in pairs(s.buildings) do if mode~='move' or k~=b.id then blockers[#blockers+1]={x=v.x,y=v.y,z=v.z,radius=v.radius} end end end
    TriggerClientEvent(E..'preview',src,{model=model,mode=mode,origin=origin,claim=public(s),blockers=blockers,radius=not isFurniture and C.Exteriors[exterior].radius or nil,room=isFurniture and C.Interiors[b.interior] or nil})
end
local function request(src,action,d)
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
local function world(src)
    local p=position(src); if not p or not cid(src) then return end
    local data={claims={},objects={},markers={}}; local v=visits[src]
    local function obj(key,model,x,y,z,h,action,sid,bid)
        data.objects[#data.objects+1]={key=key,model=model,x=x,y=y,z=z,heading=h or 0,action=action,sid=sid,bid=bid}
    end
    if p.bucket==0 then
        for sid,s in pairs(S.settlements) do if s.status=='active' then
            if s.map then data.markers[#data.markers+1]=public(s) end
            if R.distance(p,s)<=s.radius+C.StreamDistance then
                data.claims[#data.claims+1]=public(s)
                if R.distance(p,s)<=C.StreamDistance then
                    obj(sid..'fire',C.Camp.fire,s.x,s.y,s.z,0,'camp',sid)
                    obj(sid..'tent',C.Camp.tent,s.x-3,s.y,s.z,0,nil,sid)
                    obj(sid..'chest',C.Camp.chest,s.x+2,s.y,s.z,0,'chest',sid)
                end
                for bid,b in pairs(s.buildings) do if R.distance(p,b)<=C.StreamDistance then
                    obj(bid,b.complete and C.Exteriors[b.exterior].model or C.Camp.site,b.x,b.y,b.z,b.heading,b.complete and b.interior and 'enter' or not b.complete and 'site' or nil,sid,bid)
                    data.objects[#data.objects].interaction=b.complete and b.radius+C.InteractionDistance or C.InteractionDistance
                end end
            end
        end end
    elseif v and v.actor==cid(src) then
        local s,b=findVisit(src)
        if b then for fid,f in pairs(b.furniture) do obj(fid,C.Furniture[f.item].model,f.x,f.y,f.z,f.heading,nil,s.id,b.id) end end
    end
    TriggerClientEvent(E..'world',src,data)
end
local function tick()
    local now=os.time(); local changed=false; local worked={}
    for src,w in pairs(workers) do
        local s=settlement(w.sid); local b=s and s.buildings[w.bid]
        local valid=b and not b.complete and allowed(s,cid(src),'work') and cid(src)==w.actor and close(src,b)
        if valid then
            local stage=b.stages[b.stage]
            for k,n in pairs(stage.materials) do if (b.delivered[k] or 0)<n then valid=false end end
            if valid then for _,tool in ipairs(stage.tools) do local ok,has=inv:HasItem(src,tool,1); if not ok or not has then valid=false; break end end end
            if valid and cid(src)==w.actor and close(src,b) and not worked[b.id] then
                worked[b.id]=true; b.progress=b.progress+1; changed=true
                if b.progress>=stage.seconds then
                    b.stage=b.stage+1; b.progress=0; b.delivered={}
                    if not b.stages[b.stage] then b.complete=true; workers[src]=nil; notice(src,'Building completed!') else notice(src,'Stage completed.') end
                end
            end
        end
        if not valid then workers[src]=nil; notice(src,'Construction paused: distance, permission, tools or materials.') end
    end
    for _,s in pairs(S.settlements) do if s.status=='active' then
        if now>=s.nextTax then
            local periods=math.floor((now-s.nextTax)/C.TaxPeriod)+1
            if s.debt==0 then s.overdue=s.nextTax end
            s.debt=s.debt+periods*R.tax(s,C); s.nextTax=s.nextTax+periods*C.TaxPeriod; changed=true
        end
        if s.debt>0 and s.overdue and now-s.overdue>=C.TaxGrace and not occupied(s.id) then
            local value=0
            for _,b in pairs(s.buildings) do if b.complete then
                value=value+b.value
                for _,f in pairs(b.furniture) do value=value+C.Furniture[f.item].value end
            end end
            local amount=R.foreclosure(value,s.debt,C); local payments=shares(s,amount)
            if payments then s.status='foreclosing'; queue({kind='foreclose',sid=s.id,payouts=payments}); return end
        end
    end end
    if changed then save() end
end
local function restore(src,id)
    if cid(src)~=id then return end
    local v=S.visits[id]
    if v then
        visits[src]=v; exit(src)
    end
end
AddEventHandler('frontier:playerLoaded',function(player) CreateThread(function()
    if ready then run(player.source,function() restore(player.source,player.frontierCharacterId) end,true) end
end) end)
AddEventHandler('frontier:playerUnloaded',function(player)
    workers[player.source]=nil; previews[player.source]=nil; visits[player.source]=nil
    if GetPlayerRoutingBucket(player.source)>=C.InteriorBucketBase then SetPlayerRoutingBucket(player.source,0) end
end)
AddEventHandler('playerDropped',function() local src=tonumber(source); workers[src]=nil; previews[src]=nil; visits[src]=nil; rate[src]=nil end)
AddEventHandler('onResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for src,v in pairs(visits) do local ped=GetPlayerPed(src); if ped~=0 then SetPlayerRoutingBucket(src,0); SetEntityCoords(ped,v.x,v.y,v.z,false,false,false,false) end end
end)
MySQL.ready(function()
    load()
    local function register(key,d,usable)
        local ok=inv:RegisterItem(key,{name=d.name,description=d.name,category=d.category or 'Settlement',grams=d.grams,maxStack=1,usable=usable})
        if not ok then return false end
        if usable then return inv:RegisterUsableItem(key,function() return true end,'keep') end
        return true
    end
    while true do
        local ok=register(C.Kit.id,C.Kit,true)
        for key,d in pairs(C.Tools) do ok=register(key,d,false) and ok end
        for key,d in pairs(C.Furniture) do ok=register(key,d,true) and ok end
        if ok then break end
        Wait(5000)
    end
    ready=true
    for _,p in pairs(core:GetPlayers()) do run(p.source,function() restore(p.source,p.frontierCharacterId) end,true) end
    while true do
        Wait(C.TickMs)
        if ready then
            run(nil,function()
                local _,j=next(S.jobs)
                if j then process(j) else tick() end
                for _,p in pairs(core:GetPlayers()) do
                    if visits[p.source] and not findVisit(p.source) then exit(p.source) elseif not visits[p.source] and S.visits[p.frontierCharacterId] then restore(p.source,p.frontierCharacterId) end
                    world(p.source)
                end
            end,true)
        else
            if pcall(load) then ready=true end
        end
    end
end)

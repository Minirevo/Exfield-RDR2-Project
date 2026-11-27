local E='frontier_wheel:'
local core=exports.frontier_core
local views,last={},{}
local function cid(src) return core:GetPlayerCharacterId(src) end
local function send(src,msg) TriggerClientEvent(E..'documentsNotice',src,msg) end
local function rate(src)
 local now=GetGameTimer()
 if last[src] and now-last[src]<500 then return false end
 last[src]=now;return true
end
local function near(a,b)
 if a==b or GetPlayerRoutingBucket(a)~=GetPlayerRoutingBucket(b) then return false end
 local p,q=GetPlayerPed(a),GetPlayerPed(b)
 if p==0 or q==0 then return false end
 local x,y=GetEntityCoords(p),GetEntityCoords(q)
 return (x.x-y.x)^2+(x.y-y.y)^2+(x.z-y.z)^2<=9
end
local function records(id)
 local ok,p=core:GetCharacterData(id)
 if not ok or not p then return end
 local name=p.name or ((p.firstname or '')..' '..(p.lastname or ''))
 local out={{key='identity',title='Character identification',holder=name,status='Character record'}}
 if GetResourceState('frontier_business')~='started' then return out,name,'Business registry unavailable.' end
 local success,rows=pcall(function()
  return MySQL.query.await([[
   SELECT l.owner_type,l.owner_id,l.category,l.active,c.name AS company_name,c.status AS company_status
   FROM fb_licenses l LEFT JOIN fb_companies c ON l.owner_type='company' AND c.id=l.owner_id
   WHERE (l.owner_type='character' AND l.owner_id=?)
      OR (l.owner_type='company' AND
          (EXISTS(SELECT 1 FROM fb_shares s WHERE s.company_id=l.owner_id AND s.character_id=?)
           OR EXISTS(SELECT 1 FROM fb_employees e WHERE e.company_id=l.owner_id AND e.character_id=?)))
   ORDER BY l.owner_type,l.owner_id,l.category
  ]],{id,id,id})
 end)
 if not success or type(rows)~='table' then return out,name,'Business registry unavailable.' end
 for _,r in ipairs(rows) do
  local allowed=r.owner_type=='character' or exports.frontier_business:HasCompanyPermission(r.owner_id,id,'licenses')
  if allowed then
   out[#out+1]={key=r.owner_type..':'..r.owner_id..':'..r.category,title=r.category..' license',
    holder=r.company_name or name,status=tonumber(r.active)==1 and (r.owner_type=='character' or r.company_status=='active') and 'Active' or 'Inactive'}
  end
 end
 return out,name
end
local function public(row) return {title=row.title,holder=row.holder,status=row.status} end
RegisterNetEvent(E..'documentsOpen',function(seq,mode)
 local src=source
 if not rate(src) or type(seq)~='number' or seq%1~=0 or seq<1 or seq>2147483646 or (mode~='documents' and mode~='profile') then return end
 local id=cid(src);if not id then TriggerClientEvent(E..'documentsView',src,seq,false);return end
 views[src]=nil
 local rows,name,warning=records(id)
 if not rows or cid(src)~=id then TriggerClientEvent(E..'documentsView',src,seq,false);return end
 local targets,allowed={},{}
 for _,s in pairs(core:GetPlayers()) do
  local other=tonumber(s.source)
  if other and near(src,other) then
   local otherId=cid(other)
   if otherId then targets[#targets+1]={id=other,name=s.name or ('Player '..other)};allowed[other]=otherId end
  end
 end
 table.sort(targets,function(a,b)return a.id<b.id end)
 local display={}
 for i,row in ipairs(rows) do display[i]=public(row) end
 views[src]={id=id,rows=rows,targets=allowed,expires=GetGameTimer()+120000}
 TriggerClientEvent(E..'documentsView',src,seq,{mode=mode,name=name,documents=display,targets=targets,warning=warning})
end)
RegisterNetEvent(E..'documentsPresent',function(index,target)
 local src=source
 if not rate(src) or type(index)~='number' or index%1~=0 or type(target)~='number' or target%1~=0 then return end
 local v=views[src]
 if not v or GetGameTimer()>v.expires or cid(src)~=v.id or not v.rows[index] or not v.targets[target] or cid(target)~=v.targets[target] or not near(src,target) then send(src,'Recipient or document no longer available. Reopen Documents.');return end
 local rows,name=records(v.id)
 if cid(src)~=v.id or cid(target)~=v.targets[target] or not near(src,target) then return end
 local row
 for _,r in ipairs(rows or {}) do if r.key==v.rows[index].key then row=r;break end end
 if not row then send(src,'Document no longer available.');return end
 -- Recipient receives a server-generated record; no client-provided document text.
 TriggerClientEvent('chat:addMessage',target,{args={'Frontier document',name..' presents: '..row.title..' | Holder: '..row.holder..' | Status: '..row.status}})
 send(src,'Document presented to nearby player.')
end)
RegisterNetEvent(E..'documentsClose',function() views[source]=nil end)
AddEventHandler('playerDropped',function() views[source]=nil;last[source]=nil end)

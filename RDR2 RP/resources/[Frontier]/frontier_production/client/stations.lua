local E='frontier_production:station:'
local ticket,shown,opening,pending,work
local seq=0
local previewRecipes,previewObject,previewCam,previewVersion={},nil,nil,0
local previewRotation=0
local previewAsset=nil
local function tell(s)TriggerEvent('chat:addMessage',{args={'Production',tostring(s)}})end
local function ui(d)SendNUIMessage(d)end
local function stopPreview()
 previewVersion=previewVersion+1
 if previewObject and DoesEntityExist(previewObject) then DeleteEntity(previewObject) end;previewObject=nil
 if previewCam then RenderScriptCams(false,false,0,true,true,0);DestroyCam(previewCam,false);previewCam=nil end
 if previewAsset then pcall(Citizen.InvokeNative,0xC3896D03E2852236,previewAsset);previewAsset=nil end
end
local function cachePreview(data)
 previewRecipes={};for _,r in pairs(data.recipes or {}) do if r.manualOnly and r.model then previewRecipes[r.id]=r end end
end
local function close()
 stopPreview();previewRecipes={}
 if ticket then TriggerServerEvent(E..'close',ticket) end
 if shown then SetNuiFocus(false,false) end
 ticket,shown,opening,pending=nil,nil,nil,nil
 if not work then ui({type='stationClose'}) end
end
AddEventHandler('frontier_production:stationOpen',function(sid,fid)
 if shown or opening or work or IsNuiFocused() then return end
 opening=GetGameTimer();local stamp=opening
 TriggerServerEvent(E..'open',sid,fid)
 SetTimeout(10000,function()if opening==stamp then opening=nil;tell('Station did not respond. Check server console.') end end)
end)
RegisterNetEvent(E..'notice',function(msg)
 if source~=65535 then return end
 if opening then opening=nil end
 tell(msg);ui({type='stationNotice',message=msg})
end)
RegisterNetEvent(E..'view',function(token,data)
 if source~=65535 or not opening then return end
 opening=nil
 if IsNuiFocused() then TriggerServerEvent(E..'close',token);return end
 ticket,shown,seq=token,true,0;cachePreview(data)
 SetNuiFocus(true,true);SetNuiFocusKeepInput(false);ui({type='stationOpen',snapshot=data})
end)
RegisterNetEvent(E..'response',function(token,n,d)
 if source~=65535 or token~=ticket or not pending or pending.seq~=n then return end
 pending=nil;if d.snapshot then cachePreview(d.snapshot) end;d.type='stationResult';d.seq=n;ui(d)
end)
RegisterNetEvent(E..'close',function()if source==65535 then close() end end)
RegisterNUICallback('stationClose',function(_,cb)close();cb({ok=true})end)
RegisterNUICallback('gunPreviewStop',function(_,cb)stopPreview();cb({ok=true})end)
RegisterNUICallback('gunPreviewRotate',function(d,cb)
 if previewObject and DoesEntityExist(previewObject) then previewRotation=(previewRotation+(d.direction=='left' and -25 or 25))%360;SetEntityHeading(previewObject,previewRotation) end
 cb({ok=true})
end)
RegisterNUICallback('gunPreview',function(d,cb)
 local r=shown and type(d)=='table' and previewRecipes[d.id]
 if not r or type(d.cosmetics)~='table' then cb({ok=false});return end
 local hashes={};local n=0
 for k,v in pairs(d.cosmetics) do
  n=n+1;if n>24 then cb({ok=false});return end
  local found=false;for _,o in ipairs(r.cosmetics[k] or {}) do if o.hash==v then found=true;break end end
  if not found then cb({ok=false});return end
  hashes[#hashes+1]=v
 end
 stopPreview();local version=previewVersion;cb({ok=true})
 CreateThread(function()
  local ok,err=pcall(function()
   local ped=PlayerPedId();local p=GetOffsetFromEntityInWorldCoords(ped,0.0,1.5,0.9)
   local c=GetOffsetFromEntityInWorldCoords(ped,1.65,1.5,1.2)
   local hash=joaat(r.model)
   -- Unlike the old VORP preview, the player need not already own/equip this model.
   previewAsset=hash
   Citizen.InvokeNative(0x72D4CB5DB927009C,hash,0,true)
   local untilLoaded=GetGameTimer()+8000
   local function loaded()
    local result=Citizen.InvokeNative(0xFF07CF465F48B830,hash,Citizen.ResultAsInteger())
    return result==1 or result==true
   end
   while shown and version==previewVersion and not loaded() and GetGameTimer()<untilLoaded do Wait(50) end
   if not shown or version~=previewVersion then return end
   if not loaded() then error('Display asset streaming timed out: '..r.model) end
   -- Parameter six means showWorldModel, not network ownership.
   local obj=Citizen.InvokeNative(0x9888652B8BA77F73,hash,0,p.x,p.y,p.z,true,1.0,Citizen.ResultAsInteger())
   if not obj or obj==0 then error('Weapon preview unavailable') end
   local deadline=GetGameTimer()+3000
   while shown and version==previewVersion and not DoesEntityExist(obj) and GetGameTimer()<deadline do Wait(50) end
   if not shown or version~=previewVersion then if DoesEntityExist(obj) then DeleteEntity(obj) end;return end
   if not DoesEntityExist(obj) then error('Weapon preview could not initialize') end
   if NetworkGetEntityIsNetworked(obj) then DeleteEntity(obj);error('Unexpected networked preview') end
   previewObject=obj;previewRotation=GetEntityHeading(ped)+90
   SetEntityAsMissionEntity(obj,true,true);FreezeEntityPosition(obj,true);SetEntityCollision(obj,false,false);SetEntityInvincible(obj,true);SetEntityVisible(obj,true);SetEntityHeading(obj,previewRotation)
   for _,h in ipairs(hashes) do pcall(Citizen.InvokeNative,0x74C9090FDD1BB48E,obj,h,-1,true) end
   previewCam=Citizen.InvokeNative(0x40C23491CE83708E,'DEFAULT_SCRIPTED_CAMERA',c.x,c.y,c.z,0.0,0.0,0.0,48.0,false,0,Citizen.ResultAsInteger())
   if not previewCam or previewCam==0 then previewCam=nil;error('Preview camera unavailable') end
   -- Aim to the right of the display object so it occupies the open left-hand view.
   -- The right panel uses the rightmost third of the screen.
   local aim=GetOffsetFromEntityInWorldCoords(ped,0.0,2.10,0.9)
   PointCamAtCoord(previewCam,aim.x,aim.y,aim.z)
   SetCamActive(previewCam,true);RenderScriptCams(true,false,0,true,true,0)
  end)
  if version==previewVersion and shown then
   if not ok then print('[frontier_production] Preview: '..tostring(err));stopPreview() end
   ui({type='gunPreviewStatus',ok=ok,message=ok and '' or ('Preview failed: '..tostring(err)..' (see F8)')})
  end
 end)
end)
RegisterNUICallback('stationRequest',function(d,cb)
 if not shown or pending or type(d)~='table' or type(d.action)~='string' or type(d.data)~='table' then cb({ok=false});return end
 if d.retry and type(d.seq)=='number' and d.seq==seq then else seq=seq+1 end
 local request={seq=seq};pending=request
 TriggerServerEvent(E..'request',ticket,seq,d.action,d.data)
 SetTimeout(12000,function()if pending==request then pending=nil;ui({type='stationResult',seq=request.seq,ok=false,retry=true,message='No confirmation. Retry the same request.'}) end end)
 cb({ok=true,seq=seq})
end)
local scenarios={gunsmith='WORLD_HUMAN_CROUCH_INSPECT',sawmill='WORLD_HUMAN_HAMMER',carpentry='WORLD_HUMAN_HAMMER',smeltery='WORLD_HUMAN_HAMMER',forge='WORLD_HUMAN_HAMMER',anvil='WORLD_HUMAN_HAMMER',tanning='WORLD_HUMAN_CROUCH_INSPECT',leatherwork='WORLD_HUMAN_CROUCH_INSPECT',stove='WORLD_HUMAN_CROUCH_INSPECT',oven='WORLD_HUMAN_CROUCH_INSPECT',mill='WORLD_HUMAN_HAMMER',kiln='WORLD_HUMAN_HAMMER',pottery='WORLD_HUMAN_CROUCH_INSPECT',glass='WORLD_HUMAN_HAMMER',apothecary='WORLD_HUMAN_CROUCH_INSPECT',jewellery='WORLD_HUMAN_CROUCH_INSPECT'}
local function clear()
 if work then ClearPedTasksImmediately(PlayerPedId()) end
 work=nil;ui({type='stationEnd'})
end
RegisterNetEvent(E..'work',function(d)
 if source~=65535 or work then return end
 close()
 if IsNuiFocused() or IsPedDeadOrDying(PlayerPedId(),true) or IsPedOnMount(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(),false) then TriggerServerEvent(E..'cancel',d.id);return end
 work=d;d.started=GetGameTimer()+(d.leadMs or 500);d.hits={}
 ui({type='stationWork',label=d.label,ms=d.ms,targets=d.targets,rounds=d.rounds,batches=d.batches,roundMs=d.roundMs,sweepMs=d.sweepMs,width=d.width,stages=d.stages,elapsed=GetGameTimer()-d.started})
 pcall(TaskStartScenarioInPlace,PlayerPedId(),GetHashKey(scenarios[d.kind] or 'WORLD_HUMAN_HAMMER'),d.ms,true,false,false,false)
 CreateThread(function()
  local lastSend,lastSync=0,-1000
  while work==d do
   local elapsed=GetGameTimer()-d.started
   if elapsed-lastSync>=100 then lastSync=elapsed;ui({type='stationClock',elapsed=elapsed}) end
   if IsPedDeadOrDying(PlayerPedId(),true) or IsControlJustPressed(0,0x156F7119) then TriggerServerEvent(E..'cancel',d.id);clear();return end
   DisableControlAction(0,0xD9D0E1C0,true)
   local round=math.floor(elapsed/d.roundMs)+1
   local relative=elapsed-(round-1)*d.roundMs
   if elapsed>=0 and round>=1 and round<=#d.targets and relative<=d.sweepMs and not d.hits[round] and IsDisabledControlJustPressed(0,0xD9D0E1C0) then
    d.hits[round]=true
    TriggerServerEvent(E..'strike',d.id,round,elapsed)
    ui({type='stationStrike',round=round,position=relative/d.sweepMs})
   end
   if elapsed>=d.ms+200 and elapsed-lastSend>=1000 then
    lastSend=elapsed;TriggerServerEvent(E..'finish',d.id)
   end
   if elapsed>d.ms+12000 then tell('Work confirmation timed out; the worker will recover the reserved materials.');clear();return end
   Wait(0)
  end
 end)
end)
RegisterNetEvent(E..'strikeResult',function(id,round,score)
 if source==65535 and work and work.id==id then ui({type='stationStrikeResult',round=round,score=score}) end
end)
RegisterNetEvent(E..'end',function(msg)if source==65535 then clear();if msg~='' then tell(msg) end end end)
AddEventHandler('onClientResourceStop',function(r)if r==GetCurrentResourceName() then close();clear() end end)

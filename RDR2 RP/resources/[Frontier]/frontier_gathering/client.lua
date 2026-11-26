local C,R=GatherConfig,GatherRules
local E='frontier_gathering:'
local models={}
for _,s in ipairs(C.trees) do models[GetHashKey(s)&0xffffffff]='logging' end
for _,s in ipairs(C.rocks) do models[GetHashKey(s)&0xffffffff]='mining' end
for s in pairs(C.herbs) do models[GetHashKey(s)&0xffffffff]='herbalism' end
local wildlife={}
for s in pairs(C.animals) do wildlife[GetHashKey(s)&0xffffffff]=true end
local candidate,work,prop,waterMode,waiting=nil,nil,nil,'prospecting',0
local hidden={}
local function notice(s)TriggerEvent('chat:addMessage',{args={'Gathering',s}})end
local function ui(d)SendNUIMessage(d)end
local function usable()
 local ped=PlayerPedId()
 return not IsNuiFocused() and not IsPauseMenuActive() and not IsPedDeadOrDying(ped,true) and not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped,false) and not IsPedSwimming(ped)
end
local function restore(id)
 local e=hidden[id];if not e then return end
 if e.mod then Citizen.InvokeNative(0x9CF1836C03FB67A2,Citizen.PointerValueIntInitialized(e.mod),0) end
 if e.model and e.model~=0 then pcall(Citizen.InvokeNative,0x3F38A98576F6213A,e.x,e.y,e.z,1.2,e.model,true) end
 if e.stump and DoesEntityExist(e.stump) then DeleteEntity(e.stump) end
 hidden[id]=nil
end
local function hide(row)
 if hidden[row.id] then return end
 local e={x=row.x,y=row.y,z=row.z,model=tonumber(row.model),action=row.action}
 hidden[row.id]=e
 if row.action=='logging' or row.action=='herbalism' then
  pcall(Citizen.InvokeNative,0x069848B3FB3C4426,e.x,e.y,e.z,1.2,e.model,true)
  if row.action=='logging' then
   local ok,m=pcall(Citizen.InvokeNative,0xFA50F79257745E74,e.x,e.y,e.z,1.1,1,64,0,Citizen.ResultAsInteger())
   if ok and m and m~=0 then e.mod=m end
   CreateThread(function()
    local h=GetHashKey('p_tree_stump_cedar_01');if not IsModelValid(h) then return end
    RequestModel(h);local t=GetGameTimer()+2000
    while not HasModelLoaded(h) and GetGameTimer()<t do Wait(20) end
    if not HasModelLoaded(h) or hidden[row.id]~=e then SetModelAsNoLongerNeeded(h);return end
    local ok,z=GetGroundZFor_3dCoord(e.x,e.y,e.z+3,false)
    local obj=CreateObject(h,e.x,e.y,ok and z or e.z,false,false,false,false,false)
    if obj and obj~=0 then FreezeEntityPosition(obj,true);e.stump=obj end
    SetModelAsNoLongerNeeded(h)
   end)
  end
 end
end
RegisterNetEvent(E..'depleted',function(row)
 if source~=65535 then return end
 local p=GetEntityCoords(PlayerPedId());if #(p-vector3(row.x,row.y,row.z))<C.stream then hide(row) end
end)
RegisterNetEvent(E..'world',function(rows)
 if source~=65535 then return end
 local seen={};for _,row in ipairs(rows) do seen[row.id]=true;hide(row) end
 for id in pairs(hidden) do if not seen[id] then restore(id) end end
end)
local function waterNearby(ped,p)
 if IsEntityInWater(ped) and not IsPedSwimming(ped) then return true end
 local ok,z=pcall(GetWaterMapZoneAtCoords,p.x,p.y,p.z)
 return ok and z and z~=0
end
local function scan()
 local ped=PlayerPedId();local p=GetEntityCoords(ped)
 local best,distance=nil,C.reach
 local itemset=CreateItemset(true)
 local size=Citizen.InvokeNative(0x59B57C4B06531E1E,p,C.reach,itemset,3,Citizen.ResultAsInteger())
 local function consider(entity)
  if not entity or entity==0 or not DoesEntityExist(entity) then return end
  local h=GetEntityModel(entity)&0xffffffff;local a=models[h];if not a then return end
  local v=GetEntityCoords(entity);local d=#(p-v)
  if d>distance or (a=='logging' and R.protected(v.x,v.y)) or hidden[R.key(a,v.x,v.y,v.z)] then return end
  best={action=a,model=h,x=v.x,y=v.y,z=v.z};distance=d
 end
 for i=0,(size or 0)-1 do consider(GetIndexedItemInItemset(i,itemset)) end
 if IsItemsetValid(itemset) then DestroyItemset(itemset) end
 -- Plants are also exposed through the object pool in some RedM builds.
 if not best then for _,obj in ipairs(GetGamePool('CObject')) do consider(obj) end end
 if best then return best end
 if R.region(p.x,p.y) and waterNearby(ped,p) and not hidden[R.key(waterMode,p.x,p.y,p.z)] then
  return {action=waterMode,model=0,x=p.x,y=p.y,z=p.z}
 end
end
local function clear()
 if work then ClearPedTasksImmediately(PlayerPedId()) end
 if prop and DoesEntityExist(prop) then DetachEntity(prop,true,true);DeleteEntity(prop) end
 work,prop=nil,nil;waiting=0;ui({type='end'})
end
RegisterNetEvent(E..'notice',function(s)if source==65535 then waiting=0;notice(s) end end)
RegisterNetEvent(E..'end',function()if source==65535 then clear() end end)
local function startAnim(d)
 local ped=PlayerPedId();local a=C.actions[d.action] or {scenario='WORLD_HUMAN_HAMMER'}
 if a.prop then
  local h=GetHashKey(a.prop)
  if IsModelValid(h) then
   RequestModel(h);local deadline=GetGameTimer()+600
   while not HasModelLoaded(h) and GetGameTimer()<deadline do Wait(10) end
   if work~=d then SetModelAsNoLongerNeeded(h);return end
   if HasModelLoaded(h) then
    local p=GetEntityCoords(ped);prop=CreateObject(h,p.x,p.y,p.z,false,false,false,false,false)
    if prop and prop~=0 then AttachEntityToEntity(prop,ped,GetPedBoneIndex(ped,7966),0.0,0.0,0.0,0.0,0.0,0.0,false,false,false,false,2,true,false,false) end
   end
   SetModelAsNoLongerNeeded(h)
  end
 end
 local dict=d.action=='logging' and 'amb_work@world_human_tree_chop_new@working@pre_swing@male_a@trans' or d.action=='mining' and 'amb_work@world_human_pickaxe_new@working@male_a@trans'
 if dict then
  RequestAnimDict(dict);local deadline=GetGameTimer()+700
  while not HasAnimDictLoaded(dict) and GetGameTimer()<deadline do Wait(10) end
  if work==d and HasAnimDictLoaded(dict) then TaskPlayAnim(ped,dict,'pre_swing_trans_after_swing',4.0,2.0,d.ms,1,0,false,0,false,'',true);return end
 end
 if work==d then pcall(TaskStartScenarioInPlace,ped,GetHashKey(a.scenario),d.ms,true,false,false,false) end
end
RegisterNetEvent(E..'work',function(d)
 if source~=65535 then return end
 if not usable() or work then TriggerServerEvent(E..'cancel');return end
 waiting=0;work=d;d.started=GetGameTimer();ui({type='work',label=d.label,ms=d.ms,target=d.target,width=d.width,qte=d.qte})
 CreateThread(function()startAnim(d)end)
 CreateThread(function()
  while work==d do
   local elapsed=GetGameTimer()-d.started
   if IsPedDeadOrDying(PlayerPedId(),true) or IsControlJustPressed(0,0x156F7119) then TriggerServerEvent(E..'cancel');clear();return end
   DisableControlAction(0,0xD9D0E1C0,true)
   if d.qte and not d.hit and IsDisabledControlJustPressed(0,0xD9D0E1C0) then
    d.hit=true;TriggerServerEvent(E..'strike',d.token);ui({type='strike'})
   end
   if elapsed>=d.ms+150 then TriggerServerEvent(E..'finish',d.token);clear();return end
   Wait(0)
  end
 end)
end)
local function begin()
 if work or not usable() or GetGameTimer()<waiting then return end
 local n=scan()
 if not n then return notice('No compatible natural resource nearby') end
 waiting=GetGameTimer()+5000;TriggerServerEvent(E..'begin',n)
end
RegisterCommand('gather',begin,false)
RegisterCommand('gatherwater',function(_,args)
 local mode=args[1];if mode~='prospecting' and mode~='clay' and mode~='sand' then return notice('Use /gatherwater prospecting, clay or sand') end
 waterMode=mode;notice('River activity: '..C.actions[mode].name)
end,false)
RegisterCommand('gatherrecover',function()TriggerServerEvent(E..'recover')end,false)
RegisterCommand('gathersurvey',function()local n=scan();if n then TriggerServerEvent(E..'survey',n) else notice('No compatible resource nearby') end end,false)
RegisterCommand('fish',function()
 if not C.nativeFishing or not usable() or work then return end
 local ped=PlayerPedId();local _,weapon=GetCurrentPedWeapon(ped,true,0,false)
 if weapon~=GetHashKey('WEAPON_FISHINGROD') or not waterNearby(ped,GetEntityCoords(ped)) then return notice('Equip your native fishing rod and stand at the water edge') end
 TriggerServerEvent(E..'fishStart')
end,false)
CreateThread(function()
 while true do
  Wait(600)
  if not work and usable() then candidate=scan();ui({type='hint',label=candidate and C.actions[candidate.action].name or nil,river=candidate and candidate.model==0}) else candidate=nil;ui({type='hint'}) end
 end
end)
CreateThread(function()
 while true do
  if candidate and not work and usable() and (IsControlJustPressed(0,C.interactControl) or IsDisabledControlJustPressed(0,C.interactControl)) then begin() end
  Wait(candidate and 0 or 150)
 end
end)
CreateThread(function()while true do TriggerServerEvent(E..'world');Wait(5000) end end)
CreateThread(function()
 if not C.nativeHunting then return end
 while true do
  Wait(0)
  if not work then for i=0,GetNumberOfEvents(0)-1 do
   if GetEventAtIndex(0,i)==GetHashKey('EVENT_LOOT_COMPLETE') then
    local d=DataView.ArrayBuffer(24)
    if Citizen.InvokeNative(0x57EC5FA4D4D6AFCA,0,i,d:Buffer(),3) and d:GetInt32(0)==PlayerPedId() and d:GetInt32(16)==1 then
     local ped=d:GetInt32(8)
     if DoesEntityExist(ped) and wildlife[GetEntityModel(ped)&0xffffffff] then
      local model=GetEntityModel(ped)&0xffffffff
      local dead=IsEntityDead(ped) or IsPedDeadOrDying(ped,true)
      if NetworkGetEntityIsNetworked(ped) then
       TriggerServerEvent(E..'skin',NetworkGetNetworkIdFromEntity(ped),model,dead==true or dead==1)
      else
       notice('This animal is not networked; its reward cannot be verified.')
      end
     end
    end
   end
  end end
 end
end)
AddEventHandler('onResourceStop',function(name)
 if name~=GetCurrentResourceName() then return end
 clear();for id in pairs(hidden) do restore(id) end
end)

RegisterCommand('smith',function(_,args)
 if usable() and not work then TriggerServerEvent(E..'smithBegin',args[1],args[2],false) end
end,false)
RegisterCommand('repair',function(_,args)
 if usable() and not work then TriggerServerEvent(E..'smithBegin',args[1],nil,true) end
end,false)

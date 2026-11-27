-- Persistent inventory-backed firearm native adapter. One live weapon at a time.
FrontierWeapons={}
local W=FrontierWeapons
local R=FrontierWeaponRules
local E='frontier_inventory:'
local active,draw,release,reload=nil,nil,nil,nil
local residual={}
local sequence=0
local lastReport=0
local function nextRequest() sequence=sequence%2147483646+1;return sequence end
local function truth(v) return v==true or v==1 end
local function log(s) print('[frontier_weapons] '..s) end
local function notice(s) TriggerEvent('chat:addMessage',{args={'Frontier Weapons',s}});log(s) end
local function count(s)
 if not s or not DoesEntityExist(s.ped) then return 0 end
 return math.max(0,math.floor(tonumber(GetPedAmmoByType(s.ped,s.ammo)) or 0))
end
local function clip(s)
 local _,n=GetAmmoInClip(s.ped,s.hash)
 return math.max(0,math.floor(tonumber(n) or 0))
end
local function held(s) return s and GetPedCurrentHeldWeapon(s.ped)==s.hash end
local function validPed(s)
 return s and PlayerPedId()==s.ped and LocalPlayer.state.IsInSession and not truth(IsEntityDead(s.ped))
end
local function legacyRunning()
 for _,name in ipairs({'vorp_inventory','vorp_weaponsv2'}) do
  local state=GetResourceState(name)
  if state=='started' or state=='starting' then return true end
 end
 return false
end
local function removeNative(s)
 if not s or not s.created or not DoesEntityExist(s.ped) then return end
 -- Native projection belongs to Frontier; only remove a model we granted.
 -- Capture remaining ammunition before calling this function.
 local ok,err=pcall(function()
  if held(s) then SetCurrentPedWeapon(s.ped,joaat('WEAPON_UNARMED'),false,0,false,false) end
  RemoveWeaponFromPed(s.ped,s.hash,true,0)
  SetPedAmmo(s.ped,s.hash,0)
  SetPedAmmoByType(s.ped,s.ammo,0)
 end)
 if not ok then log('Native removal error: '..tostring(err)) end
 residual[s.hash]=s
end
local function cleanResidual(p)
 -- A native removal can complete asynchronously. Retry only our own known
 -- models, never clear arbitrary legacy equipment or grant extra ammunition.
 for hash,s in pairs(residual) do
  if s.ped~=p then residual[hash]=nil
  else
   local ok,has=pcall(HasPedGotWeapon,p,hash,0,false)
   local ammo=count(s)
   if not ok then return false end
   if truth(has) or ammo>0 or held(s) then
    removeNative(s)
    local checked,still=pcall(HasPedGotWeapon,p,hash,0,false)
    if not checked or truth(still) or count(s)>0 or held(s) then return false end
   end
   s.created=false;residual[hash]=nil
  end
 end
 return true
end
function W.active() return active~=nil or draw~=nil or release~=nil end
exports('IsPersistentWeaponActive',W.active)
function W.busy() return draw~=nil or release~=nil end
function W.cancelReload()
 if reload and active and not reload.cancelled then
  reload.cancelled=true;TriggerServerEvent(E..'weaponCancelReload',active.lease,reload.request)
 end
end
local function reset(reason)
 local s=active
 active,draw,reload=nil,nil,nil
 if s then removeNative(s) end
 if release then local cb=release.callback;release=nil;if cb then cb(false) end end
 if reason then notice(reason) end
end
local function abandon(reason)
 local s=active or (release and release.state)
 if s then TriggerServerEvent(E..'weaponAbandon',s.lease) end
 reset(reason)
end
local function sendRelease(q)
 TriggerServerEvent(E..'weaponRelease',q.state.lease,q.version,q.remaining)
end
function W.holster(callback)
 if release or draw then if callback then callback(false) end;return end
 if not active then if callback then callback(true) end;return end
 W.cancelReload()
 local s=active
 local remaining=s.created and math.min(s.upper,count(s)) or s.upper
 active=nil;reload=nil
 removeNative(s)
 release={state=s,version=s.version,remaining=remaining,callback=callback,started=GetGameTimer()}
 sendRelease(release)
end
RegisterNetEvent(E..'weaponReleaseResult',function(token,ok,reason)
 if source~=65535 or not release or release.state.lease~=token then return end
 local q=release
 if ok then release=nil;if q.callback then q.callback(true) end;return end
 if (reason=='busy' or reason=='conflict' or reason=='database_error') and GetGameTimer()-q.started<4500 then
  SetTimeout(350,function() if release==q then sendRelease(q) end end)
 else abandon('Could not save holstered ammunition: '..tostring(reason)) end
end)
local function startDraw(token,slot)
 if not LocalPlayer.state.IsInSession or not token or draw or release or active then return end
 if legacyRunning() then notice('Legacy inventory is still running. Frontier firearm cutover required.');return end
 local p=PlayerPedId()
 if p==0 or truth(IsEntityDead(p)) then return end
 if not cleanResidual(p) then notice('Native holster is still settling. Retry after the animation.');return end
 -- Reject unknown native weapons instead of deleting them.
 for _,d in pairs(R.models) do
  local ok,has=pcall(HasPedGotWeapon,p,joaat(d.model),0,false)
  local ammo=tonumber(GetPedAmmoByType(p,joaat(d.nativeAmmo))) or 0
  if not ok or truth(has) or ammo>0 then
   notice(('Unexpected native equipment: %s owned=%s, ammo=%d. Reconnect after the legacy inventory cutover.'):format(d.model,tostring(has),ammo));return
  end
 end
 local request=nextRequest()
 draw={request=request,ped=p,started=GetGameTimer()}
 TriggerServerEvent(E..'weaponDraw',token,slot,request)
end
function W.select(token,slot)
 if W.busy() then return end
 if active and active.slot==slot then W.holster();return end
 W.holster(function(ok) if ok then startDraw(token,slot) end end)
end
RegisterNetEvent(E..'weaponDrawResult',function(request,ok,data,msg)
 if source~=65535 then return end
 if not draw or request~=draw.request then
  if ok and type(data)=='table' then TriggerServerEvent(E..'weaponAbandon',data.lease) end
  return
 end
 local q=draw;draw=nil
 if not ok then notice(msg or 'Draw refused.');return end
 local d=type(data)=='table' and R.models[data.item]
 if legacyRunning() or not d or q.ped~=PlayerPedId() or not LocalPlayer.state.IsInSession or truth(IsEntityDead(q.ped)) then
  if data and data.lease then TriggerServerEvent(E..'weaponAbandon',data.lease) end
  return
 end
 local s={ped=q.ped,slot=data.slot,item=data.item,lease=data.lease,serial=data.serial,version=data.version,
  upper=data.rounds,hash=joaat(d.model),ammo=joaat(d.nativeAmmo),capacity=d.capacity,created=false}
 active=s
 local success,err=pcall(function()
  if truth(HasPedGotWeapon(s.ped,s.hash,0,false)) or GetPedAmmoByType(s.ped,s.ammo)>0 then error('Native equipment changed during draw') end
  GiveWeaponToPed(s.ped,s.hash,0,false,false,0,false,0.5,1.0,0,false,0.0,false)
  s.created=true
  if not truth(HasPedGotWeapon(s.ped,s.hash,0,false)) then error('Native grant failed') end
  SetAmmoTypeForPedWeapon(s.ped,s.hash,s.ammo)
  SetPedAmmoByType(s.ped,s.ammo,0)
  SetCurrentPedWeapon(s.ped,s.hash,true,0,false,false)
  if s.upper>0 then
   AddAmmoToPedByType(s.ped,s.ammo,s.upper,0)
   if type(SetAmmoInClip)=='function' then pcall(SetAmmoInClip,s.ped,s.hash,s.upper) end
   if clip(s)==0 and count(s)>0 then MakePedReload(s.ped) end
  end
 end)
 if not success then
  log(tostring(err));W.holster();notice('Could not draw native weapon.');return
 end
 lastReport=GetGameTimer()+750
 log(('Drew %s | serial %s | checked out %d'):format(d.model,s.serial,s.upper))
end)
RegisterNetEvent(E..'weaponReset',function(reason)
 if source==65535 then reset(W.active() and reason or nil) end
end)
RegisterNetEvent(E..'weaponReloadWait',function(token,request,from,delay)
 if source~=65535 or not active or active.lease~=token or not reload or reload.request~=request then return end
 if from=='satchel' and not reload.cancelled then notice('Retrieving satchel ammunition…') end
end)
local function animate(s)
 if not held(s) then return end
 MakePedReload(s.ped)
 SetTimeout(250,function() if active==s and held(s) and not truth(IsPedReloading(s.ped)) and clip(s)<count(s) then TaskReloadWeapon(s.ped,false) end end)
end
RegisterNetEvent(E..'weaponReloadResult',function(token,request,ok,version,amount,reason)
 if source~=65535 or not active or active.lease~=token or not reload or reload.request~=request then return end
 local s=active;local q=reload;reload=nil
 if not ok then if not q.cancelled then notice(reason or 'Reload refused.') end;return end
 if version~=s.version+1 or not R.integer(amount,1,s.capacity) then abandon('Invalid reload response.');return end
 s.version=version;s.upper=q.remaining+amount
 if not validPed(s) then abandon('Character changed during reload.');return end
 -- The server already debited these rounds. A cancelled animation can leave
 -- prepaid native reserve; it is loaded on the next R without a second debit.
 local before=count(s)
 SetAmmoTypeForPedWeapon(s.ped,s.hash,s.ammo)
 AddAmmoToPedByType(s.ped,s.ammo,amount,0)
 local actual=math.max(0,count(s)-before)
 if actual~=amount then log(('Native accepted %d of %d paid rounds'):format(actual,amount)) end
 lastReport=GetGameTimer()+750
 if not q.cancelled and held(s) and not W.wheelOpen and not IsNuiFocused() and not IsPauseMenuActive() then animate(s) end
end)
local function requestReload(s)
 if reload or truth(IsPedReloading(s.ped)) then return end
 local n=count(s);local c=clip(s)
 if n>s.upper then abandon('Unexpected native ammo pool; weapon isolated.');return end
 if c>=s.capacity then return end
 if n>c then animate(s);return end
 if n>=s.capacity then return end
 local request=nextRequest()
 reload={request=request,remaining=n,started=GetGameTimer(),cancelled=false}
 s.upper=n
 TriggerServerEvent(E..'weaponReload',s.lease,request,s.version,n)
end
function W.decorate(guns)
 if not guns or not active then return guns end
 for _,row in ipairs(guns) do if row.serial==active.serial then row.loaded=clip(active);row.equipped=held(active) end end
 return guns
end
RegisterCommand('frontierweaponstatus',function()
 if active then notice(('Serial %s | clip %d | native total %d | server allowance %d | reload pending %s'):format(active.serial,clip(active),count(active),active.upper,tostring(reload~=nil)))
 else notice('No persistent firearm drawn.') end
 local p=PlayerPedId()
 for _,d in pairs(R.models) do
  local ok,has=pcall(HasPedGotWeapon,p,joaat(d.model),0,false)
  notice(('%s | native owned=%s | ammo=%s'):format(d.model,ok and tostring(has) or 'native error',tostring(GetPedAmmoByType(p,joaat(d.nativeAmmo)))))
 end
end,false)
RegisterCommand('frontierweaponholster',function() W.holster() end,false)
local reloadControl=joaat('INPUT_RELOAD')
CreateThread(function()
 while true do
  Wait(W.active() and 0 or 100)
  local now=GetGameTimer()
  if draw and (now-draw.started>5000 or draw.ped~=PlayerPedId() or not LocalPlayer.state.IsInSession) then local q=draw;draw=nil;TriggerServerEvent(E..'weaponAbortDraw',q.request);notice('Weapon draw timed out.') end
  if release and now-release.started>6000 then abandon('Holster response timed out.') end
  local s=active
  if s then
   if legacyRunning() then abandon('Legacy inventory started; Frontier firearm disabled.')
   elseif not validPed(s) then abandon('Character or death state changed.')
   elseif not truth(HasPedGotWeapon(s.ped,s.hash,0,false)) then abandon('Native weapon was removed.')
   else
    local menu=W.wheelOpen or IsNuiFocused() or IsPauseMenuActive()
    if reload and (menu or not held(s)) then W.cancelReload() end
    if reload and now-reload.started>6500 then abandon('Reload response timed out.')
    elseif active==s then
     if held(s) then
      DisableControlAction(0,reloadControl,true)
      if reload then
       DisableControlAction(0,0x07CE1E61,true)
       if type(DisablePlayerFiring)=='function' then DisablePlayerFiring(PlayerId(),true) end
      elseif not menu and IsDisabledControlJustPressed(0,reloadControl) then requestReload(s) end
     end
     if not reload and now-lastReport>=250 then
      lastReport=now
      local n=count(s)
      if n>s.upper then abandon('Unexpected native ammunition; weapon isolated.')
      elseif n<s.upper then s.upper=n;TriggerServerEvent(E..'weaponReport',s.lease,s.version,n) end
     end
    end
   end
  end
 end
end)
AddEventHandler('onClientResourceStop',function(r)
 if r==GetCurrentResourceName() or r=='frontier_inventory' then
  if active then
   local s=active;local n=math.min(s.upper,count(s))
   TriggerServerEvent(E..'weaponRelease',s.lease,s.version,n)
  end
  reset()
 end
end)
AddEventHandler('vorp:SelectedCharacter',function() if W.active() then abandon('Character changed.') end;residual={} end)

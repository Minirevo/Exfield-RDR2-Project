-- Disposable native firearm experiment. No persistent weapon or ammunition ownership.
FrontierGunLab={}
local L=FrontierGunLab
local E='frontier_wheel:'
local weapons={
 {name='Cattleman Revolver',hash=joaat('WEAPON_REVOLVER_CATTLEMAN'),ammo=joaat('AMMO_REVOLVER'),label='Revolver',serial='LAB-R-001',capacity=24},
 {name='Lancaster Repeater',hash=joaat('WEAPON_REPEATER_WINCHESTER'),ammo=joaat('AMMO_REPEATER'),label='Repeater',serial='LAB-L-002',capacity=30}
}
local active,ped,job=false,nil,nil
local function log(s) print('[frontier_gunlab] '..s) end
local function notice(s) TriggerEvent('chat:addMessage',{args={'Frontier Gun Lab',s}});log(s) end
local function truth(v) return v==true or v==1 end
local function held(p) return GetPedCurrentHeldWeapon(p) end
local function clip(w)
 local ok,n=GetAmmoInClip(ped,w.hash)
 return tonumber(n) or 0
end
local function total(w) return tonumber(GetPedAmmoByType(ped,w.ammo)) or 0 end
local function current()
 if not active or PlayerPedId()~=ped then return end
 local h=held(ped)
 for i,w in ipairs(weapons) do if h==w.hash then return w,i end end
end
function L.active() return active end
exports('IsGunLabActive',L.active)
function L.holster()
 if active and PlayerPedId()==ped then
  job=nil
  SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),false,0,false,false)
 end
end
local function stop(reason)
 if not active then return end
 job=nil
 -- Remove only lab-created models and their temporary regular ammunition.
 if ped and DoesEntityExist(ped) then
  for _,w in ipairs(weapons) do
   if w.created then
    SetPedAmmoByType(ped,w.ammo,0)
    RemoveWeaponFromPed(ped,w.hash,true,0)
   end
   w.created=false
  end
 end
 active=false;ped=nil
 TriggerEvent('frontier_wheel:gunLabChanged',false)
 notice('Test ended: '..(reason or 'disabled'))
end
local function start()
 if active then return end
 if not LocalPlayer.state.IsInSession then notice('Select a character first.');return end
 local p=PlayerPedId()
 if p==0 or truth(IsEntityDead(p)) or truth(IsPedOnMount(p)) or truth(IsPedInAnyVehicle(p,false)) then notice('Start on foot.');return end
 if type(HasPedGotWeapon)~='function' then notice('HasPedGotWeapon native unavailable; test aborted.');return end
 -- Do not overwrite an existing weapon or ammunition pool. Use an empty test character.
 for _,w in ipairs(weapons) do
  local ok,has=pcall(HasPedGotWeapon,p,w.hash,0,false)
  if not ok or truth(has) or GetPedAmmoByType(p,w.ammo)>0 then
   notice('Existing '..w.label..' weapon/ammo or native unavailable. Use an empty test character.');return
  end
 end
 ped=p;active=true
 for _,w in ipairs(weapons) do
  w.quick=w.capacity;w.bag=w.capacity*2;w.created=false
  local ok,err=pcall(GiveWeaponToPed,ped,w.hash,0,false,false,0,false,0.5,1.0,0,false,0.0,false)
  if not ok then stop('grant native failed: '..tostring(err));return end
  w.created=true
  SetAmmoTypeForPedWeapon(ped,w.hash,w.ammo)
  SetPedAmmoByType(ped,w.ammo,0)
  if not truth(HasPedGotWeapon(ped,w.hash,0,false)) then stop('weapon grant not confirmed');return end
 end
 L.holster()
 TriggerEvent('frontier_wheel:gunLabChanged',true)
 notice('Active: hold TAB, Q switches pages. Select a gun, press R to reload. /frontiergunammo shows ammo.')
end
RegisterNetEvent(E..'gunLabGrant',function()
 if source==65535 then start() end
end)
RegisterNetEvent(E..'gunLabDenied',function()
 if source==65535 then notice('Test permission denied: frontier.wheel.gunlab') end
end)
RegisterCommand('frontierguntest',function()
 if active then stop('disabled') else TriggerServerEvent(E..'gunLabRequest') end
end,false)
function L.select(slot)
 if not active or not weapons[slot] then return end
 job=nil
 TriggerServerEvent('frontier_inventory:holsterTool')
 SetCurrentPedWeapon(ped,weapons[slot].hash,true,0,false,false)
 log('selected '..weapons[slot].name)
end
function L.snapshot()
 local s={}
 for i,w in ipairs(weapons) do
  s[i]={name=w.name,kind='weapon',serial=w.serial,loaded=clip(w),quick=w.quick,bag=w.bag,
   equipped=held(ped)==w.hash,nativeTotal=total(w)}
 end
 for i=3,6 do s[i]={name='Empty',kind=false} end
 return s
end
local function status()
 if not active then notice('Gun lab is off.');return end
 for _,w in ipairs(weapons) do
  notice(('%s | clip %d | native total %d | quick %d | satchel %d'):format(w.name,clip(w),total(w),w.quick,w.bag))
 end
end
RegisterCommand('frontiergunammo',status,false)
RegisterCommand('frontiergunbelt',function(_,args)
 if not active or job or truth(IsPedReloading(ped)) then return end
 local w=weapons[tonumber(args[1])]
 if not w then notice('Usage: /frontiergunbelt 1|2 empty|fill');return end
 if args[2]=='empty' then w.bag=w.bag+w.quick;w.quick=0
 elseif args[2]=='fill' then local n=math.min(w.capacity-w.quick,w.bag);w.quick=w.quick+n;w.bag=w.bag-n
 else notice('Usage: /frontiergunbelt 1|2 empty|fill');return end
 status()
end,false)
local R=joaat('INPUT_RELOAD')
local function reload(w)
 if job or truth(IsPedReloading(ped)) then return end
 local max=tonumber(GetMaxAmmoInClip(ped,w.hash,true)) or 0
 local loaded=clip(w)
 local needed=math.max(0,max-loaded)
 if needed==0 or max<=0 then return end
 local reserve=math.max(0,total(w)-loaded)
 -- Native reserve already paid for on an interrupted reload: never debit it twice.
 local missing=math.max(0,needed-reserve)
 local source=reserve>0 and 'native' or (w.quick>0 and 'quick' or 'bag')
 local amount=source=='native' and 0 or math.min(missing,w[source])
 if amount==0 and reserve==0 then notice('No compatible ammunition.');return end
 job={weapon=w,source=source,amount=amount,at=GetGameTimer()+(source=='bag' and 2000 or 0)}
 if source=='bag' then notice('Retrieving satchel ammunition…') end
end
local function step(w)
 local j=job
 if not j or GetGameTimer()<j.at then return end
 job=nil
 if j.weapon~=w then return end
 if j.amount>0 then
  local before=total(w)
  SetAmmoTypeForPedWeapon(ped,w.hash,w.ammo)
  AddAmmoToPedByType(ped,w.ammo,j.amount,0)
  local actual=math.max(0,math.min(j.amount,total(w)-before))
  w[j.source]=w[j.source]-actual
  log(('reload %s: requested %d, native accepted %d, clip %d, total %d'):format(j.source,j.amount,actual,clip(w),total(w)))
  if actual==0 and total(w)<=clip(w) then notice('Native ammunition injection failed; no test ammo deducted.');return end
 end
 MakePedReload(ped)
 local p,started=ped,GetGameTimer()
 CreateThread(function()
  Wait(250)
  if active and ped==p and current()==w and not truth(IsPedReloading(p)) then
   TaskReloadWeapon(p,false)
  end
  Wait(1000)
  if active and ped==p then log(('reload observation: clip %d, total %d, elapsed %dms'):format(clip(w),total(w),GetGameTimer()-started)) end
 end)
end
CreateThread(function()
 while true do
  if not active then Wait(150) else
   Wait(0)
   if PlayerPedId()~=ped or not LocalPlayer.state.IsInSession or truth(IsEntityDead(ped))
     or truth(IsPedOnMount(ped)) or truth(IsPedInAnyVehicle(ped,false)) then
    stop('character/death/mount/vehicle changed')
   else
    local w=current()
    if w then
     local menu=IsPauseMenuActive() or IsNuiFocused() or L.wheelOpen
     DisableControlAction(0,R,true)
     if menu then job=nil
     elseif IsDisabledControlJustPressed(0,R) then reload(w) end
     if job and (job.weapon~=w or IsControlPressed(0,0x07CE1E61)) then job=nil;log('retrieval cancelled') end
     if not menu then step(w) end
    else job=nil end
   end
  end
 end
end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then stop('resource stopped') end end)

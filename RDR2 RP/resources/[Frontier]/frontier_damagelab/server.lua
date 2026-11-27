local L=FrontierDamageLab
local E='frontier_damagelab:'
local sessions,ending={},{}
local function enabled()
 return GetConvarInt('frontier_damagelab_enabled',0)==1
end
local function isolated()
 for _,r in ipairs({'frontier_medical','frontier_needs','vorp_medic','vorp_metabolism'}) do
  local st=GetResourceState(r)
  if st=='started' or st=='starting' then return false,r end
 end
 return true
end
local function authorized(src)
 return src>0 and enabled() and IsPlayerAceAllowed(src,'frontier.damagelab')
end
local function notice(src,msg)
 print(('[frontier_damagelab] player=%d %s'):format(src,msg))
 if src>0 then TriggerClientEvent(E..'notice',src,msg) end
end
local function stop(src,why)
 local s=sessions[src]
 if not s then return end
 sessions[src]=nil
 ending[src]={id=s.id,mode=s.mode,expires=GetGameTimer()+10000}
 TriggerClientEvent(E..'stop',src,s.id,why)
 notice(src,'Trial ended: '..why)
end
local counter=0
RegisterCommand('damagelab',function(src,args)
 if src==0 then return notice(src,'Use /damagelab from an authorised player in-game.') end
 local mode=(args[1] or ''):lower()
 if mode=='off' then stop(src,'manual stop');return end
 if not authorized(src) then return notice(src,'Disabled or missing frontier.damagelab ACE.') end
 if not L.validMode(mode) then return notice(src,'Modes: observe, refill, buffer, guarded, invincible, off') end
 local ok,resource=isolated()
 if not ok then return notice(src,'Stop '..resource..' before running isolated trials.') end
 stop(src,'switch mode')
 counter=counter+1
 local id=('%d:%d:%d'):format(src,GetGameTimer(),counter)
 sessions[src]={id=id,mode=mode,expires=GetGameTimer()+L.durationMs,lastLog=0}
 TriggerClientEvent(E..'start',src,id,mode,L.durationMs)
 notice(src,'Trial granted: '..mode..' (180s). F8 console for full diagnostics.')
end,false)
RegisterNetEvent(E..'result',function(id,summary)
 local src=source;local s=sessions[src]
 if not s or s.id~=id then s=ending[src] end
 if not s or s.id~=id or type(summary)~='string' or #summary>400 or summary:find('[%c]') then return end
 if sessions[src]==s then sessions[src]=nil else ending[src]=nil end
 notice(src,'Client trial result ['..s.mode..'] '..summary)
end)
-- Observe but NEVER cancel damage. Network damage events may omit NPC/environmental hits.
AddEventHandler('weaponDamageEvent',function(sender,data)
 if type(data)~='table' then return end
 for src,s in pairs(sessions) do
  local ped=GetPlayerPed(src)
  if ped~=0 then
   local net=NetworkGetNetworkIdFromEntity(ped)
   local hit=net~=0 and data.hitGlobalId==net
   if not hit and net~=0 and type(data.hitGlobalIds)=='table' then
    for _,id in ipairs(data.hitGlobalIds) do if id==net then hit=true;break end end
   end
   if hit and GetGameTimer()-s.lastLog>=100 then
    s.lastLog=GetGameTimer()
    print(('[frontier_damagelab] weaponDamageEvent trial=%s sender=%s victim=%d weapon=%s damage=%s willKill=%s override=%s'):format(s.id,tostring(sender),src,tostring(data.weaponType),tostring(data.weaponDamage),tostring(data.willKill),tostring(data.overrideDefaultDamage)))
   end
  end
 end
end)
CreateThread(function()
 while true do
  Wait(500)
  local ok=isolated()
  for src,s in pairs(ending) do if GetGameTimer()>=s.expires then ending[src]=nil end end
  for src,s in pairs(sessions) do
   if not authorized(src) or not ok or GetGameTimer()>=s.expires then stop(src,'expired, disabled or conflicting resource started') end
  end
 end
end)
AddEventHandler('playerDropped',function() sessions[source]=nil;ending[source]=nil end)
AddEventHandler('onResourceStop',function(name)
 if name==GetCurrentResourceName() then
  for src in pairs(sessions) do stop(src,'resource stopping') end
 end
end)

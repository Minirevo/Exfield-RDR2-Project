local R=SkillsRules
local core=exports.frontier_core
local allowed={frontier_gathering=true,frontier_farming=true,frontier_production=true,frontier_property=true}
local function character(src) return core:GetPlayerCharacterId(src) end
local function valid(id) return type(id)=='string' and #id<=64 and id:match('^f_[a-f0-9]+$') end
local function stats(id,skill)
 if not valid(id) or not R.names[skill] then return false,'invalid_skill' end
 local ok,xp=pcall(MySQL.scalar.await,'SELECT COALESCE(SUM(xp),0) FROM frontier_skill_events WHERE character_id=? AND skill=?',{id,skill})
 if not ok then return false,'database_error' end
 return true,R.stats(xp)
end
exports('GetSkill',function(src,skill)
 if not allowed[GetInvokingResource()] then return false,'forbidden' end
 return stats(character(src),skill)
end)
exports('GetCharacterSkill',function(id,skill)
 if GetInvokingResource()~='frontier_production' then return false,'forbidden' end
 return stats(id,skill)
end)
exports('GrantXP',function(id,skill,xp,key)
 local owner=GetInvokingResource()
 if not allowed[owner] or not valid(id) or not R.names[skill] or type(xp)~='number' or xp%1~=0 or xp<1 or xp>1000 or type(key)~='string' or #key>48 or not key:match('^[a-zA-Z0-9_:%-]+$') then return false,'invalid_request' end
 key=owner..':'..key
 local ok,row=pcall(function()
  MySQL.update.await('INSERT IGNORE INTO frontier_skill_events(operation,character_id,skill,xp) VALUES(?,?,?,?)',{key,id,skill,xp})
  return MySQL.single.await('SELECT character_id,skill,xp FROM frontier_skill_events WHERE operation=?',{key})
 end)
 if not ok or not row then return false,'database_error' end
 if row.character_id~=id or row.skill~=skill or tonumber(row.xp)~=xp then return false,'request_conflict' end
 return true
end)
local last={}
RegisterNetEvent('frontier_skills:open',function()
 local src=source;local id=character(src);if not valid(id) then return end
 local now=GetGameTimer();if last[src] and now-last[src]<1000 then return end;last[src]=now
 local ok,rows=pcall(MySQL.query.await,'SELECT skill,SUM(xp) AS xp FROM frontier_skill_events WHERE character_id=? GROUP BY skill',{id})
 if not ok or character(src)~=id then return end
 local xp={};for _,row in ipairs(rows or {}) do xp[row.skill]=tonumber(row.xp) end
 local out={};for k,label in pairs(R.names) do local s=R.stats(xp[k]);s.name=label;s.id=k;out[#out+1]=s end
 table.sort(out,function(a,b)return a.name<b.name end)
 TriggerClientEvent('frontier_skills:view',src,out)
end)
AddEventHandler('playerDropped',function()last[source]=nil end)

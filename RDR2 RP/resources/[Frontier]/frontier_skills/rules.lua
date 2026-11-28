SkillsRules={}
local R=SkillsRules
R.names={logging='Logging',mining='Mining',prospecting='Prospecting',clay='Clay extraction',sand='Sand extraction',hunting='Hunting',fishing='Fishing',herbalism='Herbalism',farming='Farming',husbandry='Animal husbandry',blacksmithing='Blacksmithing',gunsmithing='Gunsmithing',carpentry='Carpentry',construction='Construction',cooking='Cooking',metallurgy='Metallurgy',leatherworking='Leatherworking',milling='Milling',ceramics='Ceramics',glassmaking='Glassmaking',medicine='Medicine',doctoring='Medical practice',jewellery='Jewellery',transportation='Transportation'}
function R.threshold(level)
 local n=math.max(0,math.min(99,level-1));return 100*n+8*n*n
end
function R.level(xp)
 local l=1;while l<100 and xp>=R.threshold(l+1) do l=l+1 end;return l
end
function R.stats(xp)
 xp=math.max(0,tonumber(xp) or 0);local level=R.level(xp);local t=(level-1)/99
 return {xp=xp,level=level,progress=level==100 and 1 or (xp-R.threshold(level))/(R.threshold(level+1)-R.threshold(level)),yield=1+.4*t,wear=1-.25*t,rare=1+.5*t,window=1+.2*t}
end

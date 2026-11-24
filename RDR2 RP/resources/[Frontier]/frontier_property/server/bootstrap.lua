PropertyRuntime=setmetatable({}, {__index=_G})
local _ENV=PropertyRuntime
C=assert(PropertyConfig, 'frontier_property: missing config.lua or PropertyConfig')
R=assert(PropertyRules, 'frontier_property: missing shared/rules.lua or PropertyRules')
core,inv,eco=exports.frontier_core,exports.frontier_inventory,exports.frontier_economy
E='frontier_property:'
S,revision,ready,busy=nil,0,false,false
rate,visits,workers,previews={}, {}, {}, {}

local VorpCore = exports.vorp_core:GetCore()
-- Frontier Inventory exclusively handles usable items. Retain needs load/save only.

RegisterNetEvent("vorpmetabolism:SaveLastStatus", function(status)
    local _source = source
    local UserCharacter = VorpCore.getUser(_source).getUsedCharacter
    UserCharacter.setStatus(status)
end)

RegisterNetEvent("vorpmetabolism:GetStatus", function()
    local _source = source
    local UserCharacter = VorpCore.getUser(_source).getUsedCharacter
    local s_status = UserCharacter.status
    if (#s_status > 5) then
        TriggerClientEvent("vorpmetabolism:StartFunctions", _source, s_status)
    else
        local status = json.encode({
            ['Hunger'] = Config["FirstHungerStatus"],
            ['Thirst'] = Config["FirstThirstStatus"],
            ['Metabolism'] = Config["FirstMetabolismStatus"]
        })
        UserCharacter.setStatus(status)
        TriggerClientEvent("vorpmetabolism:StartFunctions", _source, status)
    end
end)
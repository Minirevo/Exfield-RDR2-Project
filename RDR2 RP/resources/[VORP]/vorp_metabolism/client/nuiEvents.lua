NUIEvents = {}

NUIEvents.UpdateHUD = function()
    local thirst = PlayerStatus["Thirst"] / 1000;
    local hunger = PlayerStatus["Hunger"] / 1000;

    SendNUIMessage({
        action = "update",
        water = thirst,
        food = hunger
    })
end

NUIEvents.ShowHUD = function(show)
    if GetResourceState('frontier_hud')=='started' then
        local ok,active=pcall(function() return exports.frontier_hud:IsReplacingHud() end)
        if ok and active then show=false end
    end
    SendNUIMessage({
        action = show and 'show' or 'hide'
    })
end
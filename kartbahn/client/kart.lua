-- Eigenes Kart "KB-1": Physik, Tempolimit und Optik beim Spawn setzen
function ApplyKartSetup(veh, slot)
    local k = Config.Kart
    if not k or not k.Enabled or not DoesEntityExist(veh) then return end
    for field, value in pairs(k.Handling) do
        SetVehicleHandlingFloat(veh, 'CHandlingData', field, value + 0.0)
    end
    SetVehicleMaxSpeed(veh, k.MaxSpeed / 3.6)
    ModifyVehicleTopSpeed(veh, 1.0)
    SetVehicleModKit(veh, 0)
    SetVehicleColours(veh, k.Colors.primary, k.Colors.secondary)
    SetVehicleExtraColours(veh, k.Colors.pearl, k.Colors.wheels)
    SetVehicleDirtLevel(veh, 0.0)
    if k.NumberPlates and slot then
        SetVehicleNumberPlateText(veh, ('KB-%d'):format(slot))
    end
end

-- Anzeigename im Spiel
CreateThread(function()
    if Config.Kart and Config.Kart.Enabled then
        for _, m in ipairs(Config.KartModels) do AddTextEntry(m:upper(), Config.Kart.Name) end
    end
end)

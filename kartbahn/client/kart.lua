-- Eigenes Kart "KB-1": Physik (Preset), Tempolimit und Optik beim Spawn setzen
function GetKartPreset()
    return Config.KartPresets[Config.Kart.Preset] or Config.KartPresets.sport
end

function ApplyKartSetup(veh, number, color)
    local k = Config.Kart
    if not k or not k.Enabled or not DoesEntityExist(veh) then return end
    local p = GetKartPreset()
    for field, value in pairs(p.Handling) do
        SetVehicleHandlingFloat(veh, 'CHandlingData', field, value + 0.0)
    end
    if p.CenterOfMass then
        SetVehicleHandlingVector(veh, 'CHandlingData', 'vecCentreOfMassOffset', p.CenterOfMass)
    end
    SetVehicleMaxSpeed(veh, p.MaxSpeed / 3.6)
    ModifyVehicleTopSpeed(veh, 1.0)
    SetVehicleModKit(veh, 0)
    SetVehicleColours(veh, color or k.Colors.primary, k.Colors.secondary)
    SetVehicleExtraColours(veh, k.Colors.pearl, k.Colors.wheels)
    SetVehicleDirtLevel(veh, 0.0)
    if k.NumberPlates and number then
        SetVehicleNumberPlateText(veh, ('KB-%d'):format(number))
    end
end

-- Anzeigename im Spiel
CreateThread(function()
    if Config.Kart and Config.Kart.Enabled then
        for _, m in ipairs(Config.KartModels) do AddTextEntry(m:upper(), Config.Kart.Name) end
    end
end)

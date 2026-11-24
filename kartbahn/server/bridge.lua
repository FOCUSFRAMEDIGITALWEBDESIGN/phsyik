-- Framework-Bridge: ESX / QBCore / Standalone (ohne Framework ist alles kostenlos)
Bridge = { fw = 'none' }

local ESX, QBCore

local function detect()
    local mode = Config.Framework
    if (mode == 'auto' or mode == 'esx') and GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
        Bridge.fw = 'esx'
    elseif (mode == 'auto' or mode == 'qb') and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        Bridge.fw = 'qb'
    else
        Bridge.fw = 'none'
    end
    print(('[kartbahn] Framework: %s'):format(Bridge.fw))
end
detect()

local function license(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return 'src:' .. tostring(src)
end

function Bridge.GetIdentifier(src)
    if Bridge.fw == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if x then return x.identifier end
    elseif Bridge.fw == 'qb' then
        local p = QBCore.Functions.GetPlayer(src)
        if p then return p.PlayerData.citizenid end
    end
    return license(src)
end

function Bridge.GetName(src)
    if Bridge.fw == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if x and x.getName then return x.getName() end
    elseif Bridge.fw == 'qb' then
        local p = QBCore.Functions.GetPlayer(src)
        if p and p.PlayerData.charinfo then
            return ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname)
        end
    end
    return GetPlayerName(src) or ('Fahrer ' .. src)
end

-- Bargeld abziehen; true bei Erfolg
function Bridge.RemoveMoney(src, amount)
    if amount <= 0 or Bridge.fw == 'none' then return true end
    if Bridge.fw == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if not x or x.getMoney() < amount then return false end
        x.removeMoney(amount)
        return true
    elseif Bridge.fw == 'qb' then
        local p = QBCore.Functions.GetPlayer(src)
        if not p or p.Functions.GetMoney('cash') < amount then return false end
        return p.Functions.RemoveMoney('cash', amount, 'kartbahn') ~= false
    end
    return true
end

function Bridge.AddMoney(src, amount)
    if amount <= 0 or Bridge.fw == 'none' then return end
    if Bridge.fw == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if x then x.addMoney(amount) end
    elseif Bridge.fw == 'qb' then
        local p = QBCore.Functions.GetPlayer(src)
        if p then p.Functions.AddMoney('cash', amount, 'kartbahn') end
    end
end

function Bridge.IsFree()
    return Bridge.fw == 'none'
end

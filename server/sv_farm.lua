local QBCore = exports['qb-core']:GetCoreObject()

-- Handler event untuk memberi item ke pemain
RegisterNetEvent('farm_system:server:GiveRaw', function(type, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    amount = tonumber(amount) or 1  -- fallback ke 1 jika tidak dikirim

    if type == 'daging' then
        Player.Functions.AddItem('daging', math.random(1, 2))
        Player.Functions.AddItem('kulit', math.random(2, 3))
        Player.Functions.AddItem('milk', math.random(1, 3))
    else
        local item = Config.Farming.Items[type] -- Pastikan mapping di config
        if item then
            Player.Functions.AddItem(item, amount)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], 'add')
        else
            print(('[FARMING] Tidak ditemukan item untuk type: %s'):format(type))
        end
    end
end)

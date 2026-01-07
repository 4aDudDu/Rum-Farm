local QBCore = exports['qb-core']:GetCoreObject()

RegisterServerEvent('farm:server:sellItem', function(itemName, amount, price)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local item = Player.Functions.GetItemByName(itemName)

    if item and item.amount >= amount then
        Player.Functions.RemoveItem(itemName, amount)
        Player.Functions.AddMoney('cash', amount * price, "item-sold")
        TriggerClientEvent('QBCore:Notify', src, "Berhasil menjual x" .. amount .. " " .. item.label .. " seharga Rp" .. (amount * price), 'success')
    else
        TriggerClientEvent('QBCore:Notify', src, "Item tidak cukup untuk dijual", 'error')
    end
end)

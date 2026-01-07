local QBCore = exports['qb-core']:GetCoreObject()

CreateThread(function()
    local pedData = Config.SellerPed
    RequestModel(pedData.model)
    while not HasModelLoaded(pedData.model) do Wait(0) end

    local ped = CreatePed(0, pedData.model, pedData.coords.xyz, pedData.coords.w, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, pedData.scenario, 0, true)

    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'sell_items_ped',
            icon = 'fas fa-dollar-sign',
            label = 'Jual Hasil Panen',
            onSelect = function()
                OpenSellMenu()
            end,
        }
    })
end)

function OpenSellMenu()
    local menu = {
        {
            header = '📦 Penjualan Hasil Panen',
            isMenuHeader = true
        }
    }

    for _, item in pairs(Config.SellableItems) do
        table.insert(menu, {
            header = (item.label .. ' - Rp' .. item.price .. ' /pcs'),
            txt = 'Klik untuk menjual',
            params = {
                event = 'farm:sellItemPrompt',
                args = {
                    item = item.name,
                    label = item.label,
                    price = item.price
                }
            }
        })
    end

    table.insert(menu, {
        header = '❌ Tutup',
        txt = '',
        params = {
            event = ''
        }
    })

    exports['qb-menu']:openMenu(menu)
end

RegisterNetEvent('farm:sellItemPrompt', function(data)
    local input = exports['qb-input']:ShowInput({
        header = 'Jual ' .. data.label,
        submitText = 'Jual',
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'amount',
                text = 'Jumlah yang ingin dijual'
            }
        }
    })

    if input and input.amount and tonumber(input.amount) > 0 then
        TriggerServerEvent('farm:server:sellItem', data.item, tonumber(input.amount), data.price)
    end
end)